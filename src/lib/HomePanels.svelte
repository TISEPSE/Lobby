<script lang="ts">
	import type { Game, SessionRecord } from './types';
	import type { DownloadStatus } from './downloads.svelte.js';
	import { formatMinutes, platformOf, weekDays } from './stats';
	import { relativeTime } from './library.svelte.js';
	import { heroFor } from './steam.svelte.js';

	/**
	 * Panneaux sous la rangée de l'accueil, pour une page vivante : les jeux par
	 * lanceur, le temps de jeu de la semaine, et les mises à jour en cours.
	 * On y descend depuis la rangée ; A ouvre la bibliothèque, les statistiques
	 * ou la fiche du jeu mis à jour (géré par l'appelant).
	 */
	let {
		games,
		sessions,
		downloads,
		/** Panneau sélectionné (0 à 2), ou -1 quand la sélection est dans la rangée. */
		focusedPanel = -1,
		/** Dernière lecture de la bibliothèque Steam (ms ; 0 = jamais). */
		steamSyncedAt = 0,
	}: {
		games: Game[];
		sessions: SessionRecord[];
		downloads: DownloadStatus[];
		focusedPanel?: number;
		steamSyncedAt?: number;
	} = $props();

	/** Lanceurs les plus fournis d'abord ; au-delà de cinq, le reste est regroupé. */
	const launchers = $derived.by(() => {
		const counts = new Map<string, number>();
		for (const game of games) counts.set(platformOf(game), (counts.get(platformOf(game)) ?? 0) + 1);
		const sorted = [...counts.entries()].sort((a, b) => b[1] - a[1]);
		if (sorted.length <= 5) return sorted;
		const rest = sorted.slice(4).reduce((sum, [, n]) => sum + n, 0);
		return [...sorted.slice(0, 4), ['Autres', rest] as [string, number]];
	});

	const week = $derived(weekDays(sessions));
	const weekTotal = $derived(week.reduce((sum, day) => sum + day.minutes, 0));
	const weekMax = $derived(Math.max(1, ...week.map((day) => day.minutes)));

	/** Jeu de la bibliothèque qui correspond à un téléchargement, pour son visuel. */
	function gameOf(appid: string): Game | undefined {
		return games.find((game) => game.appid === appid);
	}

	/** 2 100 000 000 → « 2,1 Go ». */
	function size(bytes: number): string {
		if (bytes >= 1e9) return `${(bytes / 1e9).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} Go`;
		return `${Math.round(bytes / 1e6)} Mo`;
	}

	function status(item: DownloadStatus): { text: string; done: boolean } {
		if (item.phase === 'queued') return { text: 'En attente', done: false };
		if (item.phase === 'stage' || item.percent >= 100) return { text: 'Prête', done: true };
		return { text: `${Math.round(item.percent)} %`, done: false };
	}
</script>

