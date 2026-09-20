<script lang="ts">
	import type { Game } from './types';
	import { coverOf, ensureDetails } from './steam.svelte.js';
	import { coverFallback } from './images';

	/**
	 * Jaquette d'un jeu. Tous les jeux n'ont pas d'image verticale : dans ce cas
	 * Steam ne fournit qu'une bannière 16/9, qu'on affiche **entière** sur un
	 * fond tiré de la même image, au lieu de la recadrer sauvagement — c'est ce
	 * qui coupait les titres en deux.
	 */
	let { game }: { game: Game } = $props();

	const src = $derived(coverOf(game.appid, game.cover));
	/** Une vraie jaquette porte « library_600x900 » dans son adresse. */
	const wide = $derived(!src.includes('library_600x900'));
</script>

<span class="cover" class:wide>
	{#if wide}
		<span class="blur" style="background-image: url({src})"></span>
	{/if}
	<img
		{src}
		alt={game.title}
		onerror={(event) => {
			// L'adresse connue ne répond pas : Rust va chercher la bonne.
			ensureDetails(game.appid);
			coverFallback(event, game.appid);
		}}
	/>
</span>

<style>
	.cover {
		position: absolute;
		inset: 0;
		display: block;
		background: var(--surface);
	}

	img {
		position: relative;
		width: 100%;
		height: 100%;
		object-fit: cover;
		display: block;
	}

	/* Bannière : l'image entière, posée sur un agrandissement flou d'elle-même. */
	.wide img {
		object-fit: contain;
	}

	.blur {
		position: absolute;
		inset: -10%;
		background-size: cover;
		background-position: center;
		filter: blur(26px) saturate(1.2) brightness(0.55);
	}
</style>
