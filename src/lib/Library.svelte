<script lang="ts">
	import type { Game } from './types';
	import Cover from './Cover.svelte';
	import { FILTER_LABELS, SORT_LABELS, isFavorite, type Filter, type Sort } from './library.svelte.js';

	/**
	 * Bibliothèque : titre de page, onglets de filtre, ligne de comptage et
	 * grille de grandes jaquettes. Le fond est volontairement effacé — ici on
	 * lit une liste, l'artwork ne doit pas tirer l'œil.
	 */
	let {
		games,
		index,
		filter,
		sort,
		columns,
	}: {
		games: Game[];
		index: number;
		filter: Filter;
		sort: Sort;
		columns: number;
	} = $props();

	const filters: Filter[] = ['all', 'favorites', 'recent'];

	/** La grille défile par lignes entières : jamais de jaquette coupée. */
	const row = $derived(Math.floor(index / columns));
</script>

<section class="library">
	<h1>Bibliothèque</h1>

	<div class="tabs">
		{#each filters as entry}
			<span class="tab" class:active={entry === filter}>{FILTER_LABELS[entry]}</span>
		{/each}
	</div>

	<p class="count">
		{FILTER_LABELS[filter]} : {games.length}
		<span class="sort">Trier par : {SORT_LABELS[sort]}</span>
	</p>

	<div class="viewport">
		<div class="grid" style="--columns: {columns}; --row: {row}">
			{#each games as game, i (game.id)}
				<button class="tile" class:selected={i === index}>
					<Cover {game} />
					{#if isFavorite(game.id)}
						<img class="badge" src="/assets/icons/star.svg" alt="Favori" />
					{/if}
					<span class="caption">{game.title}</span>
				</button>
			{/each}
		</div>
	</div>

	{#if games.length === 0}
		<p class="empty">Aucun jeu dans ce filtre.</p>
	{/if}
</section>

<style>
	.library {
		position: relative;
		z-index: 1;
		display: flex;
		flex-direction: column;
		height: calc(100% - 110px);
		padding: 2vh var(--safe-x) var(--safe-y);
	}

	h1 {
		margin: 0;
		font-size: clamp(32px, 3.4vw, 56px);
		font-weight: 700;
		letter-spacing: -0.02em;
	}

	.tabs {
		display: flex;
		gap: 26px;
		margin-top: 12px;
	}

	.tab {
		font-size: 20px;
		color: var(--text-dim);
		padding-bottom: 6px;
		border-bottom: 2px solid transparent;
	}

	.tab.active {
		color: var(--text);
		border-color: var(--accent);
	}

	.count {
		display: flex;
		gap: 28px;
		margin: 14px 0 18px;
		font-size: 17px;
		color: var(--text-dim);
	}

	.sort {
		opacity: 0.8;
	}

	/* La fenêtre rogne ce qui dépasse ; la grille se décale ligne par ligne.
	   La marge négative compensée par le padding laisse respirer la tuile
	   agrandie : sans elle, la sélection était coupée sur les bords. */
	.viewport {
		flex: 1;
		overflow: hidden;
		margin: -16px;
		padding: 16px;
	}

	.grid {
		/* Les colonnes remplissent la largeur : l'espacement reste constant, la
		   taille des jaquettes s'ajuste. La hauteur d'une ligne s'en déduit
		   (format 2/3) et sert au défilement, ligne par ligne. */
		--gap: 18px;
		--col-width: calc(
			(100vw - 2 * var(--safe-x) - (var(--columns) - 1) * var(--gap)) / var(--columns)
		);
		--row-height: calc(var(--col-width) * 1.5);

		display: grid;
		grid-template-columns: repeat(var(--columns), 1fr);
		gap: var(--gap);
		transform: translateY(calc(var(--row) * -1 * (var(--row-height) + var(--gap))));
		transition: transform var(--normal) var(--ease);
	}

	.tile {
		position: relative;
		aspect-ratio: 2 / 3;
		padding: 0;
		border-radius: var(--radius);
		overflow: hidden;
		background: var(--surface);
		box-shadow: 0 12px 30px rgba(0, 0, 0, 0.45);
		transition:
			transform var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	.tile.selected {
		transform: scale(1.06);
		outline: 3px solid var(--accent);
		box-shadow:
			0 0 30px 6px var(--accent-soft),
			0 22px 50px rgba(0, 0, 0, 0.6);
	}

	.badge {
		position: absolute;
		top: 10px;
		right: 10px;
		width: 22px !important;
		height: 22px !important;
		filter: drop-shadow(0 2px 6px rgba(0, 0, 0, 0.8));
	}

	.caption {
		position: absolute;
		inset: auto 0 0;
		padding: 30px 10px 12px;
		font-size: 15px;
		font-weight: 600;
		text-align: center;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.9), transparent);
	}

	.empty {
		margin-top: 40px;
		font-size: 20px;
		color: var(--text-dim);
	}
</style>
