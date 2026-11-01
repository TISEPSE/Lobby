/**
 * État de la bibliothèque : les jeux, plus ce que l'utilisateur en fait
 * (favoris, temps de jeu, dernière partie).
 *
 * Les jeux viennent du fichier de données ; ce qui est propre à l'utilisateur
 * est gardé à part et persisté, pour qu'un rafraîchissement de la liste des
 * jeux installés n'efface jamais ses favoris.
 */
import rawGames from './data/games.json';
import type { Game, GameStats, SessionRecord } from './types';
import { steamPlayOf } from './steamAccount.svelte.js';
import { epicImage, epicMinutesOf } from './epicAccount.svelte.js';
import { details } from './steam.svelte.js';
import { persist, restore } from './persist';

const STORAGE_KEY = 'interface-console.stats';
const LIBRARY_KEY = 'interface-console.library';
const SESSIONS_KEY = 'interface-console.sessions';
const HIDDEN_KEY = 'interface-console.hidden-games';

export function cleanTitle(title: string): string {
	return title
		.replace(/marvel'?s\s+/gi, '')
		.replace(/\b(deluxe|definitive|game of the year|goty|collector'?s?|edition|remastered|v\d+[\d.]*)\b/gi, '')
		.replace(/\b(by\s+[a-z0-9_-]+)\b/gi, '')
		.replace(/\ball\s+dlc\b/gi, '')
		.replace(/[^a-zA-Z0-9]/g, '')
		.toLowerCase()
		.trim();
}

export function deduplicateGames(list: Game[]): Game[] {
	const map = new Map<string, Game>();
	const exeMap = new Map<string, string>();

	for (const g of list) {
		const key = cleanTitle(g.title) || g.id;
		const normExe = g.executable ? g.executable.toLowerCase().replace(/\\/g, '/') : '';
		const isGenericLauncher =
			normExe.endsWith('/steam.exe') ||
			normExe.endsWith('/ealauncher.exe') ||
			normExe.endsWith('/epicgameslauncher.exe');

		let matchedKey = map.has(key)
			? key
			: !isGenericLauncher && normExe && exeMap.has(normExe)
				? exeMap.get(normExe)!
				: null;

		if (matchedKey && map.has(matchedKey)) {
			const existing = map.get(matchedKey)!;
			if (!existing.cover && g.cover) existing.cover = g.cover;
			if (!existing.hero && g.hero) existing.hero = g.hero;
			if (!existing.logo && g.logo) existing.logo = g.logo;
			if (!existing.appid && g.appid) existing.appid = g.appid;
			if (!existing.launch_url && g.launch_url) existing.launch_url = g.launch_url;
			if (g.title.length > existing.title.length && g.title.includes(' ')) {
				existing.title = g.title;
			} else if (/[A-Z]/.test(g.title) && !/[A-Z]/.test(existing.title)) {
				existing.title = g.title;
			}
			if ((g.source === 'steam' || g.source === 'epic') && existing.source !== 'steam' && existing.source !== 'epic') {
				existing.source = g.source;
				existing.executable = g.executable;
				existing.args = g.args;
				existing.id = g.id;
			}
		} else {
			map.set(key, { ...g });
			if (normExe && !isGenericLauncher) {
				exeMap.set(normExe, key);
			}
		}
	}
	return Array.from(map.values());
}

/**
 * Jeux installés. Dans l'application, la liste part **vide** : elle vient de
 * `library.json` ou de la détection. Les jeux de `data/games.json` ne servent
 * qu'hors application (onglet de navigateur, captures) — ils étaient livrés
 * dans l'installeur, et un PC neuf affichait les jeux de quelqu'un d'autre.
 */
export const games = $state<Game[]>(
	(globalThis as any).__TAURI_INTERNALS__ ? [] : deduplicateGames(rawGames as Game[])
);

/** Statistiques par identifiant de jeu. */
export const stats = $state<Record<string, GameStats>>(load());

/**
 * Journal des parties, du plus ancien au plus récent. Les cumuls de `stats`
 * suffisent à la bibliothèque ; l'écran Statistiques a besoin de savoir *quand*
 * on a joué, pour découper par période.
 */
export const sessions = $state<SessionRecord[]>(loadSessions());

/**
 * Entrées retirées à la main : la détection prend aussi des applications pour
 * des jeux (Android Studio, par son raccourci du Bureau). Elles sont gardées à
 * part, sinon la recherche du démarrage les rajouterait aussitôt ; Réglages →
 * Jeux permet de les rétablir.
 */
export const hiddenGames = $state<Game[]>([]);

/** Une partie vue hors de Lobby, telle que la donne la commande Rust `played_elsewhere`. */
interface PlayedElsewhere {
	/** Exécutable lancé (Windows), vide sinon. */
	path: string;
	/** Nom interne Epic (`Sugar`), vide sinon. */
	app_name: string;
	/** Horodatage, 0 s'il est dans `local_time`. */
	at: number;
	/** Heure locale sans fuseau, que `Date.parse` lit comme telle. */
	local_time: string;
}

const playedElsewhere = $state<PlayedElsewhere[]>([]);

export const unixPath = (path: string) => path.replace(/\\/g, '/').toLowerCase();

/**
 * Dossier où chercher les programmes d'un jeu, ou vide. On compare les dossiers
 * et non les exécutables : la détection retient parfois un lanceur
 * (`Launcher.exe` pour Rocket League, dont le jeu est `RocketLeague.exe`).
 *
 * Vide pour un jeu Steam (son exécutable est le client Steam, et c'est Steam qui
 * le suit) et pour un exécutable posé trop haut (`C:/Program Files` engloberait
 * tout).
 */
export function programFolder(game: Game): string {
	if (!game.executable || game.source === 'steam') return '';
	const folder = unixPath(game.executable).replace(/\/[^/]*$/, '');
	return folder.split('/').length < 3 ? '' : `${folder}/`;
}

/**
 * Dernière partie de chaque jeu vue hors de Lobby, par identifiant. Recalculée
 * quand la liste change : sur un PC neuf, les jeux n'arrivent qu'avec la
 * détection, après cette lecture.
 */
const elsewhereDates = $derived.by(() => {
	const dates: Record<string, number> = {};
	const folders = games.map((game) => ({ id: game.id, folder: programFolder(game) })).filter((g) => g.folder);
	for (const seen of playedElsewhere) {
		const at = seen.at || Date.parse(seen.local_time) || 0;
		const path = unixPath(seen.path);
		const epicId = `epic-${seen.app_name}`.toLowerCase();
		const owners = seen.app_name
			? games.filter((game) => game.id.toLowerCase() === epicId)
			: folders.filter(({ folder }) => path.startsWith(folder));
		for (const { id } of owners) dates[id] = Math.max(dates[id] ?? 0, at);
	}
	return dates;
});

async function loadPlayedElsewhere() {
	if (!(window as any).__TAURI_INTERNALS__) return;
	const { invoke } = await import('@tauri-apps/api/core');
	// Une date en moins ne doit jamais empêcher le démarrage.
	const found = await invoke<PlayedElsewhere[] | null>('played_elsewhere').catch(() => null);
	playedElsewhere.splice(0, playedElsewhere.length, ...(found ?? []));
}

/**
 * Charge la bibliothèque, puis les statistiques et le journal depuis le disque
 * (`persist.ts`) : sans ça, l'exécutable compilé — qui n'a pas le stockage de
 * navigateur de `tauri dev` — n'avait ni dernières parties, ni temps de jeu.
 */
export async function initLibrary() {
	await loadGames();
	await loadPlayedElsewhere();
	const savedStats = await restore<Record<string, GameStats>>('stats', STORAGE_KEY);
	if (savedStats && typeof savedStats === 'object') Object.assign(stats, savedStats);
	const savedSessions = await restore<SessionRecord[]>('sessions', SESSIONS_KEY);
	if (Array.isArray(savedSessions)) sessions.splice(0, sessions.length, ...savedSessions);
	const savedHidden = await restore<Game[]>('hidden-games', HIDDEN_KEY);
	if (Array.isArray(savedHidden)) hiddenGames.splice(0, hiddenGames.length, ...savedHidden);
}

async function loadGames() {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (tauri) {
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			const loaded = await invoke<Game[]>('load_library');
			if (loaded && loaded.length > 0) {
				const cleaned = deduplicateGames(loaded);
				games.length = 0;
				games.push(...cleaned);
				if (cleaned.length !== loaded.length) {
					saveLibrary();
				}
				return;
			}
		} catch (e) {
			console.warn('Impossible de charger la bibliothèque via Tauri:', e);
		}
	}

	try {
		const raw = localStorage.getItem(LIBRARY_KEY);
		if (raw) {
			const parsed = JSON.parse(raw);
			if (Array.isArray(parsed) && parsed.length > 0) {
				const cleaned = deduplicateGames(parsed);
				games.length = 0;
				games.push(...cleaned);
				// Rien sur le disque : on y recopie la bibliothèque du navigateur.
				saveLibrary();
			}
		}
	} catch {}
}

export async function saveLibrary() {
	try {
		localStorage.setItem(LIBRARY_KEY, JSON.stringify(games));
	} catch {}

	const tauri = (window as any).__TAURI_INTERNALS__;
	if (tauri) {
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			await invoke('save_library', { games });
		} catch (e) {
			console.warn('Impossible de sauvegarder la bibliothèque via Tauri:', e);
		}
	}
}

export function addGames(newGames: Game[]) {
	const prevCount = games.length;
	const combined = deduplicateGames([...games, ...newGames]);
	const added = combined.length - prevCount;
	games.length = 0;
	games.push(...combined);
	if (added > 0 || combined.length !== prevCount) {
		saveLibrary();
	}
	return Math.max(0, added);
}

export interface SyncReport {
	added: number;
	updated: number;
	removed: number;
}

/**
 * Synchronise la bibliothèque avec un nouveau scan, sans rien demander :
 * - un jeu détecté qu'on ne connaît pas est **ajouté** ;
 * - un jeu connu dont le dossier a bougé reçoit son **nouveau chemin** ;
 * - un jeu connu qui n'est plus détecté **et** dont l'exécutable n'existe plus
 *   est **retiré**. S'il existe encore (dossier hors des dossiers suivis), on
 *   le garde : la synchronisation ne doit jamais faire perdre un jeu jouable.
 *
 * Favoris et temps de jeu sont rangés sous l'identifiant du jeu : ils
 * survivent à la mise à jour du chemin.
 */
export async function syncLibrary(
	scanned: Game[],
	exists: (paths: string[]) => Promise<boolean[]>
): Promise<SyncReport> {
	const report: SyncReport = { added: 0, updated: 0, removed: 0 };
	const matched = new Set<string>();

	for (const found of scanned) {
		if (isHidden(found)) continue;
		const key = cleanTitle(found.title);
		const known = games.find(
			(g) =>
				g.id === found.id ||
				(found.appid && g.appid === found.appid) ||
				(key && cleanTitle(g.title) === key)
		);
		if (!known) {
			games.push({ ...found });
			matched.add(found.id);
			report.added += 1;
			continue;
		}
		matched.add(known.id);
		const moved =
			(found.executable ?? '') !== (known.executable ?? '') ||
			JSON.stringify(found.args ?? []) !== JSON.stringify(known.args ?? []);
		// Un exécutable choisi à la main reste tel quel : le scan s'était trompé.
		if (moved && found.executable && !known.custom_executable) {
			known.executable = found.executable;
			known.args = found.args;
			report.updated += 1;
		}
		if (!known.appid && found.appid) known.appid = found.appid;
		if (found.launch_url && found.launch_url !== known.launch_url) {
			known.launch_url = found.launch_url;
			report.updated += 1;
		}
	}

	// Les jeux que le scan n'a pas retrouvés : on ne retire que ceux dont
	// l'exécutable a disparu. Un jeu Steam a pour « exécutable » le client
	// Steam, qui existe toujours : lui est retiré s'il n'est plus détecté
	// (désinstallé) — sauf si le scan n'a trouvé aucun jeu Steam, signe que
	// Steam était introuvable, pas que tout a été désinstallé.
	const isSteam = (g: Game) => g.source === 'steam' || (!g.executable && !!g.appid);
	const steamSeen = scanned.some(isSteam);
	const missing = games.filter((g) => !matched.has(g.id));
	const withExe = missing.filter((g) => !isSteam(g) && g.executable);
	const alive = withExe.length ? await exists(withExe.map((g) => g.executable!)) : [];
	const gone = new Set<string>([
		...withExe.filter((_, i) => !alive[i]).map((g) => g.id),
		...(steamSeen ? missing.filter(isSteam).map((g) => g.id) : []),
	]);
	if (gone.size > 0) {
		const kept = games.filter((g) => !gone.has(g.id));
		report.removed = games.length - kept.length;
		games.length = 0;
		games.push(...kept);
	}

	if (report.added || report.updated || report.removed) await saveLibrary();
	return report;
}

/**
 * Exécutable choisi à la main pour un jeu (la détection s'était trompée) :
 * il est lancé directement, sans arguments, et la recherche automatique ne le
 * remplacera plus.
 */
export function setGameExecutable(id: string, path: string) {
	const game = games.find((g) => g.id === id);
	if (!game) return;
	game.executable = path.replace(/\\/g, '/');
	game.args = [];
	game.custom_executable = true;
	saveLibrary();
}

export function removeGame(id: string) {
	const idx = games.findIndex((g) => g.id === id);
	if (idx !== -1) {
		games.splice(idx, 1);
		saveLibrary();
	}
}

/** Retirée à la main : même identifiant, ou même titre sous un autre identifiant. */
export function isHidden(game: Game): boolean {
	const key = cleanTitle(game.title);
	return hiddenGames.some((h) => h.id === game.id || (!!key && cleanTitle(h.title) === key));
}

/** Retire une entrée de la bibliothèque, sans rien désinstaller. */
export function hideGame(id: string) {
	const game = games.find((g) => g.id === id);
	if (!game) return;
	hiddenGames.push({ ...game });
	persist('hidden-games', HIDDEN_KEY, hiddenGames);
	removeGame(id);
}

/** Remet dans la bibliothèque une entrée retirée. */
export function restoreGame(id: string) {
	const index = hiddenGames.findIndex((g) => g.id === id);
	if (index === -1) return;
	const [game] = hiddenGames.splice(index, 1);
	persist('hidden-games', HIDDEN_KEY, hiddenGames);
	addGames([{ ...game }]);
}

function load(): Record<string, GameStats> {
	try {
		const raw = localStorage.getItem(STORAGE_KEY);
		return raw ? JSON.parse(raw) : {};
	} catch {
		// Stockage indisponible (mode privé, permissions) : on démarre à vide
		// plutôt que d'empêcher l'interface de s'afficher.
		return {};
	}
}

function loadSessions(): SessionRecord[] {
	try {
		const raw = localStorage.getItem(SESSIONS_KEY);
		const parsed = raw ? JSON.parse(raw) : [];
		return Array.isArray(parsed) ? parsed : [];
	} catch {
		return [];
	}
}

function save() {
	persist('stats', STORAGE_KEY, stats);
}

export function statsOf(id: string): GameStats {
	return stats[id] ?? { favorite: false, playtimeMinutes: 0, lastPlayed: null };
}

/**
 * Ce que Steam sait du jeu `id`, quand c'est un jeu Steam. Un jeu possédé mais
 * pas installé n'est pas dans `games` : son identifiant `steam-<appid>` suffit.
 */
function steamPlay(id: string) {
	const appid = games.find((g) => g.id === id)?.appid ?? (id.startsWith('steam-') ? id.slice(6) : undefined);
	return steamPlayOf(appid);
}

/**
 * Dernière partie : la nôtre, celle de Steam ou celle vue par Windows et le
 * launcher Epic, la plus récente. Un jeu lancé hors de la console, même Lobby
 * fermé, remonte donc aussi.
 */
export function lastPlayedAt(id: string): number | null {
	const local = statsOf(id).lastPlayed ?? 0;
	const steam = steamPlay(id)?.lastPlayed ?? 0;
	const best = Math.max(local, steam, elsewhereDates[id] ?? 0);
	return best > 0 ? best : null;
}

/**
 * Temps de jeu : celui de Steam pour un jeu Steam, celui d'Epic pour un jeu
 * Epic (compte connecté), le nôtre sinon. Le plus grand, pour ne jamais
 * perdre de temps compté.
 */
export function playtimeOf(id: string): number {
	return Math.max(statsOf(id).playtimeMinutes, steamPlay(id)?.playtime ?? 0, epicMinutesOf(id));
}

export function isFavorite(id: string): boolean {
	return statsOf(id).favorite;
}

export function toggleFavorite(id: string) {
	const current = statsOf(id);
	stats[id] = { ...current, favorite: !current.favorite };
	save();
}

/**
 * Appelé au lancement : la carte « Reprendre » et le filtre « Récemment joué »
 * suivent le dernier jeu *lancé*. Attendre la fin de la partie ne marchait pas
 * pour Steam, dont le processus rend la main aussitôt.
 */
export function markLaunched(id: string) {
	stats[id] = { ...statsOf(id), lastPlayed: Date.now() };
	save();
}

/** Le dernier jeu lancé encore présent dans la bibliothèque, s'il y en a un. */
export function lastPlayedGame(): Game | null {
	let best: Game | null = null;
	let when = 0;
	for (const game of games) {
		const at = lastPlayedAt(game.id) ?? 0;
		if (at > when) {
			best = game;
			when = at;
		}
	}
	return best;
}

/** « il y a 5 minutes », « hier », « il y a 3 jours »… */
export function lastPlayedText(id: string): string {
	const at = lastPlayedAt(id);
	return at ? relativeTime(at) : '';
}

/** « il y a 8 minutes », « hier », « il y a 3 jours ». */
export function relativeTime(at: number): string {
	const format = new Intl.RelativeTimeFormat('fr', { numeric: 'auto' });
	const minutes = Math.round((at - Date.now()) / 60_000);
	if (minutes > -60) return format.format(Math.min(-1, minutes), 'minute');
	const hours = Math.round(minutes / 60);
	if (hours > -24) return format.format(hours, 'hour');
	return format.format(Math.round(hours / 24), 'day');
}

/**
 * Appelé à la fin d'une partie : temps cumulé, nombre de parties, date de
 * dernière partie, et une ligne dans le journal.
 */
export function recordSession(id: string, start: number, minutes: number) {
	const current = statsOf(id);
	const played = Math.max(0, Math.round(minutes));
	stats[id] = {
		...current,
		playtimeMinutes: current.playtimeMinutes + played,
		sessions: (current.sessions ?? 0) + 1,
		lastPlayed: Date.now(),
	};
	save();
	sessions.push({ id, start, minutes: played });
	persist('sessions', SESSIONS_KEY, sessions);
}

/** Temps de jeu lisible : « 2 h 15 », « 40 min » ou « Jamais joué ». */
export function playtimeText(id: string): string {
	const minutes = playtimeOf(id);
	if (minutes <= 0) return 'Jamais joué';
	if (minutes < 60) return `${minutes} min`;
	return `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, '0')}`;
}

export type Filter = 'all' | 'installed' | 'favorites';

/** Ordre des filtres, tel qu'on les parcourt avec LT / RT. */
export const FILTERS: Filter[] = ['all', 'installed', 'favorites'];
export const SORTS: Sort[] = ['title', 'recent', 'playtime', 'steam', 'epic'];
/**
 * `steam` / `epic` : les jeux de cette boutique en tête, puis les autres —
 * chaque groupe par titre. Un tri, pas un filtre : aucun jeu ne disparaît.
 */
export type Sort = 'title' | 'recent' | 'playtime' | 'steam' | 'epic';

export const FILTER_LABELS: Record<Filter, string> = {
	all: 'Tous',
	installed: 'Installés',
	favorites: 'Favoris',
};

export const SORT_LABELS: Record<Sort, string> = {
	title: 'Titre',
	recent: 'Récemment joué',
	playtime: 'Temps de jeu',
	steam: 'Jeux Steam',
	epic: 'Jeux Epic',
};

/**
 * Jeux Steam possédés mais pas installés (bibliothèque complète), à partir de
 * la liste `appid → nom`. Ils ne sont jamais enregistrés dans `games` : ils
 * se recalculent de la liste Steam, et disparaissent une fois installés
 * (détectés par le scan, ils deviennent des jeux comme les autres).
 */
export function uninstalledSteamGames(owned: Record<string, string>): Game[] {
	const installed = new Set(games.map((g) => g.appid).filter(Boolean));
	return Object.entries(owned)
		.filter(([appid]) => !installed.has(appid))
		.map(([appid, name]) => ({
			id: `steam-${appid}`,
			// Liste sans noms (dernière voie de secours) : le titre de la fiche
			// Steam prend le relais dès qu'elle arrive.
			title: name || details[appid]?.title || `Jeu Steam ${appid}`,
			appid,
			cover: '',
			hero: '',
			logo: '',
			source: 'steam',
			installed: false,
		}))
		.filter((game) => !isHidden(game));
}

/**
 * Jeux Epic possédés mais pas installés, comme pour Steam : recalculés de la
 * liste Epic, jamais enregistrés. Un jeu installé (même repéré par son
 * dossier, sous un autre identifiant) n'est pas doublé : on compare aussi les
 * titres.
 */
export function uninstalledEpicGames(
	library: { app_name: string; title: string; cover: string; hero: string }[]
): Game[] {
	const ids = new Set(games.map((g) => g.id));
	const titles = new Set(games.map((g) => cleanTitle(g.title)));
	return library
		.filter((game) => !ids.has(`epic-${game.app_name}`) && !titles.has(cleanTitle(game.title)))
		.map((game) => ({
			id: `epic-${game.app_name}`,
			title: game.title,
			// Largeur d'une tuile et d'un écran, sur un écran 4K : au-delà, rien ne se voit.
			cover: epicImage(game.cover, 360, 480),
			hero: epicImage(game.hero, 1920, 1080),
			logo: '',
			source: 'epic',
			installed: false,
		}))
		.filter((game) => !isHidden(game));
}

/** Liste filtrée et triée, telle que la grille doit l'afficher. */
export function view(filter: Filter, sort: Sort, list: Game[] = games): Game[] {
	const kept = list.filter((game) => {
		if (filter === 'installed') return game.installed !== false;
		if (filter === 'favorites') return isFavorite(game.id);
		return true;
	});

	return kept.sort((a, b) => {
		if (sort === 'recent') return byRecent(a, b);
		if (sort === 'playtime') return playtimeOf(b.id) - playtimeOf(a.id);
		if (sort === 'steam' || sort === 'epic') {
			return Number(storeOf(b) === sort) - Number(storeOf(a) === sort) || byTitle(a, b);
		}
		return byTitle(a, b);
	});
}

/** Boutique d'un jeu : sa source, ou Steam s'il a un appid sans source connue. */
function storeOf(game: Game): string {
	return game.source || (game.appid ? 'steam' : '');
}

function byTitle(a: Game, b: Game): number {
	return a.title.localeCompare(b.title, 'fr', { sensitivity: 'base' });
}

/** Dernière partie d'abord ; les jamais joués ensuite, par titre. */
function byRecent(a: Game, b: Game): number {
	return (lastPlayedAt(b.id) ?? 0) - (lastPlayedAt(a.id) ?? 0) || byTitle(a, b);
}

/** Ordre de la rangée d'accueil, choisi dans Réglages → Apparence. */
export type HomeOrder = 'recent' | 'title';

export const HOME_ORDER_LABELS: Record<HomeOrder, string> = {
	recent: 'Dernière partie',
	title: 'Titre',
};

export function homeView(order: HomeOrder): Game[] {
	return [...games].sort(order === 'recent' ? byRecent : byTitle);
}
