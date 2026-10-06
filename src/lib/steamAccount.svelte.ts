/**
 * Compte Steam de la machine, lu par Rust dans les fichiers du client Steam
 * (commande `steam_account`) : pseudo, photo, et pour chaque jeu joué la date
 * de dernière partie et le temps de jeu. Aucune clé, aucun mot de passe.
 *
 * C'est ce qui donne l'ordre « dernière partie » et le temps de jeu des jeux
 * Steam : lancés par `steam -applaunch`, ils échappent à notre propre mesure.
 */

export interface SteamPlay {
	/** Dernière partie, en millisecondes (comme `Date.now()`). */
	lastPlayed: number;
	/** Temps de jeu total, en minutes. */
	playtime: number;
}

interface RawAccount {
	steamid: string;
	persona: string;
	avatar: string;
	apps: { appid: string; last_played: number; playtime: number }[];
}

export const steamAccount = $state<{
	/** Lecture terminée, compte trouvé ou non. */
	ready: boolean;
	steamid: string;
	persona: string;
	/** Adresse lisible par le webview, ou vide. */
	avatar: string;
	/** Jeux joués, par appid. */
	apps: Record<string, SteamPlay>;
	/**
	 * Toute la bibliothèque (clé de l'API Web) : appid → nom. Vide sans clé ;
	 * les jeux qui n'y sont pas installés apparaissent dans la Bibliothèque.
	 */
	owned: Record<string, string>;
}>({ ready: false, steamid: '', persona: '', avatar: '', apps: {}, owned: {} });

interface OwnedGame {
	appid: string;
	name: string;
	playtime: number;
	last_played: number;
}

interface OwnedLibrary {
	steamid: string;
	fetched_at: number;
	games: OwnedGame[];
}

/** Connexion Steam en cours, et date de la dernière liste (ms ; 0 = jamais). */
export const steamLibrary = $state({ pending: false, fetchedAt: 0 });

/**
 * Relit la bibliothèque complète récupérée à la dernière connexion (gardée
 * chiffrée par Rust). Le temps de jeu et la dernière partie qu'elle donne
 * complètent ceux des fichiers locaux — un jeu joué sur un autre PC y figure.
 */
export async function loadSteamLibrary() {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return;
	try {
		const { invoke } = await import('@tauri-apps/api/core');
		const library = await invoke<OwnedLibrary | null>('steam_library');
		const owned: Record<string, string> = {};
		for (const game of library?.games ?? []) {
			owned[game.appid] = game.name;
			const known = steamAccount.apps[game.appid];
			steamAccount.apps[game.appid] = {
				lastPlayed: Math.max(known?.lastPlayed ?? 0, game.last_played * 1000),
				playtime: Math.max(known?.playtime ?? 0, game.playtime),
			};
		}
		steamAccount.owned = owned;
		steamLibrary.fetchedAt = (library?.fetched_at ?? 0) * 1000;
	} catch (e) {
		console.warn('Bibliothèque Steam illisible :', e);
	}
}

/**
 * Ouvre la connexion à Steam (page officielle, QR code ou identifiants). Le
 * résultat arrive par l'événement `steam-library` (voir `initSteamLibrary`).
 */
export async function loginSteamLibrary() {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return;
	const { invoke } = await import('@tauri-apps/api/core');
	steamLibrary.pending = true;
	try {
		await invoke('steam_library_login');
	} catch (e) {
		steamLibrary.pending = false;
		throw e;
	}
}

/** Oublie la liste enregistrée : seuls les jeux installés restent. */
export async function forgetSteamLibrary() {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return;
	const { invoke } = await import('@tauri-apps/api/core');
	await invoke('steam_library_forget');
	steamAccount.owned = {};
	steamLibrary.fetchedAt = 0;
}

/** Charge la liste enregistrée et suit les connexions ; `onDone` reçoit le bilan. */
export async function initSteamLibrary(onDone?: (ok: boolean, message: string) => void) {
	await loadSteamLibrary();
	if (!(window as any).__TAURI_INTERNALS__) return;
	const { listen } = await import('@tauri-apps/api/event');
	await listen<{ ok: boolean; message: string }>('steam-library', async (event) => {
		steamLibrary.pending = false;
		if (event.payload.ok) await loadSteamLibrary();
		onDone?.(event.payload.ok, event.payload.message);
	});
}

export async function initSteamAccount() {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) {
		steamAccount.ready = true;
		return;
	}
	try {
		const { invoke, convertFileSrc } = await import('@tauri-apps/api/core');
		const raw = await invoke<RawAccount | null>('steam_account');
		if (raw) {
			const apps: Record<string, SteamPlay> = {};
			for (const app of raw.apps) {
				apps[app.appid] = { lastPlayed: app.last_played * 1000, playtime: app.playtime };
			}
			steamAccount.steamid = raw.steamid;
			steamAccount.persona = raw.persona;
			steamAccount.avatar = raw.avatar ? convertFileSrc(raw.avatar) : '';
			steamAccount.apps = apps;
		}
	} catch (e) {
		console.warn('Compte Steam illisible :', e);
	} finally {
		steamAccount.ready = true;
	}
}

/** Ce que Steam sait d'un jeu, d'après son appid. */
export function steamPlayOf(appid: string | null | undefined): SteamPlay | undefined {
	return appid ? steamAccount.apps[appid] : undefined;
}
