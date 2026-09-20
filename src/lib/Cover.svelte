<script lang="ts">
	import type { Game } from './types';
	import { details, ensureDetails, artStyles } from './steam.svelte.js';

	/**
	 * Jaquette d'un jeu.
	 *
	 * Tous les jeux n'ont pas d'image verticale chez Steam. Plutôt que d'étirer
	 * une bannière 16/9 dans une tuile 2/3 — ce qui coupe les titres et fait
	 * laid — on **compose** une jaquette : l'artwork du jeu en fond, assombri,
	 * et le logo détouré par-dessus. À défaut de logo, le titre.
	 */
	let { game }: { game: Game } = $props();

	const sheet = $derived(details[game.appid]);

	/** Affiche demandée pour ce jeu : jaquette par défaut. */
	const style = $derived(artStyles[game.appid] ?? 'auto');

	/** Vraie jaquette verticale : celle du fichier, ou celle résolue par Rust. */
	const vertical = $derived(
		style !== 'auto'
			? ''
			: sheet
				? sheet.cover
				: game.cover.includes('library_600x900')
					? game.cover
					: ''
	);
	/** Fond de la jaquette composée : artwork, sinon bannière. */
	const backdrop = $derived(
		style === 'banner'
			? sheet?.banner || sheet?.hero || game.hero
			: sheet?.hero || sheet?.banner || game.hero
	);
	const logo = $derived(sheet?.logo ?? '');

	/** Une image qui ne répond pas déclenche la résolution par Rust. */
	function resolve() {
		ensureDetails(game.appid);
	}
</script>

<span class="cover">
	{#if vertical}
		<img class="art" src={vertical} alt={game.title} onerror={resolve} />
	{:else}
		<!-- Jaquette composée : l'artwork en fond, le logo ou le titre devant. -->
		<span class="made">
			<img class="art blurred" src={backdrop} alt="" onerror={resolve} />
			<span class="veil"></span>
			{#if logo}
				<img class="logo" src={logo} alt={game.title} />
			{:else}
				<span class="name">{game.title}</span>
			{/if}
		</span>
	{/if}
</span>

<style>
	.cover {
		position: absolute;
		inset: 0;
		display: block;
		background: #0c0e13;
	}

	.art {
		position: relative;
		width: 100%;
		height: 100%;
		object-fit: cover;
		display: block;
	}

	.made {
		position: absolute;
		inset: 0;
		display: grid;
		place-items: center;
	}

	/* L'artwork est cadré serré et adouci : il sert de décor, pas de sujet. */
	.blurred {
		position: absolute;
		inset: 0;
		filter: saturate(1.1) brightness(0.8);
		transform: scale(1.08);
	}

	.veil {
		position: absolute;
		inset: 0;
		background:
			linear-gradient(180deg, rgba(8, 10, 14, 0.55) 0%, rgba(8, 10, 14, 0.2) 45%, rgba(8, 10, 14, 0.9) 100%),
			radial-gradient(90% 60% at 50% 45%, rgba(8, 10, 14, 0) 0%, rgba(8, 10, 14, 0.55) 100%);
	}

	.logo {
		position: relative;
		width: 78%;
		max-height: 46%;
		object-fit: contain;
		filter: drop-shadow(0 6px 18px rgba(0, 0, 0, 0.75));
	}

	.name {
		position: relative;
		padding: 0 14px;
		font-size: clamp(16px, 1.3vw, 24px);
		font-weight: 700;
		line-height: 1.15;
		text-align: center;
		text-wrap: balance;
		filter: drop-shadow(0 4px 14px rgba(0, 0, 0, 0.8));
	}
</style>
