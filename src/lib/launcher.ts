/**
 * Lancement d'un jeu. Hors Tauri (simple onglet de navigateur), on se contente
 * de le signaler : le prototype reste utilisable pour juger le design.
 */
import type { Game } from './types';

const STEAM = 'C:/Program Files (x86)/Steam/steam.exe';

export async function play(game: Game): Promise<string> {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return `Hors application : « ${game.title} » serait lancé ici.`;

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
		watch(pid);
		return `${game.title} démarre…`;
	} catch (error) {
		return String(error);
	}
}

/** Surveille le processus pour savoir quand la partie se termine. */
async function watch(pid: number) {
	const { invoke } = await import('@tauri-apps/api/core');
	const timer = setInterval(async () => {
		if (!(await invoke<boolean>('is_running', { pid }))) {
			clearInterval(timer);
			window.dispatchEvent(new CustomEvent('game-exited'));
		}
	}, 2000);
}
