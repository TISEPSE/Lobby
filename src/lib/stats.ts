/**
 * Calculs de l'écran Statistiques, à partir du journal des parties. Rien
 * d'affiché ici : des fonctions pures, que le composant n'a plus qu'à dessiner.
 */
import type { Game, SessionRecord } from './types';

export type Period = 'week' | 'month' | 'quarter' | 'year' | 'all';

export const PERIODS: Period[] = ['week', 'month', 'quarter', 'year', 'all'];

export const PERIOD_LABELS: Record<Period, string> = {
	week: '7 jours',
	month: '30 jours',
	quarter: '90 jours',
	year: 'Année',
	all: 'Tout',
};

/** Nombre de jours couverts par une période ; `null` pour « Tout ». */
const PERIOD_DAYS: Record<Period, number | null> = {
	week: 7,
	month: 30,
	quarter: 90,
	year: 365,
	all: null,
};

const DAY = 86_400_000;

/** Libellés des boutiques, tels que le scanner les écrit dans `source`. */
const PLATFORM_LABELS: Record<string, string> = {
	steam: 'Steam',
	epic: 'Epic Games',
	gog: 'GOG',
	ea: 'EA',
	ubisoft: 'Ubisoft',
	xbox: 'Xbox',
};

/** « 2 h 15 », « 40 min », « 0 min ». */
export function formatMinutes(minutes: number): string {
	if (minutes < 60) return `${Math.round(minutes)} min`;
	return `${Math.floor(minutes / 60)} h ${String(Math.round(minutes % 60)).padStart(2, '0')}`;
}

/** Début du jour local, pour que « aujourd'hui » commence à minuit et pas il y a 24 h. */
function startOfDay(time: number): number {
	const date = new Date(time);
	date.setHours(0, 0, 0, 0);
	return date.getTime();
}

/** Premier instant d'une période (minuit, il y a N − 1 jours) ; 0 pour « Tout ». */
export function periodStart(period: Period, now = Date.now()): number {
	const days = PERIOD_DAYS[period];
	return days === null ? 0 : startOfDay(now) - (days - 1) * DAY;
}

/** Parties de la période ; « Depuis toujours » garde tout le journal. */
export function inPeriod(log: SessionRecord[], period: Period, now = Date.now()): SessionRecord[] {
	const days = PERIOD_DAYS[period];
	if (days === null) return log;
	return log.filter((s) => s.start >= periodStart(period, now));
}

export interface Summary {
	minutes: number;
	sessions: number;
	games: number;
	average: number;
}

export function summarize(log: SessionRecord[]): Summary {
	const minutes = log.reduce((sum, s) => sum + s.minutes, 0);
	return {
		minutes,
		sessions: log.length,
		games: new Set(log.map((s) => s.id)).size,
		average: log.length ? minutes / log.length : 0,
	};
}

export interface Bucket {
	/** Libellé court sous la barre (« lun. », « 12 », « mars »). */
	label: string;
	/** Libellé complet, affiché quand la barre est sélectionnée. */
	title: string;
	minutes: number;
}

/**
 * Activité découpée dans le temps : un jour par barre sur 7 ou 30 jours, un
 * mois par barre sur les douze derniers mois pour « Depuis toujours ».
 */
export function activity(log: SessionRecord[], period: Period, now = Date.now()): Bucket[] {
	if (period === 'all') {
		const today = new Date(now);
		const months: Bucket[] = [];
		for (let back = 11; back >= 0; back--) {
			const first = new Date(today.getFullYear(), today.getMonth() - back, 1);
			const next = new Date(first.getFullYear(), first.getMonth() + 1, 1);
			months.push({
				label: first.toLocaleDateString('fr-FR', { month: 'short' }).replace('.', ''),
				title: first.toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' }),
				minutes: log
					.filter((s) => s.start >= first.getTime() && s.start < next.getTime())
					.reduce((sum, s) => sum + s.minutes, 0),
			});
		}
		return months;
	}

	const days = PERIOD_DAYS[period] ?? 30;
	const first = startOfDay(now) - (days - 1) * DAY;
	const buckets: Bucket[] = [];
	for (let i = 0; i < days; i++) {
		// On repart de la date plutôt que d'ajouter 24 h : un changement d'heure
		// décalerait sinon toutes les barres suivantes.
		const date = new Date(first);
		date.setDate(date.getDate() + i);
		const from = date.getTime();
		const to = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime();
		buckets.push({
			label:
				days === 7
					? date.toLocaleDateString('fr-FR', { weekday: 'short' }).replace('.', '')
					: String(date.getDate()),
			title: date.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' }),
			minutes: log
				.filter((s) => s.start >= from && s.start < to)
				.reduce((sum, s) => sum + s.minutes, 0),
		});
	}
	return buckets;
}

