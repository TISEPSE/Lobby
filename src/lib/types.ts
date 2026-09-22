/** Un jeu de la bibliothèque, tel que le projet le manipule. */
export interface Game {
	id: string;
	title: string;
	appid?: string | null;
	cover: string;
	hero: string;
	logo: string;
	source?: string;
	executable?: string;
	args?: string[];
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
	/** Logo détouré, s'il existe : sert à composer une jaquette. */
	logo: string;
	/** Bannière 16/9, jamais affichée telle quelle dans une tuile. */
	banner: string;
	genres: string[];
	release_date: string;
	summary: string;
	/** Note sur 5 ; 0 quand Metacritic ne connaît pas le jeu. */
	rating: number;
}

/** Une entrée du menu d'options d'une tuile. */
export interface TileAction {
	id: string;
	label: string;
	icon: string;
	/** Une ligne sous le libellé, quand l'action mérite une précision. */
	hint?: string;
}

/** Sections de la barre du haut. */
export type Section = 'home' | 'library' | 'search' | 'settings';

/** Préférences utilisateur de la console. */
export interface UserSettings {
	profile_name: string;
	avatar_path: string;
	button_layout: string;
	game_folders: string[];
	/** Vidéo jouée au lancement ; vide pour aller droit à l'accueil. */
	boot_video: string;
	boot_video_enabled: boolean;
}