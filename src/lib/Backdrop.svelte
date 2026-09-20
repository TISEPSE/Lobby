<script lang="ts">
	/**
	 * Artwork du jeu sélectionné, en fondu enchaîné. Deux couches se relaient :
	 * la nouvelle image n'apparaît qu'une fois chargée, sinon on verrait un
	 * clignotement noir à chaque déplacement de la sélection.
	 */
	let { src, dimmed = false }: { src: string; dimmed?: boolean } = $props();

	let shown = $state('');
	let previous = $state('');

	$effect(() => {
		const next = src;
		if (!next || next === shown) return;
		const image = new Image();
		image.onload = () => {
			previous = shown;
			shown = next;
		};
		image.src = next;
	});
</script>

<div class="backdrop" class:dimmed>
	{#if previous}
		<div class="layer" style="background-image: url({previous})"></div>
	{/if}
	{#key shown}
		<div class="layer fade" style="background-image: url({shown})"></div>
	{/key}
	<div class="scrim"></div>
</div>

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		z-index: 0;
		background: var(--bg);
	}

	.layer {
		position: absolute;
		inset: 0;
		background-size: cover;
		background-position: center;
		transform: scale(1.04);
	}

	/* Le fondu dure plus longtemps que le déplacement de la sélection : on ne
	   voit jamais de coupure, même en parcourant la rangée rapidement. */
	.fade {
		animation: appear 520ms var(--ease) both;
	}

	@keyframes appear {
		from {
			opacity: 0;
			transform: scale(1.07);
		}
		to {
			opacity: 1;
			transform: scale(1.04);
		}
	}

	/* Voile dégradé : lisible en bas, artwork préservé en haut. */
	.scrim {
		position: absolute;
		inset: 0;
		background:
			linear-gradient(to top, rgba(7, 8, 11, 0.99) 14%, rgba(7, 8, 11, 0.82) 38%, rgba(7, 8, 11, 0.45) 62%, rgba(7, 8, 11, 0.25) 100%),
			radial-gradient(130% 100% at 50% 0%, rgba(7, 8, 11, 0.1) 35%, rgba(7, 8, 11, 0.8) 100%);
		transition: opacity var(--normal) var(--ease);
	}

	/* Sur une fiche, le texte prime — mais l'artwork doit rester perceptible,
	   sinon autant afficher un fond noir. */
	.dimmed .scrim {
		background:
			linear-gradient(to right, rgba(7, 8, 11, 0.96) 38%, rgba(7, 8, 11, 0.72) 62%, rgba(7, 8, 11, 0.5) 100%),
			linear-gradient(to top, rgba(7, 8, 11, 0.9) 8%, rgba(7, 8, 11, 0.45) 55%, rgba(7, 8, 11, 0.4) 100%);
	}
</style>
