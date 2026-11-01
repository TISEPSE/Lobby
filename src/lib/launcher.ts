/**
 * Lancement d'un jeu. Hors Tauri (simple onglet de navigateur), on se contente
 * de le signaler : le prototype reste utilisable pour juger le design.
 */
import type { Game, Outcome } from './types';
import { games, markLaunched, programFolder, recordSession, unixPath } from './library.svelte.js';
import { endSession, session, setSessionWindow, startSession } from './session.svelte.js';

export async function play(game: Game): Promise<Outcome> {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return { ok: true, message: `Hors application : « ${game.title} » serait lancé ici.` };

	const { invoke } = await import('@tauri-apps/api/core');
	try {
		// Un jeu Epic passe par son launcher : lui seul lui donne la session du
		// compte. Un exécutable choisi à la main reste prioritaire.
		const launcherUrl = game.custom_executable ? '' : (game.launch_url ?? '');
		// Sans exécutable connu, c'est Steam qui sait où est le jeu, et son
		// protocole marche où qu'il soit installé, sous Windows comme sous Linux.
		const program =
			launcherUrl || game.executable || (game.appid ? `steam://rungameid/${game.appid}` : '');
		const args = !launcherUrl && game.executable ? (game.args ?? []) : [];
		if (!program) return { ok: false, message: `Impossible de lancer ${game.title} : exécutable inconnu.` };

		const pid = await invoke<number>('launch_game', {
			program,
			args,
		});
		markLaunched(game.id);
		if (launcherUrl) {
			// Le processus lancé rend la main aussitôt : le jeu arrivera plus tard.
			startSession(game.id, 0);
			watchLauncher(game);
			return { ok: true, message: `${game.title} démarre…` };
		}
		const steamApp = args[0] === '-applaunch' ? Number(args[1]) : game.executable ? 0 : Number(game.appid);
		// Un jeu Steam : le processus lancé est le client Steam, à ne jamais arrêter.
		startSession(game.id, steamApp ? 0 : pid, steamApp);
		if (steamApp) watchSteam(steamApp, game.id);
		else watch(pid, game.id, false, game);
		return { ok: true, message: `${game.title} démarre…` };
	} catch (error) {
		return { ok: false, message: `Impossible de lancer ${game.title} : ${error}` };
	}
}

/** Un programme ouvert, tel que le donne la commande Rust `running_programs`. */
interface RunningProgram {
	pid: number;
	path: string;
}

/** Délai entre deux recherches d'un jeu lancé hors de Lobby. */
const ADOPT_EVERY = 5000;

/**
 * Ce programme appartient-il au jeu ? Un jeu Steam a pour exécutable le client
 * Steam : ses fichiers sont sous `steamapps/common`, et Steam n'en lance qu'un.
 */
function belongsTo(game: Game, path: string): boolean {
	const program = unixPath(path);
	if (game.source === 'steam' && !game.custom_executable) return program.includes('/steamapps/common/');
	return !!game.executable && program.startsWith(`${unixPath(game.executable).replace(/\/[^/]*$/, '')}/`);
}

/** Processus ouverts du jeu : le lanceur a pu laisser la place au jeu lui-même. */
export async function gameProcesses(game: Game): Promise<number[]> {
	const { invoke } = await import('@tauri-apps/api/core');
	const programs = await invoke<RunningProgram[]>('running_programs').catch((): RunningProgram[] => []);
	return programs.filter((program) => belongsTo(game, program.path)).map((program) => program.pid);
}

/**
 * Le jeu dont le dossier contient un programme ouvert, le dossier le plus
 * précis d'abord. Pas de raccourci du Bureau : c'est souvent une application,
 * ouverte toute la journée.
 */
function findRunning(programs: RunningProgram[]): { game: Game; pid: number } | null {
	let best: { game: Game; pid: number } | null = null;
	let bestLength = 0;
	for (const game of games) {
		if (game.source === 'shortcut') continue;
		const folder = programFolder(game);
		if (!folder || folder.length <= bestLength) continue;
		const program = programs.find((p) => unixPath(p.path).startsWith(folder));
		if (program) {
			best = { game, pid: program.pid };
			bestLength = folder.length;
		}
	}
	return best;
}

/**
 * Un jeu lancé hors de Lobby (Steam, launcher Epic), ou déjà en cours quand
 * Lobby démarre : il devient la partie en cours, comme s'il avait été lancé
 * d'ici. Lobby n'en sait rien sinon, et proposerait de le relancer. Tant que
 * l'exécutable n'a pas `running_programs`, seuls les jeux Steam sont trouvés.
 */
