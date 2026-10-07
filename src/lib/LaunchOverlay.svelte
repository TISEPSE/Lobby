<script lang="ts">
	/**
	 * Écran de lancement : pendant qu'un jeu démarre, Lobby reste au-dessus de
	 * tout et montre ceci — l'artwork du jeu qui avance lentement, la jaquette
	 * qui respire, le nom et une barre de chargement. On ne voit ni le bureau,
	 * ni les fenêtres de lancement : on passe directement de Lobby au jeu.
	 */
	import { fade } from 'svelte/transition';
	import type { Game } from './types';
	import Cover from './Cover.svelte';
	import Glyph from './Glyph.svelte';
	import { heroFor } from './steam.svelte.js';
	import { platformOf } from './stats';

	let {
		game,
		slow = false,
	}: {
		game: Game;
		/** Le jeu tarde (mise à jour, launcher) : on propose de revenir à Lobby. */
		slow?: boolean;
	} = $props();
</script>

<div class="launch" transition:fade={{ duration: 260 }}>
	<div class="art" style="background-image: url({heroFor(game)})"></div>
	<div class="veil"></div>

	<div class="center">
		<div class="cover"><Cover {game} /></div>
		<span class="store">{platformOf(game)}</span>
		<h1>{game.title}</h1>
		<div class="bar"><span></span></div>
		<p class="status">{slow ? 'Le jeu prend son temps…' : 'Lancement…'}</p>
	</div>

	{#if slow}
		<p class="hint" transition:fade={{ duration: 260 }}>
			<Glyph button="b" size="28px" />Revenir à Lobby
		</p>
	{/if}
</div>

<style>
	.launch {
		position: fixed;
		inset: 0;
		z-index: 20;
		display: grid;
		place-items: center;
		background: var(--bg);
		overflow: hidden;
	}

	/* L'artwork avance lentement : l'écran vit pendant l'attente. */
	.art {
		position: absolute;
		inset: -4%;
		background-size: cover;
		background-position: center;
		filter: blur(var(--launch-blur));
		animation: drift var(--launch-drift) linear both;
	}

	.veil {
		position: absolute;
		inset: 0;
		background: radial-gradient(circle at center, var(--launch-veil-center), var(--launch-veil-edge));
	}

	.center {
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 14px;
		animation: rise var(--normal) var(--ease) both;
	}

	/* La jaquette respire, avec le halo d'accent de la sélection. */
	.cover {
		position: relative;
		width: var(--launch-cover);
		aspect-ratio: 2 / 3;
		margin-bottom: 18px;
		border-radius: var(--radius);
		overflow: hidden;
		box-shadow: 0 0 0 3px var(--accent), 0 0 40px 8px var(--accent-soft);
		animation: breathe var(--launch-breath) var(--ease) infinite alternate;
	}

	.store {
		font-size: 17px;
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--accent);
	}

	h1 {
		margin: 0;
		max-width: 70vw;
		font-size: 48px;
		font-weight: 800;
		text-align: center;
		line-height: 1.1;
	}

	/* Barre indéterminée : un trait d'accent qui court d'un bord à l'autre. */
	.bar {
		position: relative;
		width: var(--launch-bar);
		height: 6px;
		margin-top: 16px;
		border-radius: 999px;
		background: var(--surface-strong);
		overflow: hidden;
	}

	.bar span {
		position: absolute;
		inset: 0 auto 0 0;
		width: 35%;
		border-radius: inherit;
		background: var(--accent);
		box-shadow: 0 0 14px var(--accent-soft);
		animation: run var(--launch-run) var(--ease) infinite;
	}

	.status {
		margin: 4px 0 0;
		font-size: 19px;
		color: var(--text-dim);
	}

	.hint {
		position: absolute;
		bottom: var(--safe-y);
		display: flex;
		align-items: center;
		gap: 10px;
		margin: 0;
		font-size: 18px;
		color: var(--text-dim);
	}

	@keyframes drift {
		from {
			transform: scale(1);
		}
		to {
			transform: scale(1.12);
		}
	}

	@keyframes breathe {
		to {
			transform: scale(1.04);
			box-shadow: 0 0 0 3px var(--accent), 0 0 64px 14px var(--accent-soft);
		}
	}

	@keyframes run {
		from {
			transform: translateX(-100%);
		}
		to {
			transform: translateX(290%);
		}
	}

	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(16px);
		}
	}
</style>
