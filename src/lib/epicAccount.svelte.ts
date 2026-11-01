/**
 * Compte Epic Games : pseudo et temps de jeu par jeu, demandés aux serveurs
 * d'Epic par Rust (commande `epic_account`). Epic ne garde pas le temps de
 * jeu sur le disque, contrairement à Steam : il faut s'être connecté une fois
 * (`epic_login`, page de connexion officielle d'Epic).
 */

/** Un jeu de la bibliothèque Epic, installé ou non. */
export interface EpicGame {
	app_name: string;
	title: string;
	cover: string;
	hero: string;
}

interface RawAccount {
	account_id: string;
	display_name: string;
	playtime: { app_name: string; minutes: number }[];
	library: EpicGame[];
	/** Fiches du catalogue pas encore lues. */
	missing?: number;
}

export const epicAccount = $state<{
	/** Lecture terminée, compte trouvé ou non. */
	ready: boolean;
	/** Connexion en cours : fenêtre d'Epic ouverte, puis lecture du compte. */
	pending: boolean;
	/** Le catalogue se lit en arrière-plan : une requête par jeu, la première fois. */
	reading: boolean;
	/**
	 * Une session existe. Le pseudo ne le dit pas : un compte créé par un
	 * fournisseur (Steam, Google…) peut ne pas en avoir.
	 */
	connected: boolean;
	displayName: string;
	/** Minutes de jeu, par nom interne de jeu Epic (en minuscules). */
	playtime: Record<string, number>;
	/** Dernière erreur (jeton expiré, Epic injoignable…), vide sinon. */
	error: string;
	/** Toute la bibliothèque Epic (jeux seulement), installée ou non. */
	library: EpicGame[];
}>({ ready: false, pending: false, reading: false, connected: false, displayName: '', playtime: {}, error: '', library: [] });

/** Hôte des images Epic, qui les redimensionne à la demande. */
const EPIC_CDN = 'cdn1.epicgames.com';

/**
 * Image Epic à la taille voulue. Le catalogue donne des originaux, jusqu'à 2 Mo
 * pièce, pour des tuiles de 200 pixels : le serveur les réduit à la demande,
 * jusqu'à 80 fois moins lourds. Sur 48 tuiles, c'était ce qui figeait la page.
 */
export function epicImage(url: string, width: number, height: number): string {
	if (!url.includes(EPIC_CDN)) return url;
	return `${url}${url.includes('?') ? '&' : '?'}h=${height}&quality=medium&resize=1&w=${width}`;
}

/**
 * État du compte, pour le Profil et les écrans de bienvenue. Epic refuse la
 * session, ou ne répond pas : deux problèmes, deux messages.
 */
export function epicStatus(): string {
	const { pending, connected, error, reading, displayName, library, playtime } = epicAccount;
	if (pending) return 'Connexion…';
	if (!connected) return 'Non connecté';
	const who = displayName || 'Connecté';
	if (error) return `${who} · ${error.includes('refusé') ? 'session expirée' : 'Epic injoignable'}`;
	if (reading) return `${who} · lecture de la bibliothèque…`;
	const count = library.length || Object.keys(playtime).length;
	return `${who} · ${count} jeu${count > 1 ? 'x' : ''}`;
}

/** A sur le compte : se connecter, ou se reconnecter si la session a expiré. */
export function epicAction(): string {
	if (epicAccount.pending) return '';
	if (!epicAccount.connected) return 'Se connecter';
	return epicAccount.error ? 'Se reconnecter' : '';
}

async function tauri() {
	if (!(window as any).__TAURI_INTERNALS__) return null;
	return import('@tauri-apps/api/core');
}

