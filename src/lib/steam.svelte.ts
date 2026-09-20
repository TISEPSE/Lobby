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
