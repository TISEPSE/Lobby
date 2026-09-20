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

export const games: Game[] = rawGames as Game[];

/** Statistiques par identifiant de jeu. */
export const stats = $state<Record<string, GameStats>>(load());

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
