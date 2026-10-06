<script lang="ts">
	import type { Game } from './types';
	import { details, ensureDetails, artStyles, artwork, ensureArtwork, coverFor } from './steam.svelte.js';
	import { generateProceduralCover } from './art';

	let {
		game,
		override = '',
	}: {
		game: Game;
		/**
		 * Image imposée, quelle que soit l'affiche retenue pour ce jeu. Sert à
		 * l'aperçu du choix d'affiche : la tuile est alors rendue exactement
		 * comme elle le sera une fois le choix validé.
		 */
		override?: string;
	} = $props();

	$effect(() => {
		// En aperçu, rien à chercher : l'image est déjà connue.
		if (override) return;
		// Les métadonnées (note, genres, résumé) viennent de l'appid…
		if (game.appid) {
			ensureDetails(game.appid);
		}
		// …mais la jaquette est téléchargée une fois pour tous les jeux, avec ou
		// sans appid : ensuite elle s'affiche depuis le disque. Un jeu Epic non
		// installé arrive avec la jaquette officielle de son catalogue : inutile
		// de lancer une recherche pour chacun des centaines de jeux possédés.
		if (game.installed === false && game.cover) return;
		ensureArtwork(game);
	});

	const online = $derived(artwork[game.id]);

	const sheet = $derived(game.appid ? details[game.appid] : undefined);
	// L'affiche choisie est rangée sous l'identifiant du jeu : un appid peut
	// manquer, un id jamais.
	const style = $derived(artStyles[game.id] ?? 'auto');

	// Même logique que le préchargement du démarrage (`coverFor`).
	const coverSrc = $derived(override || coverFor(game));

	let failed = $state(false);

	function onError() {
		if (!failed) {
			failed = true;
			if (game.appid) {
				ensureDetails(game.appid);
			} else {
				ensureArtwork(game);
			}
		}
	}
</script>

<span class="cover">
	{#if !failed}
		<img
			class="art"
			src={coverSrc}
			alt={game.title}
			loading="lazy"
			onerror={onError}
		/>
	{:else}
		<img
			class="art"
			src={generateProceduralCover(game.title, game.source)}
			alt={game.title}
			loading="lazy"
		/>
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
