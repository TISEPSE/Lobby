<script lang="ts">
	import type { Game } from './types';
	import type { Action } from './gamepad';
	import Cover from './Cover.svelte';
	import { isFavorite } from './library.svelte.js';
	import { SEARCH_ROWS, SEARCH_COLUMNS } from './searchKeys';

	/**
	 * Recherche dans la bibliothèque.
	 *
	 * Le clavier reste affiché en permanence, comme sur une console : on tape,
	 * les résultats se mettent à jour sous les doigts. Descendre depuis la
	 * dernière rangée de touches amène dans les résultats, remonter ramène au
	 * clavier — pas de modale à ouvrir et refermer.
	 */
	let {
		games,
		query = '',
		zone = 'keys',
		keyIndex = 0,
		resultIndex = 0,
		columns = 6,
	}: {
		games: Game[];
		query?: string;
		zone?: 'keys' | 'results';
		keyIndex?: number;
		resultIndex?: number;
		columns?: number;
	} = $props();

	const row = $derived(Math.floor(keyIndex / SEARCH_COLUMNS));
	const col = $derived(keyIndex % SEARCH_COLUMNS);
	const resultRow = $derived(Math.floor(resultIndex / columns));

	/**
	 * Deux rangées tiennent sous le champ de recherche. La grille ne bouge que
	 * lorsque la sélection dépasse la rangée du bas : sinon elle sauterait dès
	 * le premier déplacement.
	 */
	const VISIBLE_ROWS = 2;
	let scrollRow = $state(0);

	$effect(() => {
		const current = resultRow;
		if (current < scrollRow) scrollRow = current;
		else if (current >= scrollRow + VISIBLE_ROWS) scrollRow = current - VISIBLE_ROWS + 1;
	});
</script>

<section class="search">
	<header class="head">
		<h1>Recherche</h1>
		<div class="field" class:active={zone === 'keys'}>
			{#if query}
				<span class="typed">{query}</span>
			{:else}
				<span class="placeholder">Titre du jeu…</span>
			{/if}
			<span class="caret" class:blink={zone === 'keys'}></span>
		</div>
		<p class="count">{games.length} résultat{games.length > 1 ? 's' : ''}</p>
	</header>

	<div class="body">
		<div class="keyboard" class:dimmed={zone !== 'keys'}>
			{#each SEARCH_ROWS as keyRow, r}
				<div class="krow">
					{#each keyRow as key, c}
						<span class="key" class:selected={zone === 'keys' && r === row && c === col}>
							{key}
						</span>
					{/each}
				</div>
			{/each}
			<p class="legend">Effacer avec B · Espace avec Y</p>
		</div>

		<div
			class="results"
			class:dimmed={zone !== 'results'}
			style="--columns: {columns}; --row: {scrollRow}"
		>
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
		margin-bottom: 20px;
	}

	h1 {
		margin: 0;
		font-size: clamp(28px, 2.4vw, 40px);
		font-weight: 700;
		letter-spacing: -0.02em;
	}

	/* Le texte saisi, dans un champ qui s'allume quand le clavier a la main. */
	.field {
		display: flex;
		align-items: center;
		gap: 2px;
		min-width: 420px;
		padding: 10px 18px;
		border-radius: var(--radius);
		background: rgba(255, 255, 255, 0.05);
		font-size: 22px;
		transition: box-shadow var(--fast) var(--ease);
	}

	.field.active {
		box-shadow: inset 0 0 0 2px var(--accent);
	}

	.placeholder {
		color: var(--text-dim);
	}

	.caret {
		width: 2px;
		height: 24px;
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

	.count {
		margin: 0 0 0 auto;
		font-size: 17px;
		color: var(--text-dim);
	}

	.body {
		display: grid;
		grid-template-columns: minmax(320px, 26vw) 1fr;
		/* La ligne ne dépasse pas la place disponible : sans cette contrainte,
		   la grille des résultats s'étirait et une rangée débordait de l'écran. */
		grid-template-rows: minmax(0, 1fr);
		gap: 3vw;
		flex: 1;
		min-height: 0;
	}

	.keyboard {
		display: flex;
		flex-direction: column;
		gap: 8px;
		align-content: start;
		transition: opacity var(--fast) var(--ease);
	}

	/* La zone inactive s'efface sans disparaître : on sait où on reviendra. */
	.dimmed {
		opacity: 0.45;
	}

	.krow {
		display: grid;
		grid-template-columns: repeat(10, 1fr);
		gap: 8px;
	}

	.key {
		display: grid;
		place-items: center;
		aspect-ratio: 1;
		border-radius: 10px;
		background: rgba(255, 255, 255, 0.06);
		font-size: 18px;
		font-weight: 600;
		transition:
			background var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease),
			transform var(--fast) var(--ease);
	}

	.key.selected {
		background: var(--accent);
		color: #06210f;
		transform: scale(1.08);
		box-shadow: 0 0 20px 4px var(--accent-soft);
	}

	.legend {
		margin: 6px 0 0;
		font-size: 14px;
		color: var(--text-dim);
	}

	/* La fenêtre des résultats fait exactement deux rangées : au-delà, la grille
	   glisse sous elle. Sans hauteur explicite, une troisième rangée débordait
	   de l'écran. */
	.results {
		--gap: 16px;
		/* Hauteur en unités d'écran : un pourcentage dans une variable se
		   résoudrait ici contre la hauteur du parent, pas sa largeur, et le
		   calcul partait faux. Deux rangées font un peu plus de la moitié de
		   l'écran. */
		--row-height: 25.5vh;

		height: calc(2 * var(--row-height) + var(--gap));
		overflow: hidden;
		min-height: 0;
		transition: opacity var(--fast) var(--ease);
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
