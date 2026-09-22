/**
 * Fiches Steam (jaquette, artwork, note, genres, résumé), récupérées par la
 * couche Rust. Le webview ne peut pas interroger Steam lui-même : ces points
 * d'entrée publics ne renvoient pas d'en-tête CORS.
 *
 * Aucune clé, aucun compte. Chaque fiche est mise en cache sur le disque par
 * Rust, et gardée ici pour la session.
 */
import type { Details } from './types';

/** Fiches déjà connues, par appid. Les composants les lisent directement. */
export const details = $state<Record<string, Details>>({});

/** Appids en cours de récupération, pour ne pas lancer deux fois la requête. */
const pending = new Set<string>();

/**
 * Demande la fiche d'un jeu si on ne l'a pas encore. Ne rend rien : le jour où
 * la réponse arrive, `details` se met à jour et l'affichage suit.
 */
export function ensureDetails(appid: string) {
	if (!appid || details[appid] || pending.has(appid)) return;
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return;

	pending.add(appid);
	void (async () => {
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			details[appid] = await invoke<Details>('steam_details', { appid, refresh: false });
		} catch {
			// Jeu inconnu de Steam ou machine hors ligne : on garde ce qu'on a.
		} finally {
			pending.delete(appid);
		}
	})();
}

/**
 * Affiche choisie par l'utilisateur pour un jeu : la jaquette quand elle
 * existe, l'artwork ou la bannière sinon. Gardée d'une session à l'autre.
 */
export type ArtStyle = 'auto' | 'artwork' | 'banner';

const ART_KEY = 'interface-console.art';

export const artStyles = $state<Record<string, ArtStyle>>(loadArt());

function loadArt(): Record<string, ArtStyle> {
	try {
		const raw = localStorage.getItem(ART_KEY);
		return raw ? JSON.parse(raw) : {};
	} catch {
		return {};
	}
}

/** Passe à l'affiche suivante et rend son nom, pour le dire à l'utilisateur. */
export function cycleArtStyle(appid: string): string {
	const order: ArtStyle[] = ['auto', 'artwork', 'banner'];
	const next = order[(order.indexOf(artStyles[appid] ?? 'auto') + 1) % order.length];
	artStyles[appid] = next;
	try {
		localStorage.setItem(ART_KEY, JSON.stringify(artStyles));
	} catch {
		/* sans stockage, le choix ne vaut que pour la session */
	}
	return { auto: 'Jaquette', artwork: 'Artwork', banner: 'Bannière' }[next];
}

/** Jaquette à afficher : celle résolue par Rust si elle est arrivée. */
export function coverOf(appid: string, fallback: string): string {
	return details[appid]?.cover || fallback;
}

/** Artwork de fond, même principe. */
export function heroOf(appid: string, fallback: string): string {
	return details[appid]?.hero || fallback;
}

/**
 * Visuels d'un jeu **sans identifiant Steam** : jeu installé hors launcher,
 * copié à la main, ou retiré du store (Fall Guys, Rocket League, Valorant…).
 *
 * Rust essaie plusieurs écritures du titre — celle du dossier, celle de
 * l'exécutable — auprès de Steam puis de Lutris. Sans ça, « Fallguys » ou
 * « rocketleague » ne correspondaient à rien et le jeu restait sans jaquette.
 */
export interface Artwork {
	cover: string;
	hero: string;
	logo: string;
	banner: string;
}

// v2 : on ne stocke plus des adresses web mais des fichiers locaux.
const ARTWORK_KEY = 'interface-console.artwork.v2';

export const artwork = $state<Record<string, Artwork>>(loadArtwork());

const artPending = new Set<string>();

function loadArtwork(): Record<string, Artwork> {
	try {
		const raw = localStorage.getItem(ARTWORK_KEY);
		return raw ? JSON.parse(raw) : {};
	} catch {
		return {};
	}
}

function saveArtwork() {
	try {
		localStorage.setItem(ARTWORK_KEY, JSON.stringify(artwork));
	} catch {
		/* sans stockage, on redemandera au prochain lancement */
	}
}

/**
 * Demande les visuels d'un jeu si on ne les a pas encore.
 *
 * Rust cherche l'image **et la télécharge** dans le dossier de l'application :
 * on ne garde donc pas une adresse web, mais un fichier. L'association jeu ↔
 * jaquette est faite une fois pour toutes — elle ne dépend plus d'une recherche
 * qui pourrait renvoyer autre chose demain, et l'interface s'affiche hors ligne.
 */
export function ensureArtwork(game: { id: string; title: string; appid?: string; executable?: string }) {
	if (!game?.id || artwork[game.id] || artPending.has(game.id)) return;
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return;

	artPending.add(game.id);
	void (async () => {
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			const { convertFileSrc } = await import('@tauri-apps/api/core');
			const saved = await invoke<Artwork>('cache_game_art', {
				gameId: game.id,
				title: game.title,
				appid: game.appid ?? null,
				executable: game.executable ?? null,
			});

			// Les chemins disque deviennent des adresses que le webview sait lire.
			artwork[game.id] = {
				cover: saved.cover ? convertFileSrc(saved.cover) : '',
				hero: saved.hero ? convertFileSrc(saved.hero) : '',
				logo: saved.logo ? convertFileSrc(saved.logo) : '',
				banner: saved.banner ? convertFileSrc(saved.banner) : '',
			};
			saveArtwork();
		} catch (error) {
			console.warn('Visuels indisponibles pour', game.title, error);
		} finally {
			artPending.delete(game.id);
		}
	})();
}

/** Oublie les visuels d'un jeu : la prochaine recherche repartira de zéro. */
export function forgetArtwork(gameId: string) {
	delete artwork[gameId];
	saveArtwork();
}
