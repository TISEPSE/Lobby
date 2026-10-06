<script lang="ts">
	import type { Game } from './types';
	import Cover from './Cover.svelte';
	import Glyph from './Glyph.svelte';
	import { FILTERS, FILTER_LABELS, SORT_LABELS, isFavorite, type Filter, type Sort } from './library.svelte.js';

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
		focused = true,
		syncing = false,
		zone = 'grid',
		headerIndex = 0,
	}: {
		games: Game[];
		index: number;
		filter: Filter;
		sort: Sort;
		columns: number;
		/** Sélection dans la grille ; sinon elle est sur la barre du haut. */
		focused?: boolean;
		/** Synchronisation avec le disque en cours (touche X). */
		syncing?: boolean;
		/** Grille de jaquettes, ou boutons de l'en-tête (Trier, Synchroniser). */
		zone?: 'grid' | 'header';
		/** Bouton sélectionné dans l'en-tête : 0 = Trier, 1 = Synchroniser. */
		headerIndex?: number;
	} = $props();

	const filters = FILTERS;

	const currentRow = $derived(Math.floor(index / columns));
	let scrollRow = $state(0);

	/**
	 * Deux lignes entières de jaquettes sont visibles simultanément dans la fenêtre.
	 * Descendre d'un cran (ligne 0 vers ligne 1) ne fait pas bouger la grille.
	 * Le défilement ne s'enclenche que lorsqu'on dépasse la rangée du bas.
	 */
	const VISIBLE_ROWS = 2;

	$effect(() => {
		const cur = currentRow;
		if (cur < scrollRow) {
			scrollRow = cur;
		} else if (cur >= scrollRow + VISIBLE_ROWS) {
			scrollRow = cur - VISIBLE_ROWS + 1;
		}
	});

	/**
	 * Chargement par lots : avec les bibliothèques Steam et Epic, la grille
	 * comptait des centaines de jaquettes, toutes construites (et demandées)
	 * d'un coup — le défilement saccadait. On en affiche `BATCH`, puis, quand
	 * la sélection approche du bas, une rangée « Chargement… » et le lot
	 * suivant après un court instant.
	 */
	const BATCH = 48;
	/** Rangées restantes sous la sélection qui déclenchent le lot suivant. */
	const PRELOAD_ROWS = 2;
	/** Pause avant d'ajouter le lot : on voit qu'il charge, sans attendre. */
	const BATCH_DELAY = 250;

	let limit = $state(BATCH);
	let loadingMore = $state(false);
	const shown = $derived(games.slice(0, limit));
	const hasMore = $derived(limit < games.length);

	// Nouveau filtre ou nouveau tri : on repart du premier lot.
	$effect(() => {
		void filter;
		void sort;
		limit = BATCH;
		loadingMore = false;
		if (batchTimer) clearTimeout(batchTimer);
		batchTimer = null;
	});

	/**
	 * Minuteur du lot en attente, hors de l'effet : sinon chaque déplacement
	 * de la sélection pendant la pause relançait l'effet, annulait le minuteur,
	 * et la grille restait bloquée sur « Chargement… ».
	 */
	let batchTimer: ReturnType<typeof setTimeout> | null = null;

	// La sélection approche du bas du lot : on charge le suivant. Si elle l'a
	// déjà dépassé (touche maintenue), on rattrape tout de suite.
	$effect(() => {
		if (!hasMore) return;
		if (index >= limit) {
			limit = Math.ceil((index + 1) / BATCH) * BATCH;
			return;
		}
		const lastRow = Math.ceil(limit / columns) - 1;
		if (currentRow < lastRow - PRELOAD_ROWS + 1 || batchTimer) return;
		loadingMore = true;
		batchTimer = setTimeout(() => {
			batchTimer = null;
			limit += BATCH;
			loadingMore = false;
		}, BATCH_DELAY);
	});

	$effect(() => () => {
		if (batchTimer) clearTimeout(batchTimer);
	});
</script>