export interface Ranked<T> {
	item: T;
	minutes: number;
	sessions: number;
}

/** Jeux les plus joués de la période, du plus long au plus court. */
export function topGames(log: SessionRecord[], games: Game[], limit = 5): Ranked<Game>[] {
	const byId = new Map<string, Ranked<Game>>();
	for (const s of log) {
		const game = games.find((g) => g.id === s.id);
		// Un jeu retiré de la bibliothèque ne peut plus s'ouvrir : on ne le
		// propose pas dans une liste où A ouvre la fiche.
		if (!game) continue;
		const entry = byId.get(s.id) ?? { item: game, minutes: 0, sessions: 0 };
		entry.minutes += s.minutes;
		entry.sessions += 1;
		byId.set(s.id, entry);
	}
	return [...byId.values()]
		.sort((a, b) => b.minutes - a.minutes || b.sessions - a.sessions)
		.slice(0, limit);
}

/** Temps passé par boutique : Steam, Epic… et « Hors boutique » pour le reste. */
export function platforms(log: SessionRecord[], games: Game[]): Ranked<string>[] {
	const totals = new Map<string, Ranked<string>>();
	for (const s of log) {
		const source = games.find((g) => g.id === s.id)?.source ?? '';
		const label = PLATFORM_LABELS[source] ?? 'Hors boutique';
		const entry = totals.get(label) ?? { item: label, minutes: 0, sessions: 0 };
		entry.minutes += s.minutes;
		entry.sessions += 1;
		totals.set(label, entry);
	}
	return [...totals.values()].sort((a, b) => b.minutes - a.minutes);
}

/**
 * Temps passé par genre, d'après les fiches Steam. Un jeu à trois genres
 * compte pour chacun : on lit « combien de temps sur des jeux d'action », pas
 * une répartition qui ferait 100 %.
 */
export function genres(
	log: SessionRecord[],
	games: Game[],
	genresOf: (game: Game) => string[],
	limit = 5
): Ranked<string>[] {
	const totals = new Map<string, Ranked<string>>();
	for (const s of log) {
		const game = games.find((g) => g.id === s.id);
		if (!game) continue;
		for (const genre of genresOf(game)) {
			const entry = totals.get(genre) ?? { item: genre, minutes: 0, sessions: 0 };
			entry.minutes += s.minutes;
			entry.sessions += 1;
			totals.set(genre, entry);
		}
	}
	return [...totals.values()].sort((a, b) => b.minutes - a.minutes).slice(0, limit);
}

/** Une case du calendrier d'activité : un jour. */
export interface HeatCell {
	time: number;
	minutes: number;
	/** 0 (rien) à 4 (grosse journée). */
	level: number;
}

/** Paliers du calendrier, en minutes : une demi-heure, une heure, deux, quatre. */
const HEAT_STEPS = [1, 30, 60, 120, 240];

/**
 * Calendrier d'activité sur un an : 53 colonnes d'une semaine (lundi en
 * haut), la dernière s'arrêtant à aujourd'hui. Les jours à venir valent `null`.
 */
export function heatmap(log: SessionRecord[], now = Date.now()): (HeatCell | null)[][] {
	const today = startOfDay(now);
	const weekday = (new Date(today).getDay() + 6) % 7; // lundi = 0
	const firstMonday = new Date(today);
	firstMonday.setDate(firstMonday.getDate() - weekday - 52 * 7);

	const byDay = new Map<number, number>();
	for (const s of log) {
		const day = startOfDay(s.start);
		byDay.set(day, (byDay.get(day) ?? 0) + s.minutes);
	}

	const weeks: (HeatCell | null)[][] = [];
	for (let w = 0; w < 53; w++) {
		const week: (HeatCell | null)[] = [];
		for (let d = 0; d < 7; d++) {
			// Par la date, pas en ajoutant des tranches de 24 h : un changement
			// d'heure décalerait sinon tout le calendrier.
			const date = new Date(firstMonday);
			date.setDate(date.getDate() + w * 7 + d);
			const time = date.getTime();
			if (time > today) {
				week.push(null);
				continue;
			}
			const minutes = byDay.get(time) ?? 0;
			const level = HEAT_STEPS.filter((step) => minutes >= step).length;
			week.push({ time, minutes, level: Math.min(4, level) });
		}
		weeks.push(week);
	}
	return weeks;
}

