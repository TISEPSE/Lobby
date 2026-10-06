<script lang="ts">
	import type { Game } from './types';
	import type { Action } from './gamepad';
	import Cover from './Cover.svelte';
	import Glyph from './Glyph.svelte';
	import { sessions, playtimeOf } from './library.svelte.js';
	import { details, ensureDetails } from './steam.svelte.js';
	import {
		PERIODS,
		PERIOD_LABELS,
		activeDays,
		formatMinutes,
		genres,
		heatmap,
		inPeriod,
		longestSession,
		longestStreak,
		periodStart,
		rankByPlaytime,
		summarize,
		topGames,
		type Period,
		type Ranked,
	} from './stats';

	/**
	 * Statistiques, façon tableau de bord Xbox : un mot d'accueil et les faits
	 * marquants, les périodes (LT / RT), quatre chiffres, le **calendrier
	 * d'activité** de l'année, et à droite les genres et les jeux les plus
	 * joués.
	 *
	 * Deux zones se parcourent : le calendrier (une case = un jour ; la case
	 * sélectionnée affiche sa date et son temps de jeu — à la manette, il n'y a
	 * pas de survol) et le classement (A ouvre la fiche).
	 *
	 * « Tout » compte aussi le temps de jeu Steam ; les autres périodes, elles,
	 * viennent du journal des parties, Steam ne donnant qu'un total.
	 */
	let {
		games,
		profileName,
		initialPeriod = 'month',
		onOpenGame,
		onBack,
	}: {
		games: Game[];
		profileName: string;
		initialPeriod?: Period;
		onOpenGame?: (game: Game) => void;
		/** B : retour aux réglages. */
		onBack?: () => void;
	} = $props();

	let period = $state<Period>(PERIODS.includes(initialPeriod) ? initialPeriod : 'month');
	let zone = $state<'heat' | 'top'>('heat');
	/** Case sélectionnée du calendrier : semaine (colonne) et jour (ligne). */
	let cell = $state<{ w: number; d: number } | null>(null);
	let topIndex = $state(0);

	const log = $derived(inPeriod(sessions, period));
	const summary = $derived(summarize(log));
	const weeks = $derived(heatmap(sessions));
	const from = $derived(periodStart(period));

	/** Aujourd'hui : la dernière case qui existe. */
	const today = $derived.by(() => {
		const w = weeks.length - 1;
		const d = weeks[w].findLastIndex((c) => c !== null);
		return { w, d };
	});
	const at = $derived(cell ?? today);
	const picked = $derived(weeks[at.w]?.[at.d] ?? null);

	const totalMinutes = $derived(
		period === 'all' ? games.reduce((sum, g) => sum + playtimeOf(g.id), 0) : summary.minutes
	);
	const genresOf = (game: Game) => (game.appid ? (details[game.appid]?.genres ?? []) : []);
	const byGenre = $derived(
		period === 'all'
			? rankByPlaytime(games, (g) => playtimeOf(g.id), genresOf)
			: genres(log, games, genresOf)
	);
	const ranking = $derived<Ranked<Game>[]>(
		period === 'all'
			? games
					.map((g) => ({ item: g, minutes: playtimeOf(g.id), sessions: 0 }))
					.filter((r) => r.minutes > 0)
					.sort((a, b) => b.minutes - a.minutes)
					.slice(0, 5)
			: topGames(log, games)
	);
	const genrePeak = $derived(Math.max(1, ...byGenre.map((g) => g.minutes)));

	/** Faits marquants : seulement ceux qui disent quelque chose. */
	const highlights = $derived.by(() => {
		const list: string[] = [];
		const streak = longestStreak(sessions);
		if (streak >= 2) list.push(`Série record : ${streak} jours d'affilée`);
		const moment = topGames(inPeriod(sessions, 'month'), games, 1)[0];
		if (moment) list.push(`Jeu du moment : ${moment.item.title}`);
		const longest = longestSession(sessions);
		const longestGame = longest && games.find((g) => g.id === longest.id);
		if (longest && longestGame) {
			list.push(`Plus longue partie : ${formatMinutes(longest.minutes)} sur ${longestGame.title}`);
		}
		return list;
	});

	const greeting = $derived.by(() => {
		const hour = new Date().getHours();
		return hour >= 5 && hour < 18 ? 'Bonjour' : 'Bonsoir';
	});

	/** Étiquettes de mois au-dessus du calendrier, à la première semaine de chaque mois. */
	const monthLabels = $derived(
		weeks.map((week, w) => {
			const first = week[0];
			if (!first) return '';
			const date = new Date(first.time);
			const previous = weeks[w - 1]?.[0];
			if (previous && new Date(previous.time).getMonth() === date.getMonth()) return '';
			return date.toLocaleDateString('fr-FR', { month: 'short' }).replace('.', '');
		})
	);

	// Les genres viennent des fiches Steam : on les demande pour les jeux joués.
	$effect(() => {
		for (const game of games) {
			if (game.appid && playtimeOf(game.id) > 0) ensureDetails(game.appid);
		}
	});

	/** Empreinte de la sélection, pour ne sonner que si elle bouge. */
	export function selectionKey(): string {
		return `${period}|${zone}|${at.w}|${at.d}|${topIndex}`;
	}

	export function changePeriod(step: number) {
		const index = PERIODS.indexOf(period);
		period = PERIODS[Math.min(PERIODS.length - 1, Math.max(0, index + step))];
		topIndex = 0;
	}

	/** Déplace la case sélectionnée, sans jamais tomber sur un jour à venir. */
	function moveCell(dw: number, dd: number) {
		const w = Math.min(weeks.length - 1, Math.max(0, at.w + dw));
		const d = Math.min(6, Math.max(0, at.d + dd));
		if (weeks[w]?.[d]) cell = { w, d };
	}

	export function handleAction(action: Action) {
		if (action === 'pagePrev' || action === 'pageNext') {
			return changePeriod(action === 'pageNext' ? 1 : -1);
		}
		if (action === 'cancel') return onBack?.();

		if (zone === 'heat') {
			if (action === 'left') moveCell(-1, 0);
			else if (action === 'up') moveCell(0, -1);
			else if (action === 'down') moveCell(0, 1);
			else if (action === 'right') {
				// Au bout du calendrier, on passe au classement juste à côté.
				if (at.w < weeks.length - 1 && weeks[at.w + 1]?.[at.d]) moveCell(1, 0);
				else if (ranking.length > 0) zone = 'top';
			}
			return;
		}

		if (action === 'up') topIndex = Math.max(0, topIndex - 1);
		else if (action === 'down') topIndex = Math.min(ranking.length - 1, topIndex + 1);
		else if (action === 'left') zone = 'heat';
		else if (action === 'accept') {
			const chosen = ranking[topIndex]?.item;
			if (chosen) onOpenGame?.(chosen);
		}
	}

	function hours(minutes: number): string {
		return minutes >= 600 ? `${Math.round(minutes / 60)} h` : formatMinutes(minutes);
	}

	/** Jeux possédés (Steam, Epic, dossiers) dont ceux qui sont installés. */
	const installedCount = $derived(games.filter((g) => g.installed !== false).length);

	/**
	 * Jeux joués sur la période : d'après le journal, ou, pour « Tout », tout jeu
	 * qui a du temps de jeu (Steam et Epic compris).
	 */
	const playedCount = $derived(
		period === 'all'
			? games.filter((g) => playtimeOf(g.id) > 0).length
			: new Set(log.map((entry) => entry.id)).size
	);
