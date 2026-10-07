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
	/**
	 * `false` pour un jeu Steam possédé mais pas installé (bibliothèque
	 * complète, clé de l'API Web) : sa fiche propose « Installer ».
	 */
	installed?: boolean;
	/**
	 * Exécutable choisi à la main (options → « Changer l'exécutable ») : la
	 * recherche automatique ne le remplace plus jamais.
	 */
	custom_executable?: boolean;
}

/** Ce que l'utilisateur a fait d'un jeu. Conservé à part de la liste des jeux. */
export interface GameStats {
	favorite: boolean;
	playtimeMinutes: number;
	/** Horodatage de la dernière partie, ou null si le jeu n'a jamais été lancé. */
	lastPlayed: number | null;
	/** Nombre de parties lancées ; absent des statistiques d'avant le journal. */
	sessions?: number;
}

/** Une partie terminée, gardée dans le journal qui nourrit les statistiques. */
export interface SessionRecord {
	id: string;
	/** Début de la partie (horodatage). */
	start: number;
	minutes: number;
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
	/** Captures du magasin ; absentes d'une fiche mise en cache avant les médias. */
	screenshots?: { thumb: string; full: string }[];
	/** Bandes-annonces, en flux HLS. */
	movies?: { name: string; thumb: string; hls: string }[];
	developers?: string[];
	publishers?: string[];
	/** Résumé long (« À propos » du magasin). */
	about?: string;
}

/** Une capture ou une vidéo de la fiche d'un jeu. */
export type MediaItem =
	| { kind: 'video'; thumb: string; src: string; name: string }
	| { kind: 'image'; thumb: string; src: string };

/** Une entrée du menu d'options d'une tuile. */
export interface TileAction {
	id: string;
	label: string;
	icon: string;
	/** Une ligne sous le libellé, quand l'action mérite une précision. */
	hint?: string;
}

/** Sections de la barre du haut. */
export type Section = 'home' | 'library' | 'settings' | 'profile';

/** Préférences utilisateur de la console. */
/**
 * Résultat d'une action qui peut échouer (lancer un jeu, éteindre la machine,
 * passer la main à Steam). Le message est destiné à l'écran ; `ok` décide du
 * ton : une erreur doit se voir et s'entendre, pas se fondre dans les
 * confirmations.
 */
export interface Outcome {
	ok: boolean;
	message: string;
}

export interface UserSettings {
	profile_name: string;
	avatar_path: string;
	button_layout: string;
	game_folders: string[];
	/** Retours sonores de l'interface. */
	sound_enabled: boolean;
	/** Clé SteamGridDB, propre à l'utilisateur : jamais dans le dépôt. */
	steamgriddb_key: string;
	/** Minutes d'inactivité avant l'écran de veille ; 0 = jamais. */
	screensaver_minutes: number;
	/** Ordre de la rangée d'accueil : dernière partie d'abord, ou par titre. */
	home_order: 'recent' | 'title';
	/** Filtre et tri de la bibliothèque, retrouvés d'une session à l'autre. */
	library_filter: string;
	library_sort: string;
	/** Volumes en pour cent (0 à 100) : général, puis par famille de sons. */
	volume_master: number;
	volume_menu: number;
	volume_alerts: number;
	volume_launch: number;
	volume_video: number;
}

/** Réglages de volume, dans l'ordre de la page Audio. */
export type VolumeKey = 'volume_master' | 'volume_menu' | 'volume_alerts' | 'volume_launch' | 'volume_video';