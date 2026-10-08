/**
 * Partie en cours : le jeu lancé depuis Lobby, tant qu'il tourne. C'est ce
 * qui permet « Revenir au jeu » et « Quitter le jeu » (accueil, menu du jeu
 * ouvert par View + Menu pendant la partie).
 *
 * - `launchPid` : le processus démarré par Lobby (0 pour un jeu Steam :
 *   c'est le client Steam, qu'on ne doit jamais arrêter) ;
 * - `pid` : le processus de la fenêtre du jeu, repérée par l'écran de
 *   lancement (`focus_game_window`) — le plus sûr à arrêter.
 */
export const session = $state<{
	id: string | null;
	pid: number;
	launchPid: number;
	/** Jeu Steam : son appid (0 sinon). Steam dit quand il tourne vraiment. */
	steamAppid: number;
}>({
	id: null,
	pid: 0,
	launchPid: 0,
	steamAppid: 0,
});

export function startSession(id: string, launchPid: number, steamAppid = 0) {
	session.id = id;
	session.pid = 0;
	session.launchPid = launchPid;
	session.steamAppid = steamAppid;
}

/** La fenêtre du jeu est trouvée : c'est son processus qu'on suivra. */
export function setSessionWindow(pid: number) {
	if (session.id) session.pid = pid;
}

/** Fin de partie ; sans `id`, quelle que soit la partie en cours. */
export function endSession(id?: string) {
	if (id && session.id !== id) return;
	session.id = null;
	session.pid = 0;
	session.launchPid = 0;
	session.steamAppid = 0;
}

/** Le processus à viser pour revenir au jeu ou le quitter (0 : inconnu). */
export function sessionPid(): number {
	return session.pid || session.launchPid;
}