</script>

<section class="stats">
	<header class="hello">
		<span class="caption">Statistiques</span>
		<h1>{greeting}, {profileName}</h1>
		<p class="lead">
			{games.length} jeux possédés · {installedCount} installés · {hours(
				games.reduce((sum, g) => sum + playtimeOf(g.id), 0)
			)} de jeu au total
		</p>
		{#if highlights.length > 0}
			<div class="chips">
				{#each highlights as text}
					<span class="chip"><img src="/assets/icons/star.svg" alt="" />{text}</span>
				{/each}
			</div>
		{/if}
	</header>

	<div class="body">
		<div class="main">
			<!-- Les périodes, encadrées des gâchettes qui les parcourent. -->
			<div class="periods">
				<Glyph button="l2" size="34px" />
				{#each PERIODS as entry}
					<span class="period" class:active={entry === period}>{PERIOD_LABELS[entry]}</span>
				{/each}
				<Glyph button="r2" size="34px" />
			</div>

			<div class="kpis">
				<div class="kpi">
					<img src="/assets/icons/controller.svg" alt="" />
					<span class="value">{playedCount}</span>
					<span class="label">Jeux joués</span>
				</div>
				<div class="kpi">
					<img src="/assets/icons/clock.svg" alt="" />
					<span class="value">{hours(totalMinutes)}</span>
					<span class="label">Temps de jeu</span>
				</div>
				<div class="kpi">
					<img src="/assets/icons/check.svg" alt="" />
					<span class="value">{activeDays(log)}</span>
					<span class="label">Jours actifs</span>
				</div>
				<div class="kpi">
					<img src="/assets/icons/star.svg" alt="" />
					<span class="value small">{byGenre[0]?.item ?? '—'}</span>
					<span class="label">Genre favori</span>
				</div>
			</div>

			<div class="card heat" class:active={zone === 'heat'}>
				<div class="card-head">
					<span class="caption">Activité de l'année</span>
					<p class="readout">
						{#if picked}
							<span class="when"
								>{new Date(picked.time).toLocaleDateString('fr-FR', {
									weekday: 'long',
									day: 'numeric',
									month: 'long',
								})}</span
							>
							<strong>{picked.minutes > 0 ? formatMinutes(picked.minutes) : 'Pas joué'}</strong>
						{/if}
					</p>
				</div>

				<div class="calendar">
					<div class="months">
						{#each monthLabels as label}<span>{label}</span>{/each}
					</div>
					<div class="days">
						<span>lun</span><span></span><span>mer</span><span></span><span>ven</span><span></span><span>dim</span>
					</div>
					<div class="cells">
						{#each weeks as week, w}
							{#each week as day, d}
								{#if day}
									<span
										class="cell level-{day.level}"
										class:out={day.time < from}
										class:selected={zone === 'heat' && w === at.w && d === at.d}
										style="grid-column: {w + 1}; grid-row: {d + 1}"
									></span>
								{/if}
							{/each}
						{/each}
					</div>
				</div>

				<div class="legend">
					<span>Moins</span>
					{#each [0, 1, 2, 3, 4] as level}<span class="cell level-{level}"></span>{/each}
					<span>Plus</span>
				</div>
			</div>
		</div>

		<aside class="side">
			<div class="card">
				<span class="caption">Par genre</span>
				{#if byGenre.length === 0}
					<p class="none">Genres inconnus : ils viennent des fiches Steam.</p>
				{/if}
				{#each byGenre as entry (entry.item)}
					<div class="row">
						<span class="name">{entry.item}</span>
						<span class="meter"><span style="--w: {entry.minutes / genrePeak}"></span></span>
						<span class="amount">{hours(entry.minutes)}</span>
					</div>
				{/each}
			</div>

			<div class="card top" class:active={zone === 'top'}>
				<span class="caption">Les plus joués</span>
				{#if ranking.length === 0}
					<p class="none">Aucune partie sur cette période.</p>
				{/if}
				<ol>
					{#each ranking as entry, i (entry.item.id)}
						<li class:selected={zone === 'top' && i === topIndex}>
							<div class="thumb"><Cover game={entry.item} /></div>
							<span class="title">{entry.item.title}</span>
							<span class="amount">{hours(entry.minutes)}</span>
						</li>
					{/each}
				</ol>
			</div>
		</aside>
	</div>
</section>

<style>
	.stats {
		position: relative;
		z-index: 1;
		display: flex;
		flex-direction: column;
		gap: 18px;
		height: 100%;
		padding: 1vh var(--safe-x) calc(var(--safe-y) + 30px);
	}

	.caption {
		font-size: 17px;
		font-weight: 600;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--text-dim);
	}

	h1 {
		margin: 2px 0 0;
		font-size: clamp(32px, 2.8vw, 48px);
		font-weight: 700;
		letter-spacing: -0.02em;
	}

	.lead {
		margin: 4px 0 0;
		font-size: 19px;
		color: var(--text-dim);
	}

	.chips {
		display: flex;
		flex-wrap: wrap;
		gap: 10px;
		margin-top: 14px;
	}

	/* Faits marquants : pastilles de verre, une étoile d'accent. */
	.chip {
		display: inline-flex;
		align-items: center;
		gap: 10px;
		padding: 8px 16px;
		border-radius: 999px;
		background: var(--dock-bg);
		border: 1px solid var(--dock-border);
		font-size: 17px;
	}

	.chip img {
		width: 16px;
		height: 16px;
	}

	.body {
		flex: 1;
		min-height: 0;
		display: grid;
		grid-template-columns: 1fr var(--stats-side);
		gap: var(--card-gap);
	}

	.main {
		display: flex;
		flex-direction: column;
		gap: var(--card-gap);
		min-width: 0;
	}

	.periods {
		display: flex;
		align-items: center;
		gap: 8px;
	}

	/* Période courante : pilule claire, comme la section courante du dock. */
	.period {
		padding: 8px 18px;
		border-radius: 999px;
		font-size: 17px;
		color: var(--text-dim);
		transition:
			background var(--fast) var(--ease),
			color var(--fast) var(--ease);
	}

	.period.active {
		background: var(--dock-active);
		color: var(--text);
		font-weight: 600;
	}

	.kpis {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--card-gap);
	}

	.kpi,
	.card {
		border-radius: var(--radius-lg);
		background: var(--dock-bg);
		border: 1px solid var(--dock-border);
		backdrop-filter: blur(18px);
	}

	.kpi {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: 18px 22px;
	}

	.kpi img {
		width: 22px;
		height: 22px;
		margin-bottom: 8px;
		opacity: 0.8;
	}

	.value {
		font-size: clamp(28px, 2.2vw, 40px);
		font-weight: 700;
		letter-spacing: -0.02em;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.value.small {
		font-size: clamp(24px, 1.8vw, 32px);
	}

	.label {
		font-size: 17px;
		color: var(--text-dim);
	}

	.card {
		display: flex;
		flex-direction: column;
		gap: 12px;
		padding: 20px 24px;
		outline: 3px solid transparent;
		transition:
			outline-color var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	/* La zone qui a la main porte le contour d'accent. */
	.card.active {
		outline-color: var(--accent);
		box-shadow: 0 0 32px 4px var(--accent-soft);
	}

	.card-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 20px;
	}

	.readout {
		margin: 0;
		font-size: 18px;
		color: var(--text-dim);
	}

	.readout strong {
		margin-left: 10px;
		color: var(--text);
	}

	.when::first-letter {
		text-transform: uppercase;
	}

	/* Calendrier : 53 semaines en colonnes, 7 jours en lignes. Les cases
	   gardent leur forme carrée et se partagent la largeur. */
	.calendar {
		display: grid;
		grid-template-columns: auto 1fr;
		grid-template-rows: auto auto;
		column-gap: 10px;
		row-gap: 6px;
	}

	.months {
		grid-column: 2;
		display: grid;
		grid-template-columns: repeat(53, 1fr);
		gap: var(--heat-gap);
		font-size: 17px;
		color: var(--text-dim);
		white-space: nowrap;
	}

	.days {
		grid-column: 1;
		grid-row: 2;
		display: grid;
		grid-template-rows: repeat(7, 1fr);
		gap: var(--heat-gap);
		font-size: 15px;
		line-height: 1;
		color: var(--text-dim);
		align-items: center;
	}

	.cells {
		grid-column: 2;
		grid-row: 2;
		display: grid;
		grid-template-columns: repeat(53, 1fr);
		grid-template-rows: repeat(7, auto);
		gap: var(--heat-gap);
	}

	.cell {
		aspect-ratio: 1;
		border-radius: 3px;
		background: var(--heat-0);
		transition: transform var(--fast) var(--ease);
	}

	.level-1 {
		background: var(--heat-1);
	}

	.level-2 {
		background: var(--heat-2);
	}

	.level-3 {
		background: var(--heat-3);
	}

	.level-4 {
		background: var(--heat-4);
	}

	/* Hors de la période choisie : le calendrier reste entier, mais s'efface. */
	.cell.out {
		opacity: 0.35;
	}

	.cell.selected {
		opacity: 1;
		outline: 2px solid var(--text);
		outline-offset: 1px;
		transform: scale(1.35);
		position: relative;
		z-index: 1;
	}

	.legend {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		gap: 6px;
		font-size: 17px;
		color: var(--text-dim);
	}

	.legend .cell {
		width: 16px;
	}

	.side {
		display: flex;
		flex-direction: column;
		gap: var(--card-gap);
		min-height: 0;
	}

	.row {
		display: grid;
		grid-template-columns: 8em 1fr 4em;
		align-items: center;
		gap: 12px;
		font-size: 17px;
	}

	.name,
	.title {
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.meter {
		display: block;
		height: 6px;
		border-radius: 3px;
		background: var(--grid-line);
		overflow: hidden;
	}

	.meter span {
		display: block;
		width: calc(var(--w) * 100%);
		height: 100%;
		border-radius: 3px;
		background: var(--accent);
	}

	.amount {
		text-align: right;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}

	.top {
		flex: 1;
		min-height: 0;
	}

	ol {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	li {
		display: grid;
		grid-template-columns: 36px 1fr auto;
		align-items: center;
		gap: 14px;
		padding: 6px 10px;
		border-radius: var(--radius);
		font-size: 17px;
		transition: background var(--fast) var(--ease);
	}

	li.selected {
		background: var(--surface-strong);
		outline: 2px solid var(--accent);
	}

	/* `Cover` se cale en absolu sur son conteneur : il lui faut un repère. */
	.thumb {
		position: relative;
		aspect-ratio: 2 / 3;
		border-radius: 6px;
		overflow: hidden;
		background: var(--surface);
	}

	.none {
		margin: 0;
		font-size: 17px;
		color: var(--text-dim);
	}
</style>