<section class="library">
	<!-- Tout l'en-tête tient sur une ligne : la place gagnée va à la mosaïque. -->
	<header class="head">
		<h1>Bibliothèque</h1>
		<!-- Les gâchettes qui changent de catégorie encadrent les onglets. -->
		<div class="tabs">
			<span class="trigger"><Glyph button="l2" size="32px" /></span>
			{#each filters as entry}
				<span class="tab" class:active={entry === filter}>{FILTER_LABELS[entry]}</span>
			{/each}
			<span class="trigger"><Glyph button="r2" size="32px" /></span>
		</div>
		<p class="count">{games.length} jeux</p>
		<!-- De vrais boutons, atteints en montant depuis la première rangée :
		     X reste aux options du jeu sélectionné, comme sur l'accueil. -->
		<div class="actions">
			<span class="button" class:selected={focused && zone === 'header' && headerIndex === 0}>
				<img src="/assets/icons/library.svg" alt="" />
				Trier : {SORT_LABELS[sort]}
			</span>
			<span
				class="button"
				class:busy={syncing}
				class:selected={focused && zone === 'header' && headerIndex === 1}
			>
				<img src="/assets/icons/restart.svg" alt="" />
				{syncing ? 'Synchronisation…' : 'Synchroniser'}
			</span>
		</div>
	</header>

	<div class="viewport">
		<div class="grid" style="--columns: {columns}; --row: {scrollRow}">
			{#each shown as game, i (game.id)}
				<button
					class="tile"
					class:selected={focused && zone === 'grid' && i === index}
					class:absent={game.installed === false}
				>
					<Cover {game} />
					{#if game.installed === false}
						<!-- Possédé mais pas installé : grisé, et dit tel quel. -->
						<span class="missing"><img src="/assets/icons/download.svg" alt="" />Non installé</span>
					{/if}
					{#if isFavorite(game.id)}
						<img class="badge" src="/assets/icons/star.svg" alt="Favori" />
					{/if}
					<span class="caption">{game.title}</span>
				</button>
			{/each}
			{#if hasMore}
				<!-- Lot suivant : il arrive quand la sélection approche du bas. -->
				<div class="more">
					<span class="spinner" class:active={loadingMore}></span>
					{loadingMore ? 'Chargement des jeux suivants…' : `${games.length - limit} autres jeux`}
				</div>
			{/if}
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
		height: 100%;
		padding: 1.5vh var(--safe-x) calc(var(--safe-y) + 30px);
	}

	.head {
		display: flex;
		align-items: baseline;
		gap: 30px;
		margin-bottom: 18px;
	}

	h1 {
		margin: 0;
		font-size: clamp(28px, 2.4vw, 40px);
		font-weight: 700;
		letter-spacing: -0.02em;
	}

	.tabs {
		display: flex;
		align-items: center;
		gap: 24px;
	}

	/* Le glyphe se cale sur le texte des onglets, pas sur leur soulignement. */
	.trigger {
		display: flex;
		margin-bottom: 6px;
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
		margin: 0 0 0 auto;
		font-size: 17px;
		color: var(--text-dim);
	}

	.actions {
		display: flex;
		gap: 10px;
		align-self: center;
	}

	/* Boutons-pilules de verre, comme le dock ; sélectionnés, ils prennent le
	   contour d'accent de toute sélection. */
	.button {
		display: inline-flex;
		align-items: center;
		gap: 10px;
		padding: 9px 18px;
		border-radius: 999px;
		background: var(--dock-bg);
		border: 1px solid var(--dock-border);
		font-size: 17px;
		outline: 3px solid transparent;
		transition:
			outline-color var(--fast) var(--ease),
			background var(--fast) var(--ease);
	}

	.button.selected {
		background: var(--surface-strong);
		outline-color: var(--accent);
		box-shadow: 0 0 26px 2px var(--accent-soft);
	}

	.button img {
		width: 18px;
		height: 18px;
	}

	.button.busy img {
		animation: spin 900ms linear infinite;
	}

	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}

	/* La fenêtre rogne ce qui dépasse ; la grille se décale ligne par ligne.
	   La marge négative compensée par le padding laisse respirer la tuile
	   agrandie : sans elle, la sélection était coupée sur les bords. */
	.viewport {
		flex: 1;
		overflow: hidden;
		margin: calc(-1 * var(--hover-room));
		padding: var(--hover-room);
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

	/* Rangée de fin de lot, sur toute la largeur. */
	.more {
		grid-column: 1 / -1;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 14px;
		height: calc(var(--row-height) / 3);
		border-radius: var(--radius);
		background: var(--surface);
		font-size: 18px;
		color: var(--text-dim);
	}

	.more .spinner {
		width: 26px;
		height: 26px;
		border-radius: 50%;
		border: 4px solid var(--surface-strong);
		opacity: 0.4;
	}

	.more .spinner.active {
		border-top-color: var(--accent);
		opacity: 1;
		animation: spin 800ms linear infinite;
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

	/* Jeu possédé mais pas installé : l'affiche s'éteint, sans disparaître. */
	.tile.absent :global(img) {
		filter: grayscale(0.85) brightness(0.6);
	}

	.tile.absent.selected :global(img) {
		filter: grayscale(0.4) brightness(0.85);
	}

	.missing {
		position: absolute;
		top: 10px;
		left: 10px;
		display: inline-flex;
		align-items: center;
		gap: 6px;
		padding: 4px 10px;
		border-radius: 999px;
		background: var(--dock-bg);
		font-size: 15px;
		font-weight: 600;
	}

	.missing img {
		width: 14px;
		height: 14px;
		filter: none !important;
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