export async function refreshEpicAccount() {
	const api = await tauri();
	if (!api) {
		epicAccount.ready = true;
		return;
	}
	try {
		const raw = await api.invoke<RawAccount | null>('epic_account');
		epicAccount.connected = raw !== null;
		epicAccount.displayName = raw?.display_name ?? '';
		epicAccount.playtime = Object.fromEntries(
			(raw?.playtime ?? []).map((play) => [play.app_name, play.minutes])
		);
		epicAccount.library = raw?.library ?? [];
		epicAccount.error = '';
		if (raw?.missing) void readCatalog();
	} catch (e) {
		// Session expirée ou Epic injoignable : on garde ce qu'on avait, et on
		// le dit dans le Profil plutôt que par un bandeau à chaque démarrage.
		// Sans session, Rust répond `null` : une erreur veut dire qu'il y en a une.
		epicAccount.connected = true;
		epicAccount.error = String(e);
	} finally {
		epicAccount.ready = true;
	}
}

/**
 * Fiches du catalogue qui manquent, en arrière-plan : la connexion est déjà
 * faite et l'interface reste libre pendant ces dizaines de secondes.
 */
async function readCatalog() {
	const api = await tauri();
	if (!api || epicAccount.reading) return;
	epicAccount.reading = true;
	try {
		epicAccount.library = await api.invoke<EpicGame[]>('epic_library');
	} catch (e) {
		console.warn('Bibliothèque Epic illisible :', e);
	} finally {
		epicAccount.reading = false;
	}
}

/**
 * Lit le compte au démarrage, et se réabonne au résultat des connexions.
 * `onLogin` reçoit le bilan à afficher (pseudo, ou erreur).
 */
export async function initEpicAccount(onLogin?: (ok: boolean, message: string) => void) {
	void refreshEpicAccount();
	if (!(window as any).__TAURI_INTERNALS__) return;
	const { listen } = await import('@tauri-apps/api/event');
	await listen<{ ok: boolean; message: string }>('epic-login', async (event) => {
		// « Connexion… » reste affiché jusqu'à la lecture du compte : la tuile
		// redisait sinon « Non connecté », et la connexion semblait avoir échoué.
		if (event.payload.ok) await refreshEpicAccount();
		epicAccount.pending = false;
		onLogin?.(event.payload.ok, event.payload.message);
	});
}

export async function loginEpic() {
	const api = await tauri();
	if (!api) return;
	epicAccount.pending = true;
	try {
		await api.invoke('epic_login');
	} catch (e) {
		epicAccount.pending = false;
		throw e;
	}
}

export async function logoutEpic() {
	const api = await tauri();
	if (!api) return;
	await api.invoke('epic_logout');
	epicAccount.connected = false;
	epicAccount.displayName = '';
	epicAccount.playtime = {};
	epicAccount.library = [];
	epicAccount.error = '';
}

/** Même règle que `normalize()` côté Rust : lettres et chiffres, en minuscules. */
function normalizeTitle(title: string): string {
	return (title.match(/[\p{L}\p{N}]/gu) ?? []).join('').toLowerCase();
}

/** Bibliothèque Epic indexée par titre normalisé → nom interne du jeu. */
const byTitle = $derived(
	new Map(epicAccount.library.map((game) => [normalizeTitle(game.title), game.app_name.toLowerCase()]))
);

/**
 * Minutes de jeu Epic d'un jeu (`epic-<appname>`). L'identifiant suffit : un
 * jeu Epic non installé n'est pas dans la liste des jeux de la bibliothèque.
 *
 * Un jeu repéré seulement par son dossier (`.egstore`, sans manifeste lisible)
 * a un identifiant tiré du titre (`epic-rocketleague`), pas du nom interne
 * (`Sugar`) : on le retrouve alors par son titre dans la bibliothèque du compte.
 */
export function epicMinutesOf(id: string): number {
	if (!id.startsWith('epic-')) return 0;
	const key = id.slice('epic-'.length);
	const direct = epicAccount.playtime[key];
	if (direct !== undefined) return direct;
	const appName = byTitle.get(key);
	return appName ? (epicAccount.playtime[appName] ?? 0) : 0;
}
