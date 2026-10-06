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
		watch(pid, game.id);
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
