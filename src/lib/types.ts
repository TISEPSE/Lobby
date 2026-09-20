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

/** Fiche d'un jeu récupérée auprès de Steam par la couche Rust. */
export interface Details {
	appid: string;
	title: string;
	cover: string;
	hero: string;
	genres: string[];
	release_date: string;
	summary: string;
	/** Note sur 5 ; 0 quand Metacritic ne connaît pas le jeu. */
	rating: number;
}

/** Sections de la barre du haut. */
export type Section = 'home' | 'library' | 'search' | 'settings';
