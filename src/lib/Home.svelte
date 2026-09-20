<script lang="ts">
	import type { Game, TileAction } from './types';
	import Cover from './Cover.svelte';
	import TileOptions from './TileOptions.svelte';

	/**
	 * Accueil : artwork plein écran, rangée horizontale de jaquettes. La tuile
	 * sélectionnée s'agrandit et **pousse** ses voisines plutôt que de les
	 * recouvrir — c'est le `gap` qui s'élargit autour d'elle.
	 */
	let {
		games,
		index,
		actions = [],
		optionsOpen = false,
		optionsIndex = 0,
	}: {
		games: Game[];
		index: number;
		actions?: TileAction[];
		optionsOpen?: boolean;
		optionsIndex?: number;
	} = $props();

	const selected = $derived(games[index]);

</script>

<section class="stage">
	{#if selected}
		<div class="headline">
			<h1>{selected.title}</h1>
			<p class="facts">Installé · Prêt à jouer</p>
		</div>
	{/if}

	<div class="rail" style="--index: {index}">
		{#each games as game, i (game.id)}
			<button
				class="tile"
				class:selected={i === index}
				style="--i: {i}"
				aria-current={i === index}
			>
				<Cover {game} />
				<span class="caption">{game.title}</span>
			</button>
			{#if i === index}
				<TileOptions {actions} index={optionsIndex} open={optionsOpen} />
			{/if}
		{/each}
	</div>
</section>

<style>









	.stage {
		position: relative;
		z-index: 1;
		display: flex;
		flex-direction: column;
		justify-content: flex-end;
		height: 100%;
		/* On dégage la barre d'aide : la rangée ne doit jamais venir dessous. */
		padding: 0 0 calc(var(--safe-y) + 46px);
	}

	.headline {
		padding: 0 var(--safe-x);
		margin-bottom: 4vh;
	}

	h1 {
		margin: 0;
		font-size: clamp(38px, 4.4vw, 76px);
		font-weight: 700;
		letter-spacing: -0.02em;
		/* Le titre suit la sélection sans clignoter : il glisse. */
		animation: rise var(--normal) var(--ease) both;
	}

	.facts {
		margin: 8px 0 0;
		font-size: 19px;
		color: var(--text-dim);
	}

	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(14px);
		}
	}

	.rail {
		display: flex;
		align-items: flex-end;
		gap: 18px;
		padding: 40px 0 0;
		/* La sélection se tient un peu à droite du centre : pile au milieu, la
		   rangée paraît figée et la lecture est moins naturelle. */
		transform: translateX(
			calc(50vw + var(--selection-shift) - (var(--index) + 0.5) * (var(--tile) + 18px))
		);
		transition: transform var(--normal) var(--ease);
		will-change: transform;
	}

	.tile {
		position: relative;
		flex: 0 0 var(--tile);
		width: var(--tile);
		aspect-ratio: 2 / 3;
		padding: 0;
		border-radius: var(--radius);
		overflow: hidden;
		background: var(--surface);
		transform-origin: center bottom;
		transition:
			transform var(--normal) var(--ease),
			box-shadow var(--normal) var(--ease),
			margin var(--normal) var(--ease);
		box-shadow: 0 12px 30px rgba(0, 0, 0, 0.45);
	}

	/* La tuile agrandie écarte ses voisines au lieu de passer par-dessus. */
	.tile.selected {
		transform: scale(var(--tile-focus-scale));
		margin: 0 calc(var(--tile) * (var(--tile-focus-scale) - 1) / 2);
		outline: 4.5px solid var(--accent);
		box-shadow:
			0 0 38px 8px var(--accent-soft),
			0 26px 60px rgba(0, 0, 0, 0.6);
	}

	.caption {
		position: absolute;
		inset: auto 0 0;
		padding: 26px 10px 10px;
		font-size: 14px;
		font-weight: 600;
		text-align: center;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.88), transparent);
	}
</style>
