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

/** Une affiche proposée dans « Changer l'affiche ». */
export interface ArtCandidate {
	url: string;
	thumb: string;
	source: string;
	kind: 'cover' | 'hero' | 'banner';
}

/**
 * Toutes les affiches trouvables pour un jeu. La recherche prend quelques
 * secondes (Steam, Lutris, SteamGridDB) : l'appelant affiche une attente.
 */
export async function artCandidates(game: {
	title: string;
	appid?: string;
	executable?: string;
}): Promise<ArtCandidate[]> {
	const tauri = (window as any).__TAURI_INTERNALS__;
	// Hors application, on montre ce que le CDN Steam expose pour ce jeu : le
	// front reste utilisable pour juger la fenêtre, comme pour le lancement.
	if (!tauri) return previewCandidates(game.appid);
	const { invoke } = await import('@tauri-apps/api/core');
	return invoke<ArtCandidate[]>('art_candidates', {
		title: game.title,
		appid: game.appid ?? null,
		executable: game.executable ?? null,
	});
}

/**
 * Retient l'affiche choisie : Rust la télécharge à la place de la précédente,
 * et l'interface lit désormais ce fichier. Le choix survit donc au
 * redémarrage, et ne dépend plus d'une recherche en ligne.
 */
export type ArtTarget = 'cover' | 'background';

export async function chooseArt(
	gameId: string,
	candidate: ArtCandidate,
	target: ArtTarget = 'cover'
): Promise<void> {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return;
	const { invoke, convertFileSrc } = await import('@tauri-apps/api/core');
	// Un fond est toujours rangé comme « hero », quelle que soit l'image
	// choisie : c'est ce champ que lit l'arrière-plan.
	const kind = target === 'background' ? 'hero' : candidate.kind;
	const local = await invoke<string>('pick_game_art', {
		gameId,
		url: candidate.url,
		kind,
	});

	const current = artwork[gameId] ?? { cover: '', hero: '', logo: '', banner: '' };
	// Rust écrit l'image sous un nom horodaté : l'adresse change, donc le
	// webview affiche la nouvelle au lieu de resservir l'ancienne. Un paramètre
	// d'URL ne marcherait pas — le protocole d'accès aux fichiers le prendrait
	// pour une partie du chemin.
	artwork[gameId] = { ...current, [kind]: convertFileSrc(local) };
	saveArtwork();

	// Changer le fond ne doit pas changer la tuile : le style de l'affiche
	// n'est touché que lorsqu'on choisit une jaquette.
	if (target === 'background') return;

	if (candidate.kind === 'cover') {
		artStyles[gameId] = 'auto';
	} else if (candidate.kind === 'banner') {
		artStyles[gameId] = 'banner';
	} else {
		artStyles[gameId] = 'artwork';
	}
	try {
		localStorage.setItem(ART_KEY, JSON.stringify(artStyles));
	} catch {
		/* sans stockage, le choix ne vaut que pour la session */
	}
}

/** Candidats visibles dans un simple onglet de navigateur, sans Rust. */
function previewCandidates(appid?: string): ArtCandidate[] {
	if (!appid) return [];
	const cdn = 'https://cdn.cloudflare.steamstatic.com/steam/apps';
	const kinds: [string, ArtCandidate['kind']][] = [
		[`${cdn}/${appid}/library_600x900_2x.jpg`, 'cover'],
		[`${cdn}/${appid}/library_600x900.jpg`, 'cover'],
		[`${cdn}/${appid}/library_hero.jpg`, 'hero'],
		[`${cdn}/${appid}/header.jpg`, 'banner'],
		[`${cdn}/${appid}/capsule_616x353.jpg`, 'banner'],
	];
	return kinds.map(([url, kind]) => ({ url, thumb: url, source: 'Steam', kind }));
}
