<script lang="ts">
	/**
	 * Vidéo d'introduction, jouée au lancement par-dessus l'interface déjà
	 * construite derrière. Si le fichier est illisible, on passe directement à
	 * l'accueil plutôt que de rester sur un écran noir.
	 */
	let {
		src,
		volume = 1,
		onFinished,
	}: { src: string; /** 0 à 1 (Réglages → Audio). */ volume?: number; onFinished: () => void } = $props();

	let hintVisible = $state(false);
	let video = $state<HTMLVideoElement | null>(null);

	$effect(() => {
		// L'invite n'apparaît qu'après un instant : elle gênerait les premières
		// images.
		const timer = setTimeout(() => (hintVisible = true), 1400);
		return () => clearTimeout(timer);
	});

	function skip() {
		video?.pause();
		onFinished();
	}
</script>

<div class="boot">
	<video
		bind:this={video}
		{src}
		autoplay
		muted={volume <= 0}
		{volume}
		playsinline
		onended={onFinished}
		onerror={onFinished}
	></video>
	{#if hintVisible}
		<p class="hint">Appuyer sur une touche pour passer</p>
	{/if}
</div>

<svelte:window onkeydown={skip} />

<style>
	.boot {
		position: fixed;
		inset: 0;
		z-index: 10;
		display: grid;
		place-items: center;
		background: #000;
		animation: fade-in 120ms var(--ease) both;
	}

	video {
		width: 100%;
		height: 100%;
		object-fit: contain;
		background: #000;
	}

	.hint {
		position: absolute;
		right: var(--safe-x);
		bottom: calc(var(--safe-y) * 0.6);
		margin: 0;
		font-size: 17px;
		color: var(--text-dim);
		animation: fade-in var(--normal) var(--ease) both;
	}

	@keyframes fade-in {
		from {
			opacity: 0;
		}
	}
</style>
