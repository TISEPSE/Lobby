<script lang="ts">
	import type { Action } from './gamepad';
	import type { MediaItem } from './types';
	import VideoPlayer from './VideoPlayer.svelte';

	/**
	 * Visionneuse plein écran des captures et bandes-annonces d'un jeu. Une
	 * capture s'affiche centrée ; une bande-annonce passe dans le lecteur
	 * (`VideoPlayer.svelte`), avec ses commandes affichées. L'appelant gère B,
	 * le volume et le passage au média voisin.
	 */
	let {
		items,
		index,
		title,
		volume = 1,
	}: { items: MediaItem[]; index: number; title: string; /** 0 à 1 (Réglages → Audio). */ volume?: number } =
		$props();

	const item = $derived(items[index]);
	let player = $state<{ handleAction: (action: Action) => void; poke: () => void } | null>(null);

	/** Touches du lecteur (A, gauche / droite) ; sur une capture, rien. */
	export function handleAction(action: Action) {
		player?.handleAction(action);
	}

	/** Une touche gérée par l'appelant (volume, média voisin) ravive les commandes. */
	export function poke() {
		player?.poke();
	}
</script>

<div class="viewer">
	{#key index}
		{#if item?.kind === 'video'}
			<VideoPlayer
				bind:this={player}
				src={item.src}
				poster={item.thumb}
				{title}
				name={item.name ?? ''}
				position="{index + 1} / {items.length}"
				{volume}
				hasNeighbours={items.length > 1}
			/>
		{:else if item}
			<div class="stage">
				<img src={item.src} alt="" />
			</div>
		{/if}
	{/key}

	{#if item?.kind !== 'video'}
		<footer class="caption">
			<span class="title">{title}</span>
			<span class="count">{index + 1} / {items.length}</span>
		</footer>
	{/if}
</div>

<style>
	.viewer {
		position: fixed;
		inset: 0;
		z-index: 5;
		display: grid;
		place-items: center;
		background: var(--viewer-bg);
		animation: fade var(--normal) var(--ease) both;
	}

	@keyframes fade {
		from {
			opacity: 0;
		}
	}

	.stage {
		position: relative;
		display: grid;
		place-items: center;
		width: 100%;
		height: 100%;
		animation: fade var(--fast) var(--ease) both;
	}

	/* Bornée sur l'écran, pas en pourcentage : dans une grille aux rangées
	   automatiques, `max-height: 100%` ne s'appliquait pas et l'image
	   débordait en bas. Même marge en haut et en bas : elle est pile au
	   centre de l'écran, la légende tient dans la marge du haut. */
	.stage img {
		max-width: calc(100vw - 2 * var(--safe-x));
		max-height: calc(100vh - 2 * var(--viewer-inset));
		border-radius: var(--radius);
		box-shadow: 0 30px 80px rgba(0, 0, 0, 0.6);
		background: #000;
	}

	.caption {
		position: absolute;
		left: var(--safe-x);
		right: var(--safe-x);
		top: var(--safe-y);
		display: flex;
		align-items: baseline;
		gap: 18px;
		font-size: 19px;
		text-shadow: 0 2px 12px rgba(0, 0, 0, 0.8);
	}

	.title {
		font-weight: 700;
	}

	.count {
		margin-left: auto;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}
</style>