<div class="panels">
	<section class="panel" class:focused={focusedPanel === 0}>
		<header>
			<h2>Vos lanceurs</h2>
			<span class="aside">{games.length} jeux</span>
		</header>
		<div class="launchers">
			{#each launchers as [name, count] (name)}
				<div class="launcher">
					<span class="count">{count}</span>
					<span class="store">{name}</span>
				</div>
			{/each}
		</div>
		<p class="foot">
			{steamSyncedAt ? `Bibliothèque Steam synchronisée ${relativeTime(steamSyncedAt)}` : 'Connecte Steam depuis le Profil pour toute ta bibliothèque'}
		</p>
	</section>

	<section class="panel" class:focused={focusedPanel === 1}>
		<header>
			<h2>Cette semaine</h2>
			<span class="aside">{formatMinutes(weekTotal)}</span>
		</header>
		<div class="week">
			{#each week as day, i (i)}
				<div class="day" class:today={day.today} class:future={day.future}>
					<span class="bar-slot">
						<span class="bar" style="height: {day.minutes > 0 ? Math.max(8, (day.minutes / weekMax) * 100) : 0}%"
						></span>
					</span>
					<span class="letter">{day.label}</span>
				</div>
			{/each}
		</div>
	</section>

	<section class="panel" class:focused={focusedPanel === 2}>
		<header>
			<h2>Mises à jour</h2>
			{#if downloads.length > 0}<span class="aside">{downloads.length}</span>{/if}
		</header>
		{#if downloads.length === 0}
			<p class="empty"><img src="/assets/icons/check.svg" alt="" />Tout est à jour</p>
		{:else}
			<div class="updates">
				{#each downloads.slice(0, 2) as item (item.appid)}
					{@const game = gameOf(item.appid)}
					{@const state = status(item)}
					<div class="update">
						<span class="thumb" style={game ? `background-image: url(${heroFor(game)})` : ''}></span>
						<span class="what">
							<span class="title">{game?.title ?? item.title}</span>
							<span class="sub">Mise à jour · {size(item.bytes_total)}</span>
						</span>
						<span class="state" class:done={state.done}>{state.text}</span>
					</div>
				{/each}
			</div>
		{/if}
	</section>
</div>

<style>
	.panels {
		display: grid;
		grid-template-columns: 1.25fr 1fr 1fr;
		gap: var(--panel-gap);
		padding: 0 var(--safe-x);
	}

	.panel {
		display: flex;
		flex-direction: column;
		gap: 14px;
		min-width: 0;
		height: var(--panel-height);
		padding: 20px 24px;
		border-radius: var(--radius-lg);
		background: var(--dock-bg);
		border: 1px solid var(--dock-border);
		backdrop-filter: blur(18px) saturate(1.2);
		transition:
			transform var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease),
			outline-color var(--fast) var(--ease);
		outline: 3px solid transparent;
	}

	/* Même sélection que partout : contour d'accent et halo. */
	.panel.focused {
		outline-color: var(--accent);
		transform: translateY(-4px);
		box-shadow:
			0 0 34px 6px var(--accent-soft),
			0 18px 40px rgba(0, 0, 0, 0.5);
	}

	header {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
	}

	h2 {
		margin: 0;
		font-size: 20px;
		font-weight: 700;
	}

	.aside {
		font-size: 18px;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	.launchers {
		display: grid;
		grid-template-columns: repeat(5, 1fr);
		gap: 10px;
	}

	.launcher {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		padding: 12px 14px;
		border-radius: var(--radius);
		background: var(--surface);
	}

	.launcher .count {
		font-size: 28px;
		font-weight: 800;
		font-variant-numeric: tabular-nums;
	}

	.store {
		overflow: hidden;
		font-size: 17px;
		color: var(--text-dim);
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	.foot {
		margin: auto 0 0;
		font-size: 17px;
		color: var(--text-dim);
	}

	.week {
		flex: 1;
		display: grid;
		grid-template-columns: repeat(7, 1fr);
		gap: 10px;
		min-height: 0;
	}

	.day {
		display: flex;
		flex-direction: column;
		align-items: stretch;
		gap: 8px;
		min-height: 0;
	}

	.bar-slot {
		flex: 1;
		display: flex;
		align-items: flex-end;
		min-height: 0;
		border-radius: 8px;
		background: var(--surface);
	}

	.bar {
		width: 100%;
		border-radius: 8px;
		background: var(--surface-strong);
		transition: height var(--normal) var(--ease);
	}

	.today .bar {
		background: var(--accent);
		box-shadow: 0 0 16px var(--accent-soft);
	}

	.future .bar-slot {
		opacity: 0.4;
	}

	.letter {
		font-size: 17px;
		text-align: center;
		color: var(--text-dim);
	}

	.today .letter {
		color: var(--text);
		font-weight: 700;
	}

	.empty {
		display: flex;
		align-items: center;
		gap: 12px;
		margin: auto 0;
		font-size: 19px;
		color: var(--text-dim);
	}

	.empty img {
		width: 26px;
		height: 26px;
		opacity: 0.7;
	}

	.updates {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	.update {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: 10px 14px;
		border-radius: var(--radius);
		background: var(--surface);
	}

	.thumb {
		flex: none;
		width: 46px;
		height: 46px;
		border-radius: 10px;
		background: var(--surface-strong) center / cover;
	}

	.what {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}

	.what .title {
		overflow: hidden;
		font-size: 17px;
		font-weight: 700;
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	.sub {
		font-size: 17px;
		color: var(--text-dim);
	}

	.state {
		margin-left: auto;
		font-size: 17px;
		font-weight: 700;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	.state.done {
		color: var(--accent);
	}
</style>