async function adoptRunningGame() {
	if (session.id) return;
	const { invoke } = await import('@tauri-apps/api/core');
	const [appid, programs] = await Promise.all([
		invoke<number>('steam_running_app').catch(() => 0),
		invoke<RunningProgram[]>('running_programs').catch((): RunningProgram[] => []),
	]);
	// Un lancement a pu aboutir pendant ces lectures.
	if (session.id) return;

	const steamGame = appid ? games.find((game) => game.appid === String(appid)) : undefined;
	if (steamGame) {
		const pid = programs.find((p) => belongsTo(steamGame, p.path))?.pid ?? 0;
		markLaunched(steamGame.id);
		startSession(steamGame.id, 0, appid);
		if (pid) setSessionWindow(pid);
		watchSteam(appid, steamGame.id, true);
		return;
	}
	const found = findRunning(programs);
	if (!found) return;
	markLaunched(found.game.id);
	startSession(found.game.id, found.pid);
	setSessionWindow(found.pid);
	watch(found.pid, found.game.id, true, found.game);
}

/** Cherche régulièrement un jeu lancé hors de Lobby. Rend la fonction d'arrêt. */
export function watchRunningGames(): () => void {
	if (!(window as any).__TAURI_INTERNALS__) return () => {};
	void adoptRunningGame();
	const timer = setInterval(() => void adoptRunningGame(), ADOPT_EVERY);
	return () => clearInterval(timer);
}

/**
 * Fin de partie. Un jeu adopté (`quiet`) n'a pas été lancé depuis Lobby :
 * Lobby ne vient pas se poser par-dessus ce qu'on fait à ce moment-là.
 */
function gameExited(quiet: boolean) {
	window.dispatchEvent(new CustomEvent('game-exited', { detail: { quiet } }));
}

/**
 * Surveille le processus pour savoir quand la partie se termine, puis la
 * compte dans les statistiques.
 */
async function watch(pid: number, id: string, quiet = false, game?: Game) {
	const { invoke } = await import('@tauri-apps/api/core');
	const start = Date.now();
	const timer = setInterval(async () => {
		// Le processus lancé peut n'être qu'un lanceur : une fois la fenêtre du
		// jeu repérée, c'est elle qu'on suit.
		const target = session.id === id && session.pid ? session.pid : pid;
		if (!(await invoke<boolean>('is_running', { pid: target }))) {
			// Il a fini, mais le jeu a pris le relais dans son dossier : la partie
			// continue. Sinon, Lobby repassait devant un jeu en train de démarrer.
			const next = game && session.id === id ? (await gameProcesses(game))[0] : 0;
			if (next) return setSessionWindow(next);
			clearInterval(timer);
			endSession(id);
			// Moins d'une minute, ce n'est pas une partie : c'est le plus souvent
			// `steam -applaunch`, qui confie le jeu à Steam et rend la main aussitôt.
			const minutes = (Date.now() - start) / 60_000;
			if (minutes >= 1) recordSession(id, start, minutes);
			gameExited(quiet);
		}
	}, 2000);
}

/** Temps laissé à un launcher pour démarrer le jeu (mise à jour, synchronisation cloud…). */
const START_TIMEOUT = 10 * 60_000;

/**
 * Un jeu lancé par son launcher : on attend qu'il apparaisse dans son dossier,
 * puis on le suit comme les autres. Rien au bout de dix minutes (mise à jour
 * annulée, compte déconnecté) : on abandonne.
 */
function watchLauncher(game: Game) {
	const launched = Date.now();
	const timer = setInterval(async () => {
		if (session.id !== game.id) return clearInterval(timer);
		const [pid] = await gameProcesses(game);
		if (pid) {
			clearInterval(timer);
			if (!session.pid) setSessionWindow(pid);
			watch(pid, game.id, false, game);
		} else if (Date.now() - launched > START_TIMEOUT) {
			clearInterval(timer);
			endSession(game.id);
		}
	}, 2000);
}

/**
 * Un jeu Steam : `steam -applaunch` rend la main aussitôt, son processus ne dit
 * rien. C'est Steam qui sait quel jeu tourne (`steam_running_app`) : la partie
 * commence quand il annonce notre jeu, et finit quand il ne l'annonce plus.
 */
async function watchSteam(appid: number, id: string, quiet = false) {
	const { invoke } = await import('@tauri-apps/api/core');
	const launched = Date.now();
	// Un jeu adopté tourne déjà : pas de démarrage à attendre.
	let start = quiet ? launched : 0;
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
			else if (Date.now() - launched > START_TIMEOUT) {
				clearInterval(timer);
				endSession(id);
			}
			return;
		}
		if (running === appid) return;
		clearInterval(timer);
		endSession(id);
		const minutes = (Date.now() - start) / 60_000;
		if (minutes >= 1) recordSession(id, start, minutes);
		gameExited(quiet);
	}, 3000);
}
