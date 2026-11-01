<script lang="ts">
	import type { Game } from './types';
	import { ensureDetails, ensureArtwork, coverFor } from './steam.svelte.js';

	let {
		game,
		override = '',
		near = true,
	}: {
		game: Game;
		/**
		 * Tuile proche de l'écran. Les autres attendent pour demander fiche et
		 * visuels : un lot de 48 lançait sinon 48 recherches d'un coup.
		 */
		near?: boolean;
		/**
		 * Image imposée, quelle que soit l'affiche retenue pour ce jeu. Sert à
		 * l'aperçu du choix d'affiche : la tuile est alors rendue exactement
		 * comme elle le sera une fois le choix validé.
		 */
		override?: string;
	} = $props();

	$effect(() => {
		// En aperçu, rien à chercher : l'image est déjà connue.
		if (override || !near) return;
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

	// Même logique que le préchargement du démarrage (`coverFor`).
	const coverSrc = $derived(override || coverFor(game));

	let failed = $state(false);

	// Une nouvelle image arrive (fiche, affiche téléchargée) : on la retente.
	$effect(() => {
		void coverSrc;
		failed = false;
	});

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
	{#if coverSrc && !failed}
		<img
			class="art"
			src={coverSrc}
			alt={game.title}
			loading="lazy"
			decoding="async"
			onerror={onError}
		/>
	{:else}
		<!-- Aucune image : une tuile unie et le titre, rien d'inventé autour.
		     `Home` et `Library` masquent alors leur légende, qui le répéterait. -->
		<span class="plain"><span class="plain-title">{game.title}</span></span>
	{/if}
</span>

<style>
	.cover {
		position: absolute;
		inset: 0;
		display: block;
		background: var(--cover-plain);
	}

	.art {
		position: relative;
		width: 100%;
		height: 100%;
		object-fit: cover;
		display: block;
	}

	.plain {
		position: absolute;
		inset: 0;
		display: grid;
		place-items: center;
		padding: var(--cover-plain-pad);
		box-shadow: inset 0 0 0 1px var(--cover-plain-line);
		border-radius: inherit;
	}

	.plain-title {
		display: -webkit-box;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 5;
		overflow: hidden;
		font-size: var(--cover-plain-title);
		font-weight: 700;
		line-height: 1.25;
		text-align: center;
		text-wrap: balance;
		overflow-wrap: anywhere;
	}
</style>
