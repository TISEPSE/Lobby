<script lang="ts">
	import type { Game } from './types';
	import type { Action } from './gamepad';
	import Cover from './Cover.svelte';
	import VirtualKeyboard from './VirtualKeyboard.svelte';
	import { normalizeForSearch } from './searchKeys';

	/**
	 * Recherche : une fenêtre, pas une page. C'est le clavier virtuel des
	 * réglages (`VirtualKeyboard`), avec les jeux qui correspondent juste en
	 * dessous, filtrés à la frappe.
	 *
	 * Bas sous la dernière rangée du clavier (ou « Valider ») passe aux jeux ;
	 * haut depuis les jeux revient au clavier. A sur un jeu ouvre sa fiche.
	 */
	let {
		open = false,
		games,
		onOpenGame,
		onClose,
	}: {
		open: boolean;
		games: Game[];
		onOpenGame: (game: Game) => void;
		onClose: () => void;
	} = $props();

	const COLUMNS = 7;

	let query = $state('');
	let zone = $state<'keys' | 'results'>('keys');
	let index = $state(0);
	let keyboard = $state<{ handleAction: (action: Action) => void } | null>(null);

	/** Comparaison sans accents ni ponctuation : « repo » trouve « R.E.P.O. ». */
	const results = $derived.by(() => {
		const needle = normalizeForSearch(query);
		return needle ? games.filter((game) => normalizeForSearch(game.title).includes(needle)) : games;
	});
	/** Une seule rangée visible : celle de la sélection. */
	const page = $derived(Math.floor(index / COLUMNS));
	const visible = $derived(results.slice(page * COLUMNS, page * COLUMNS + COLUMNS));

	$effect(() => {
		if (!open) return;
		query = '';
		zone = 'keys';
		index = 0;
	});

	/** Empreinte de la sélection, pour ne sonner que si elle bouge. */
	export function selectionKey(): string | null {
		return zone === 'keys' ? null : `results|${index}`;
	}

	export function handleAction(action: Action) {
		if (zone === 'keys') return keyboard?.handleAction(action);

		if (action === 'left') index = Math.max(0, index - 1);
		else if (action === 'right') index = Math.min(results.length - 1, index + 1);
		else if (action === 'down') {
			// Comme partout : pas de saut en diagonale depuis la dernière rangée.
			if (index + COLUMNS < results.length) index += COLUMNS;
		} else if (action === 'up') {
			if (index >= COLUMNS) index -= COLUMNS;
			else zone = 'keys';
		} else if (action === 'accept') {
			const game = results[index];
			if (game) onOpenGame(game);
		} else if (action === 'cancel') zone = 'keys';
	}

	function toResults() {
		if (results.length > 0) {
			zone = 'results';
			index = Math.min(index, results.length - 1);
		}
	}
</script>

<VirtualKeyboard
	bind:this={keyboard}
	{open}
	wide
	title="Rechercher un jeu"
	subtitle="{results.length} jeu{results.length > 1 ? 'x' : ''} — bas pour les parcourir"
	placeholder="Titre du jeu…"
	initialValue=""
	maxLength={40}
	active={zone === 'keys'}
	onInput={(value) => {
		query = value;
		index = 0;
	}}
	onLeaveBottom={toResults}
	onConfirm={toResults}
	{onClose}
>
	<div class="results" class:active={zone === 'results'} style="--columns: {COLUMNS}">
		{#if results.length === 0}
			<p class="empty">Aucun jeu ne correspond à « {query} ».</p>
		{:else}
			{#each visible as game, i (game.id)}
				<div class="tile" class:selected={zone === 'results' && page * COLUMNS + i === index}>
					<Cover {game} />
					<span class="caption">{game.title}</span>
				</div>
			{/each}
		{/if}
	</div>
	{#if results.length > COLUMNS}
		<p class="more">Rangée {page + 1} / {Math.ceil(results.length / COLUMNS)}</p>
	{/if}
</VirtualKeyboard>

<style>
	.results {
		display: grid;
		grid-template-columns: repeat(var(--columns), 1fr);
		gap: 14px;
		/* Gouttière pour l'agrandissement de la sélection. */
		padding: var(--hover-room);
		margin: calc(-1 * var(--hover-room));
		opacity: 0.7;
		transition: opacity var(--fast) var(--ease);
	}

	.results.active {
		opacity: 1;
	}

	.tile {
		position: relative;
		aspect-ratio: 2 / 3;
		border-radius: var(--radius);
		overflow: hidden;
		background: var(--surface);
		box-shadow: 0 10px 26px rgba(0, 0, 0, 0.45);
		transition: transform var(--fast) var(--ease);
	}

	.tile.selected {
		transform: scale(1.06);
		outline: 3px solid var(--accent);
		box-shadow:
			0 0 30px 6px var(--accent-soft),
			0 22px 50px rgba(0, 0, 0, 0.6);
		z-index: 1;
	}

	.caption {
		position: absolute;
		inset: auto 0 0;
		padding: 26px 8px 10px;
		font-size: 15px;
		font-weight: 600;
		text-align: center;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.9), transparent);
	}

	.empty,
	.more {
		grid-column: 1 / -1;
		margin: 0;
		font-size: 17px;
		color: var(--text-dim);
	}

	.more {
		text-align: right;
	}
</style>
