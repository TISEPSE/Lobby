/**
 * État de la bibliothèque : les jeux, plus ce que l'utilisateur en fait
 * (favoris, temps de jeu, dernière partie).
 *
 * Les jeux viennent du fichier de données ; ce qui est propre à l'utilisateur
 * est gardé à part et persisté, pour qu'un rafraîchissement de la liste des
 * jeux installés n'efface jamais ses favoris.
 */
import rawGames from './data/games.json';
import type { Game, GameStats } from './types';

const STORAGE_KEY = 'interface-console.stats';
const LIBRARY_KEY = 'interface-console.library';

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

export const games = $state<Game[]>(deduplicateGames(rawGames as Game[]));

/** Statistiques par identifiant de jeu. */
export const stats = $state<Record<string, GameStats>>(load());

export async function initLibrary() {
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
				if (cleaned.length !== parsed.length) {
					saveLibrary();
				}
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

export function removeGame(id: string) {
	const idx = games.findIndex((g) => g.id === id);
	if (idx !== -1) {
		games.splice(idx, 1);
		saveLibrary();
	}
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

function save() {
	try {
		localStorage.setItem(STORAGE_KEY, JSON.stringify(stats));
	} catch {
		/* rien à faire : les statistiques ne valent pas un écran d'erreur */
	}
}

export function statsOf(id: string): GameStats {
	return stats[id] ?? { favorite: false, playtimeMinutes: 0, lastPlayed: null };
}

export function isFavorite(id: string): boolean {
	return statsOf(id).favorite;
}

export function toggleFavorite(id: string) {
	const current = statsOf(id);
	stats[id] = { ...current, favorite: !current.favorite };
	save();
}

/** Appelé à la fin d'une partie : temps cumulé et date de dernière partie. */
export function recordSession(id: string, minutes: number) {
	const current = statsOf(id);
	stats[id] = {
		...current,
		playtimeMinutes: current.playtimeMinutes + Math.max(0, Math.round(minutes)),
		lastPlayed: Date.now(),
	};
	save();
}

/** Temps de jeu lisible : « 2 h 15 », « 40 min » ou « Jamais joué ». */
export function playtimeText(id: string): string {
	const minutes = statsOf(id).playtimeMinutes;
	if (minutes <= 0) return 'Jamais joué';
	if (minutes < 60) return `${minutes} min`;
	return `${Math.floor(minutes / 60)} h ${String(minutes % 60).padStart(2, '0')}`;
}

export type Filter = 'all' | 'favorites' | 'recent';
export type Sort = 'title' | 'recent' | 'playtime';

export const FILTER_LABELS: Record<Filter, string> = {
	all: 'Tous',
	favorites: 'Favoris',
	recent: 'Récemment joué',
};

export const SORT_LABELS: Record<Sort, string> = {
	title: 'Titre',
	recent: 'Dernière partie',
	playtime: 'Temps de jeu',
};

/** Liste filtrée et triée, telle que la grille doit l'afficher. */
export function view(filter: Filter, sort: Sort): Game[] {
	const kept = games.filter((game) => {
		if (filter === 'favorites') return isFavorite(game.id);
		if (filter === 'recent') return statsOf(game.id).lastPlayed !== null;
		return true;
	});

	return kept.sort((a, b) => {
		if (sort === 'recent') return (statsOf(b.id).lastPlayed ?? 0) - (statsOf(a.id).lastPlayed ?? 0);
		if (sort === 'playtime') return statsOf(b.id).playtimeMinutes - statsOf(a.id).playtimeMinutes;
		return a.title.localeCompare(b.title, 'fr', { sensitivity: 'base' });
	});
}
