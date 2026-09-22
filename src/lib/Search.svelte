<script lang="ts">
	import type { Game } from './types';
	import Cover from './Cover.svelte';
	import Keyboard from './Keyboard.svelte';
	import { isFavorite } from './library.svelte.js';

	/**
	 * Recherche.
	 *
	 * L'écran reprend la mise en page de la bibliothèque — même titre, même
	 * grille, mêmes jaquettes — pour qu'on ne change pas de monde en appuyant
	 * sur Y. Ce qui s'ajoute, c'est une grande barre de saisie en tête et le
	 * clavier à l'écran juste en dessous.
	 *
	 * Le clavier se replie dès qu'on descend dans les résultats : la grille
	 * récupère la place, et remonter le ramène.
	 */
	let {
		games,
		query = '',
		zone = 'keys',
		keyRow = 0,
		keyCol = 0,
		resultIndex = 0,
		columns = 6,
	}: {
		games: Game[];
		query?: string;
		zone?: 'keys' | 'results';
		keyRow?: number;
		keyCol?: number;
		resultIndex?: number;
		columns?: number;
	} = $props();

	const resultRow = $derived(Math.floor(resultIndex / columns));

	/**
	 * Une rangée de résultats est visible tant que le clavier est déployé, trois
	 * une fois replié. La grille ne glisse que lorsque la sélection sort de la
	 * fenêtre : sinon elle sauterait au premier déplacement.
	 */
	const visibleRows = $derived(zone === 'keys' ? 1 : 3);
	let scrollRow = $state(0);

	$effect(() => {
		const current = resultRow;
		const rows = visibleRows;
		if (current < scrollRow) scrollRow = current;
		else if (current >= scrollRow + rows) scrollRow = current - rows + 1;
	});
</script>

<section class="search">
	<header class="head">
		<h1>Recherche</h1>
		<p class="count">{games.length} résultat{games.length > 1 ? 's' : ''}</p>
	</header>

	<!-- La barre prend toute la largeur : c'est l'objet principal de l'écran. -->
	<div class="field" class:active={zone === 'keys'}>
		<img class="glass" src="/assets/icons/search.svg" alt="" />
		{#if query}
			<span class="typed">{query}</span>
		{:else}
			<span class="placeholder">Titre du jeu…</span>
		{/if}
		<span class="caret" class:blink={zone === 'keys'}></span>
	</div>

	<div class="pad" class:folded={zone !== 'keys'}>
		<Keyboard row={keyRow} col={keyCol} active={zone === 'keys'} />
	</div>

	<div class="results" class:dimmed={zone !== 'results'} style="--columns: {columns}; --row: {scrollRow}">
		{#if games.length === 0}
			<p class="empty">
				{query ? `Aucun jeu ne correspond à « ${query} ».` : 'Tape un titre pour chercher.'}
			</p>
		{:else}
			<div class="grid">
				{#each games as game, i (game.id)}
					<button class="tile" class:selected={zone === 'results' && i === resultIndex}>
						<Cover {game} />
						{#if isFavorite(game.id)}
							<img class="badge" src="/assets/icons/star.svg" alt="Favori" />
						{/if}
						<span class="caption">{game.title}</span>
					</button>
				{/each}
			</div>
		{/if}
	</div>
</section>

<style>
	.search {
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
		margin-bottom: 14px;
	}

	h1 {
		margin: 0;
		font-size: clamp(28px, 2.4vw, 40px);
		font-weight: 700;
		letter-spacing: -0.02em;
	}

	.count {
		margin: 0 0 0 auto;
		font-size: 17px;
		color: var(--text-dim);
	}

	.field {
		display: flex;
		align-items: center;
		gap: 4px;
		padding: 16px 26px;
		border-radius: var(--radius);
		background: rgba(255, 255, 255, 0.05);
		font-size: 30px;
		transition: box-shadow var(--fast) var(--ease);
	}

	.field.active {
		box-shadow: inset 0 0 0 2px var(--accent);
	}

	.glass {
		width: 26px;
		height: 26px;
		margin-right: 16px;
		opacity: 0.6;
	}

	.placeholder {
		color: var(--text-dim);
	}

	.caret {
		width: 2px;
		height: 32px;
		background: var(--accent);
		opacity: 0;
	}

	.caret.blink {
		animation: blink 1s steps(2, start) infinite;
	}

	@keyframes blink {
		0% {
			opacity: 1;
		}
		100% {
			opacity: 0;
		}
	}

	/* Le clavier se replie en hauteur : la grille en dessous remonte toute
	   seule, sans qu'on ait à mesurer quoi que ce soit. */
	.pad {
		--key-size: 52px;
		--key-font: 24px;
		--key-gap: 8px;

		overflow: hidden;
		max-height: 340px;
		padding: 18px 0 6px;
		transition:
			max-height var(--normal) var(--ease),
			opacity var(--normal) var(--ease),
			padding var(--normal) var(--ease);
	}

	.pad.folded {
		max-height: 0;
		padding: 0;
		opacity: 0;
	}

	.results {
		--gap: 16px;
		/* Les jaquettes gardent leur format 2/3, comme partout ailleurs : la
		   hauteur d'une rangée se déduit donc de la largeur disponible. Tout est
		   en unités d'écran — un pourcentage dans une variable se résoudrait
		   contre la hauteur du parent, pas sa largeur. */
		--tile-width: calc((100vw - 2 * var(--safe-x) - (var(--columns) - 1) * var(--gap)) / var(--columns));
		--row-height: calc(var(--tile-width) * 1.5);

		flex: 1;
		min-height: 0;
		overflow: hidden;
		padding-top: 14px;
		/* La rangée suivante s'estompe au lieu d'être tranchée net : on comprend
		   qu'il y a une suite sans voir une bande de jaquettes coupées. */
		mask-image: linear-gradient(to bottom, #000 82%, transparent);
		transition: opacity var(--fast) var(--ease);
	}

	.dimmed {
		opacity: 0.55;
	}

	.grid {
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
		width: 22px;
		height: 22px;
		filter: drop-shadow(0 2px 6px rgba(0, 0, 0, 0.8));
	}

	.caption {
		position: absolute;
		inset: auto 0 0;
		padding: 28px 8px 10px;
		font-size: 14px;
		font-weight: 600;
		text-align: center;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.9), transparent);
	}

	.empty {
		margin-top: 20px;
		font-size: 20px;
		color: var(--text-dim);
	}
</style>
