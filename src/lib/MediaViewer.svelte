<script lang="ts">
	import type { MediaItem } from './types';

	/**
	 * Visionneuse plein écran des captures et bandes-annonces d'un jeu.
	 * Gauche / droite passent au média voisin, A met une vidéo en pause, B
	 * referme (géré par l'appelant).
	 *
	 * Les bandes-annonces de Steam ne sont plus que des flux HLS : WebKitGTK
	 * (Linux) sait les lire seul, WebView2 (Windows) non — hls.js prend alors
	 * le relais, chargé seulement quand une vidéo s'ouvre.
	 */
	let {
		items,
		index,
		title,
		volume = 1,
	}: { items: MediaItem[]; index: number; title: string; /** 0 à 1 (Réglages → Audio). */ volume?: number } = $props();

	// Volume des vidéos réglé dans Réglages → Audio (ou haut / bas ici) ; à
	// zéro, la lecture est muette.
	$effect(() => {
		if (!video) return;
		video.volume = volume;
		video.muted = volume <= 0;
	});

	/**
	 * Indicateur de volume : il apparaît quand le volume change (haut / bas),
	 * puis s'efface tout seul. Pas au premier affichage.
	 */
	let volumeShown = $state(false);
	let lastVolume = volume;
	$effect(() => {
		if (volume === lastVolume) return;
		lastVolume = volume;
		volumeShown = true;
		const timer = setTimeout(() => (volumeShown = false), 1500);
		return () => clearTimeout(timer);
	});

	const item = $derived(items[index]);
	let video = $state<HTMLVideoElement | null>(null);
	let paused = $state(false);

	$effect(() => {
		const element = video;
		const current = item;
		if (!element || current?.kind !== 'video') return;

		let destroy = () => {};
		let cancelled = false;
		paused = false;

		const start = () => {
			// Lecture avec le son ; si le webview la refuse sans geste de
			// l'utilisateur, on relance en muet plutôt que de rester figé.
			element.play().catch(() => {
				element.muted = true;
				element.play().catch(() => {});
			});
		};

		if (element.canPlayType('application/vnd.apple.mpegurl')) {
			element.src = current.src;
			start();
		} else {
			void import('hls.js').then(({ default: Hls }) => {
				if (cancelled || !Hls.isSupported()) return;
				const hls = new Hls({ capLevelToPlayerSize: true });
				hls.loadSource(current.src);
				hls.attachMedia(element);
				hls.on(Hls.Events.MANIFEST_PARSED, start);
				destroy = () => hls.destroy();
			});
		}

		return () => {
			cancelled = true;
			element.pause();
			destroy();
			element.removeAttribute('src');
		};
	});

	/** A : lecture / pause d'une vidéo. */
	export function togglePause() {
		if (!video || item?.kind !== 'video') return;
		if (video.paused) {
			video.play().catch(() => {});
			paused = false;
		} else {
			video.pause();
			paused = true;
		}
	}
</script>

<div class="viewer">
	{#key index}
		<div class="stage" class:full={item?.kind === 'video'}>
			{#if item?.kind === 'video'}
				<!-- svelte-ignore a11y_media_has_caption -->
				<video bind:this={video} poster={item.thumb} playsinline></video>
				{#if paused}<span class="paused">En pause</span>{/if}
			{:else if item}
				<img src={item.src} alt="" />
			{/if}
		</div>
	{/key}

	{#if item?.kind === 'video'}
		<div class="volume" class:shown={volumeShown}>
			<img src="/assets/icons/volume.svg" alt="" />
			<span class="bar"><span class="fill" style="width: {Math.round(volume * 100)}%"></span></span>
			<span class="percent">{Math.round(volume * 100)} %</span>
		</div>
	{/if}

	<footer class="caption">
		<span class="title">{title}</span>
		{#if item?.kind === 'video' && item.name}<span class="name">{item.name}</span>{/if}
		<span class="count">{index + 1} / {items.length}</span>
	</footer>
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
	.stage img,
	.stage video {
		max-width: calc(100vw - 2 * var(--safe-x));
		max-height: calc(100vh - 2 * var(--viewer-inset));
		border-radius: var(--radius);
		box-shadow: 0 30px 80px rgba(0, 0, 0, 0.6);
		background: #000;
	}

	/* Une bande-annonce prend tout l'écran, bord à bord : c'est du cinéma, la
	   légende passe par-dessus, sur un dégradé. */
	.stage.full video {
		width: 100vw;
		height: 100vh;
		max-width: none;
		max-height: none;
		border-radius: 0;
		box-shadow: none;
		object-fit: contain;
	}

	/* Indicateur de volume, en haut à droite sous le compteur. */
	.volume {
		position: absolute;
		top: calc(var(--safe-y) + 50px);
		right: var(--safe-x);
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 12px 18px;
		border-radius: 999px;
		background: var(--dock-bg);
		backdrop-filter: blur(18px);
		font-size: 17px;
		font-weight: 700;
		opacity: 0;
		transform: translateY(-6px);
		transition:
			opacity var(--fast) var(--ease),
			transform var(--fast) var(--ease);
	}

	.volume.shown {
		opacity: 1;
		transform: none;
	}

	.volume img {
		width: 24px;
		height: 24px;
	}

	.volume .bar {
		position: relative;
		width: var(--volume-bar);
		height: var(--volume-bar-height);
		border-radius: 999px;
		background: var(--surface-strong);
		overflow: hidden;
	}

	.volume .fill {
		position: absolute;
		inset: 0 auto 0 0;
		background: var(--accent);
		transition: width var(--fast) var(--ease);
	}

	.volume .percent {
		min-width: 4ch;
		text-align: right;
		font-variant-numeric: tabular-nums;
	}

	.paused {
		position: absolute;
		padding: 12px 22px;
		border-radius: 999px;
		background: var(--dock-bg);
		font-size: 20px;
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
		/* Lisible même posée sur une vidéo plein écran. */
		text-shadow: 0 2px 12px rgba(0, 0, 0, 0.8);
	}

	.title {
		font-weight: 700;
	}

	.name {
		color: var(--text-dim);
	}

	.count {
		margin-left: auto;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}
</style>
