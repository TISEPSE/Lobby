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
	let { items, index, title }: { items: MediaItem[]; index: number; title: string } = $props();

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
		<div class="stage">
			{#if item?.kind === 'video'}
				<!-- svelte-ignore a11y_media_has_caption -->
				<video bind:this={video} poster={item.thumb} playsinline></video>
				{#if paused}<span class="paused">En pause</span>{/if}
			{:else if item}
				<img src={item.src} alt="" />
			{/if}
		</div>
	{/key}

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
		padding: calc(var(--safe-y) + 50px) var(--safe-x) calc(var(--safe-y) + 40px);
		animation: fade var(--fast) var(--ease) both;
	}

	.stage img,
	.stage video {
		max-width: 100%;
		max-height: 100%;
		border-radius: var(--radius);
		box-shadow: 0 30px 80px rgba(0, 0, 0, 0.6);
		background: #000;
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
