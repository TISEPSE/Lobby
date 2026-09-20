/** Un jeu de la bibliothèque, tel que le projet le manipule. */
export interface Game {
	id: string;
	appid: string;
	title: string;
	cover: string;
	hero: string;
	logo: string;
}

/** Ce que l'utilisateur a fait d'un jeu. Conservé à part de la liste des jeux. */
export interface GameStats {
	favorite: boolean;
	playtimeMinutes: number;
	/** Horodatage de la dernière partie, ou null si le jeu n'a jamais été lancé. */
	lastPlayed: number | null;
}

/** Sections de la barre du haut. */
export type Section = 'home' | 'library' | 'search' | 'settings';
