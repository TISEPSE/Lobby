/**
 * Lancement d'un jeu. Hors Tauri (simple onglet de navigateur), on se contente
 * de le signaler : le prototype reste utilisable pour juger le design.
 */
import type { Game, Outcome } from './types';
import { markLaunched, recordSession } from './library.svelte.js';

const STEAM = 'C:/Program Files (x86)/Steam/steam.exe';

export async function play(game: Game): Promise<Outcome> {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return { ok: true, message: `Hors application : « ${game.title} » serait lancé ici.` };

	const { invoke } = await import('@tauri-apps/api/core');
	try {
		let program = STEAM;
		let args: string[] = [];

		if (game.executable) {
			program = game.executable;
			args = game.args ?? [];
		} else if (game.appid) {
			program = STEAM;
			args = ['-applaunch', game.appid];
		}

		const pid = await invoke<number>('launch_game', {
			program,
			args,
		});
		markLaunched(game.id);
		const steamApp = args[0] === '-applaunch' ? Number(args[1]) : 0;
		if (steamApp) watchSteam(steamApp, game.id);
		else watch(pid, game.id);
		return { ok: true, message: `${game.title} démarre…` };
	} catch (error) {
		return { ok: false, message: `Impossible de lancer ${game.title} : ${error}` };
	}
}

/**
 * Surveille le processus pour savoir quand la partie se termine, puis la
 * compte dans les statistiques.
 */
async function watch(pid: number, id: string) {
	const { invoke } = await import('@tauri-apps/api/core');
	const start = Date.now();
	const timer = setInterval(async () => {
		if (!(await invoke<boolean>('is_running', { pid }))) {
			clearInterval(timer);
			// Moins d'une minute, ce n'est pas une partie : c'est le plus souvent
			// `steam -applaunch`, qui confie le jeu à Steam et rend la main aussitôt.
			const minutes = (Date.now() - start) / 60_000;
			if (minutes >= 1) recordSession(id, start, minutes);
			window.dispatchEvent(new CustomEvent('game-exited'));
		}
	}, 2000);
}

/** Temps laissé à Steam pour démarrer le jeu (mise à jour, synchronisation cloud…). */
const STEAM_START_TIMEOUT = 10 * 60_000;

/**
 * Un jeu Steam : `steam -applaunch` rend la main aussitôt, son processus ne dit
 * rien. C'est Steam qui sait quel jeu tourne (`steam_running_app`) : la partie
 * commence quand il annonce notre jeu, et finit quand il ne l'annonce plus.
 */
async function watchSteam(appid: number, id: string) {
	const { invoke } = await import('@tauri-apps/api/core');
	const launched = Date.now();
	let start = 0;
	const timer = setInterval(async () => {
		let running = 0;
		try {
			running = await invoke<number>('steam_running_app');
		} catch {
			running = 0;
		}
		if (!start) {
			if (running === appid) start = Date.now();
			// Le jeu n'a jamais démarré (annulé, erreur Steam) : on abandonne.
			else if (Date.now() - launched > STEAM_START_TIMEOUT) clearInterval(timer);
			return;
		}
		if (running === appid) return;
		clearInterval(timer);
		const minutes = (Date.now() - start) / 60_000;
		if (minutes >= 1) recordSession(id, start, minutes);
		window.dispatchEvent(new CustomEvent('game-exited'));
	}, 3000);
}