/** Jours où l'on a joué, dans le journal donné. */
export function activeDays(log: SessionRecord[]): number {
	return new Set(log.map((s) => startOfDay(s.start))).size;
}

/** Plus longue suite de jours consécutifs avec au moins une partie. */
export function longestStreak(log: SessionRecord[]): number {
	const days = [...new Set(log.map((s) => startOfDay(s.start)))].sort((a, b) => a - b);
	let best = 0;
	let run = 0;
	let previous = 0;
	for (const day of days) {
		// Entre deux minuits, 23 à 25 h selon l'heure d'été : on arrondit.
		run = previous && Math.round((day - previous) / DAY) === 1 ? run + 1 : 1;
		best = Math.max(best, run);
		previous = day;
	}
	return best;
}

/** La plus longue partie du journal, s'il y en a une. */
export function longestSession(log: SessionRecord[]): SessionRecord | null {
	return log.reduce<SessionRecord | null>((best, s) => (!best || s.minutes > best.minutes ? s : best), null);
}

/**
 * Classement d'après le **temps de jeu total** (le nôtre et celui de Steam),
 * pas d'après le journal : c'est ce que montre le profil. `keysOf` donne les
 * catégories d'un jeu — ses genres, ou sa boutique.
 */
export function rankByPlaytime(
	games: Game[],
	minutesOf: (game: Game) => number,
	keysOf: (game: Game) => string[],
	limit = 5
): Ranked<string>[] {
	const totals = new Map<string, Ranked<string>>();
	for (const game of games) {
		const minutes = minutesOf(game);
		if (minutes <= 0) continue;
		for (const key of keysOf(game)) {
			const entry = totals.get(key) ?? { item: key, minutes: 0, sessions: 0 };
			entry.minutes += minutes;
			entry.sessions += 1;
			totals.set(key, entry);
		}
	}
	return [...totals.values()].sort((a, b) => b.minutes - a.minutes).slice(0, limit);
}

/** Boutique d'un jeu, telle qu'affichée. */
export function platformOf(game: Game): string {
	return PLATFORM_LABELS[game.source ?? ''] ?? (game.appid ? 'Steam' : 'Hors boutique');
}

/**
 * Journal fictif pour juger l'écran dans un navigateur (`?stats=demo`) : il
 * n'est jamais enregistré.
 */
export function demoLog(games: Game[], now = Date.now()): SessionRecord[] {
	const log: SessionRecord[] = [];
	const picked = games.slice(0, 7);
	let seed = 7;
	const random = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
	for (let day = 300; day >= 0; day--) {
		if (random() < 0.45) continue;
		const count = 1 + Math.floor(random() * 2);
		for (let i = 0; i < count; i++) {
			const index = Math.min(picked.length - 1, Math.floor(random() * random() * picked.length));
			const game = picked[index];
			if (!game) continue;
			log.push({
				id: game.id,
				start: startOfDay(now) - day * DAY + (18 + i * 2) * 3_600_000,
				minutes: Math.round(20 + random() * 140),
			});
		}
	}
	return log;
}

/** Un jour de la semaine en cours, pour le panneau « Cette semaine » de l'accueil. */
export interface WeekDay {
	/** « L », « M »… */
	label: string;
	minutes: number;
	today: boolean;
	/** Jour pas encore arrivé : rien à montrer. */
	future: boolean;
}

/**
 * Temps de jeu de chaque jour de la semaine en cours, du lundi au dimanche.
 * Les jours se calculent par le calendrier (changement d'heure compris).
 */
export function weekDays(log: SessionRecord[], now = Date.now()): WeekDay[] {
	const today = new Date(now);
	today.setHours(0, 0, 0, 0);
	const monday = new Date(today);
	monday.setDate(today.getDate() - ((today.getDay() + 6) % 7));
	return ['L', 'M', 'M', 'J', 'V', 'S', 'D'].map((label, i) => {
		const start = new Date(monday);
		start.setDate(monday.getDate() + i);
		const end = new Date(start);
		end.setDate(start.getDate() + 1);
		const minutes = log
			.filter((entry) => entry.start >= start.getTime() && entry.start < end.getTime())
			.reduce((sum, entry) => sum + entry.minutes, 0);
		return { label, minutes, today: start.getTime() === today.getTime(), future: start > today };
	});
}
