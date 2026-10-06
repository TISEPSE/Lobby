<script lang="ts">
	import type { Action } from './gamepad';
	import Glyph from './Glyph.svelte';

	/**
	 * Lecteur des bandes-annonces, plein écran, façon lecteur multimédia Xbox :
	 * barre de progression (écoulé / durée), et **toutes les touches affichées**
	 * — rien n'est à deviner. Les commandes s'effacent après quelques secondes
	 * de lecture sans toucher à rien, comme sur YouTube, et reviennent au
	 * moindre appui ou à la pause. Chaque action fait apparaître brièvement son
	 * icône au centre (lecture, pause, ±10 s).
	 *
	 * Touches : A lecture / pause (ou revoir à la fin) · gauche / droite
	 * déplacent **directement le curseur de la barre** (pas de 5 s ; maintenu,
	 * il défile, le temps visé s'affiche au-dessus) · haut / bas le volume,
	 * jauge verticale sur le côté (géré par l'appelant, qui passe `volume`) ·
	 * L1 / R1 média précédent / suivant (idem) · B fermer.
	 *
	 * Les bandes-annonces de Steam ne sont plus que des flux HLS : WebKitGTK
	 * (Linux) sait les lire seul, WebView2 (Windows) non — hls.js prend alors
	 * le relais, chargé seulement à l'ouverture.
	 */
	let {
		src,
		poster = '',
		title,
		name = '',
		/** « 2 / 5 » parmi les médias de la fiche. */
		position = '',
		/** 0 à 1 (Réglages → Audio → Vidéos, ou haut / bas ici). */
		volume = 1,
		/** Il existe un média avant / après : L1 / R1 ont un sens. */
		hasNeighbours = false,
	}: {
		src: string;
		poster?: string;
		title: string;
		name?: string;
		position?: string;
		volume?: number;
		hasNeighbours?: boolean;
	} = $props();

	/** Pas du curseur à chaque appui sur gauche / droite, en secondes. */
	const SEEK = 5;
	/** Commandes visibles tant que la lecture n'a pas duré ce temps sans appui. */
	const HUD_DELAY = 3000;

	let video = $state<HTMLVideoElement | null>(null);
	let paused = $state(false);
	let ended = $state(false);
	let waiting = $state(true);
	let current = $state(0);
	let duration = $state(0);
	let buffered = $state(0);

	let hudVisible = $state(true);
	let hudTimer: ReturnType<typeof setTimeout> | null = null;

	/** Icône brève au centre de l'écran ; `key` relance l'animation. */
	let flash = $state<{ key: number; icon?: string; text?: string } | null>(null);
	let flashKey = 0;

	/** Le curseur vient d'être déplacé : il grossit et affiche le temps visé. */
	let scrubbing = $state(false);
	let scrubTimer: ReturnType<typeof setTimeout> | null = null;

	/** Le volume vient de changer : sa jauge reste visible un instant. */
	let volumeActive = $state(false);
	let volumeTimer: ReturnType<typeof setTimeout> | null = null;
	let lastVolume = volume;
	$effect(() => {
		if (volume === lastVolume) return;
		lastVolume = volume;
		volumeActive = true;
		if (volumeTimer) clearTimeout(volumeTimer);
		volumeTimer = setTimeout(() => (volumeActive = false), 1200);
	});

	const progress = $derived(duration > 0 ? Math.min(1, current / duration) : 0);
	const loaded = $derived(duration > 0 ? Math.min(1, buffered / duration) : 0);
	const volumePercent = $derived(Math.round(volume * 100));

	// Chargement du flux (HLS natif ou hls.js), relancé quand la vidéo change.
	$effect(() => {
		const element = video;
		const source = src;
		if (!element || !source) return;

		let destroy = () => {};
		let cancelled = false;
		paused = false;
		ended = false;
		waiting = true;
		current = 0;
		duration = 0;
		buffered = 0;
		poke();

		const start = () => {
			// Lecture avec le son ; si le webview la refuse sans geste de
			// l'utilisateur, on relance en muet plutôt que de rester figé.
			element.play().catch(() => {
				element.muted = true;
				element.play().catch(() => {});
			});
		};

		if (element.canPlayType('application/vnd.apple.mpegurl')) {
			element.src = source;
			start();
		} else {
			void import('hls.js').then(({ default: Hls }) => {
				if (cancelled || !Hls.isSupported()) return;
				const hls = new Hls({ capLevelToPlayerSize: true });
				hls.loadSource(source);
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

	// Volume ; à zéro, la lecture est muette.
	$effect(() => {
		if (!video) return;
		video.volume = volume;
		video.muted = volume <= 0;
	});

	$effect(() => () => {
		if (hudTimer) clearTimeout(hudTimer);
		if (scrubTimer) clearTimeout(scrubTimer);
		if (volumeTimer) clearTimeout(volumeTimer);
	});

	/** Montre les commandes, puis les efface si la lecture continue sans appui. */
	export function poke() {
		hudVisible = true;
		if (hudTimer) clearTimeout(hudTimer);
		hudTimer = setTimeout(() => {
			if (!paused && !ended && !waiting) hudVisible = false;
		}, HUD_DELAY);
	}

	function showFlash(icon?: string, text?: string) {
		flash = { key: ++flashKey, icon, text };
	}

	/** Touches propres au lecteur ; les autres (volume, voisins, B) sont à l'appelant. */
	export function handleAction(action: Action) {
		poke();
		if (!video) return;
		if (action === 'accept') {
			if (ended) {
				video.currentTime = 0;
				video.play().catch(() => {});
				showFlash('play');
			} else if (video.paused) {
				video.play().catch(() => {});
				showFlash('play');
			} else {
				video.pause();
				showFlash('pause');
			}
		} else if (action === 'left' || action === 'right') {
			// Le curseur de la barre se déplace directement ; maintenir la touche
			// le fait défiler (répétition de la manette).
			const step = action === 'left' ? -SEEK : SEEK;
			const end = Number.isFinite(video.duration) ? video.duration : Infinity;
			video.currentTime = Math.max(0, Math.min(end - 0.25, video.currentTime + step));
			current = video.currentTime;
			scrubbing = true;
			if (scrubTimer) clearTimeout(scrubTimer);
			scrubTimer = setTimeout(() => (scrubbing = false), 900);
		}
	}

	function onTime() {
		if (!video) return;
		current = video.currentTime;
		if (Number.isFinite(video.duration)) duration = video.duration;
		const ranges = video.buffered;
		buffered = ranges.length ? ranges.end(ranges.length - 1) : 0;
	}

	/** 83 → « 1:23 ». */
	function clock(seconds: number): string {
		const total = Math.max(0, Math.floor(seconds));
		return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`;
	}
</script>

<div class="player" class:idle={!hudVisible}>
	<!-- svelte-ignore a11y_media_has_caption -->
	<video
		bind:this={video}
		{poster}
		playsinline
		ontimeupdate={onTime}
		ondurationchange={onTime}
		onprogress={onTime}
		onplay={() => {
			paused = false;
			ended = false;
			poke();
		}}
		onpause={() => {
			paused = true;
			poke();
		}}
		onwaiting={() => (waiting = true)}
		onplaying={() => {
			waiting = false;
			poke();
		}}
		onended={() => {
			ended = true;
			poke();
		}}
	></video>

	{#if waiting && !paused && !ended}
		<div class="spinner" aria-label="Chargement"></div>
	{/if}

	{#if flash}
		{#key flash.key}
			<div class="flash">
				{#if flash.icon}
					<img src="/assets/icons/{flash.icon}.svg" alt="" />
				{:else}
					<span>{flash.text}</span>
				{/if}
			</div>
		{/key}
	{/if}

	<!-- Volume sur le côté, en jauge verticale : ▲ ▼ le règlent. -->
	<div class="side-volume" class:active={volumeActive}>
		<kbd>▲</kbd>
		<span class="column"><span class="level" style="height: {volumePercent}%"></span></span>
		<kbd>▼</kbd>
		<img src="/assets/icons/volume.svg" alt="" />
		<span class="side-value">{volumePercent} %</span>
	</div>

	<header class="top">
		<span class="title">{title}</span>
		{#if name}<span class="name">{name}</span>{/if}
		{#if position}<span class="position">{position}</span>{/if}
	</header>

	<footer class="bottom">
		<div class="timeline">
			<span class="time">{clock(current)}</span>
			<div class="timeline-bar" class:scrubbing>
				<span class="loaded" style="width: {loaded * 100}%"></span>
				<span class="played" style="width: {progress * 100}%"></span>
				<span class="knob" style="left: {progress * 100}%">
					<span class="bubble">{clock(current)}</span>
				</span>
			</div>
			<span class="time">{duration ? clock(duration) : '--:--'}</span>
		</div>

		<div class="controls">
			<span class="state">
				<img src="/assets/icons/{paused || ended ? 'play' : 'pause'}.svg" alt="" />
				{ended ? 'Terminé' : paused ? 'En pause' : waiting ? 'Chargement…' : 'Lecture'}
			</span>

			<div class="hints">
				<span class="hint">
					<Glyph button="a" size="30px" />
					{ended ? 'Revoir' : paused ? 'Lecture' : 'Pause'}
				</span>
				<span class="hint">
					<span class="keys"><kbd>◀</kbd><kbd>▶</kbd></span>
					Avancer / reculer
				</span>
				{#if hasNeighbours}
					<span class="hint">
						<span class="keys"><Glyph button="l1" size="30px" /><Glyph button="r1" size="30px" /></span>
						Média précédent / suivant
					</span>
				{/if}
				<span class="hint">
					<Glyph button="b" size="30px" />
					Fermer
				</span>
			</div>
		</div>
	</footer>
</div>

<style>
	.player {
		position: absolute;
		inset: 0;
		background: #000;
	}

	video {
		width: 100%;
		height: 100%;
		object-fit: contain;
	}

	/* Bandeaux du haut et du bas, sur des dégradés : lisibles sur n'importe
	   quelle image, sans masquer la vidéo. */
	.top,
	.bottom {
		position: absolute;
		left: 0;
		right: 0;
		padding: 0 var(--safe-x);
		transition:
			opacity var(--normal) var(--ease),
			transform var(--normal) var(--ease);
	}

	.top {
		top: 0;
		display: flex;
		align-items: baseline;
		gap: 18px;
		padding-top: var(--safe-y);
		padding-bottom: 60px;
		background: linear-gradient(180deg, var(--player-shade) 0%, transparent 100%);
		font-size: 20px;
	}

	.bottom {
		bottom: 0;
		display: flex;
		flex-direction: column;
		gap: 20px;
		padding-top: 90px;
		padding-bottom: calc(var(--safe-y) * 0.7);
		background: linear-gradient(0deg, var(--player-shade) 0%, transparent 100%);
	}

	/* Commandes effacées : la vidéo seule. */
	.idle .top {
		opacity: 0;
		transform: translateY(-12px);
	}

	.idle .bottom {
		opacity: 0;
		transform: translateY(12px);
	}

	.title {
		font-weight: 700;
	}

	.name {
		color: var(--text-dim);
	}

	.position {
		margin-left: auto;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	.timeline {
		display: flex;
		align-items: center;
		gap: 18px;
	}

	.time {
		min-width: 5ch;
		font-size: 18px;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}

	.time:last-child {
		text-align: right;
		color: var(--text-dim);
	}

	/* Pas de classe `.track` : c'est déjà la barre de téléchargement. */
	.timeline-bar {
		position: relative;
		flex: 1;
		height: var(--player-bar);
		border-radius: 999px;
		background: var(--surface-strong);
	}

	.loaded,
	.played {
		position: absolute;
		inset: 0 auto 0 0;
		border-radius: inherit;
	}

	.loaded {
		background: rgba(255, 255, 255, 0.18);
	}

	.played {
		background: var(--accent);
		box-shadow: 0 0 14px var(--accent-soft);
	}

	/* Le curseur est la sélection du lecteur : gauche / droite le déplacent. */
	.knob {
		position: absolute;
		top: 50%;
		width: var(--player-knob);
		height: var(--player-knob);
		border-radius: 50%;
		background: var(--text);
		box-shadow:
			0 0 0 4px var(--accent),
			0 0 18px 4px var(--accent-soft);
		transform: translate(-50%, -50%);
		transition:
			transform var(--fast) var(--ease),
			left 120ms linear;
	}

	.scrubbing .knob {
		transform: translate(-50%, -50%) scale(1.35);
	}

	/* Temps visé, au-dessus du curseur, pendant qu'on le déplace. */
	.bubble {
		position: absolute;
		bottom: calc(100% + 14px);
		left: 50%;
		padding: 6px 12px;
		border-radius: 999px;
		background: var(--dock-bg);
		font-size: 17px;
		font-weight: 700;
		white-space: nowrap;
		font-variant-numeric: tabular-nums;
		opacity: 0;
		transform: translateX(-50%) scale(calc(1 / 1.35));
		transition: opacity var(--fast) var(--ease);
	}

	.scrubbing .bubble {
		opacity: 1;
	}

	/* Jauge de volume verticale, sur le bord droit, centrée en hauteur. */
	.side-volume {
		position: absolute;
		top: 50%;
		right: var(--safe-x);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 10px;
		padding: 16px 12px;
		border-radius: 999px;
		background: var(--dock-bg);
		border: 1px solid var(--dock-border);
		backdrop-filter: blur(18px);
		transform: translateY(-50%);
		transition:
			opacity var(--normal) var(--ease),
			transform var(--normal) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	.side-volume.active {
		box-shadow: 0 0 30px 4px var(--accent-soft);
	}

	.column {
		position: relative;
		width: var(--volume-bar-height);
		height: var(--player-volume-height);
		border-radius: 999px;
		background: var(--surface-strong);
		overflow: hidden;
	}

	.level {
		position: absolute;
		inset: auto 0 0;
		border-radius: inherit;
		background: var(--accent);
		transition: height var(--fast) var(--ease);
	}

	.side-volume img {
		width: 22px;
		height: 22px;
		margin-top: 4px;
	}

	.side-value {
		font-size: 17px;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}

	/* Commandes effacées : la jauge s'efface avec elles, sauf si on règle le
	   volume à l'instant. */
	.idle .side-volume:not(.active) {
		opacity: 0;
		transform: translate(12px, -50%);
	}

	.controls {
		display: flex;
		align-items: center;
		gap: 30px;
	}

	.state {
		display: flex;
		align-items: center;
		gap: 12px;
		font-size: 20px;
		font-weight: 700;
	}

	.state img {
		width: 26px;
		height: 26px;
	}

	.hints {
		display: flex;
		flex-wrap: wrap;
		justify-content: flex-end;
		align-items: center;
		gap: 12px 28px;
		margin-left: auto;
		font-size: 18px;
		color: var(--text-dim);
	}

	.hint {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	.keys {
		display: flex;
		gap: 4px;
	}

	/* Flèches de la croix directionnelle, en touches de clavier stylisées. */
	kbd {
		display: grid;
		place-items: center;
		width: 30px;
		height: 30px;
		border-radius: 8px;
		background: var(--surface-strong);
		border: 1px solid rgba(255, 255, 255, 0.18);
		color: var(--text);
		font-family: inherit;
		font-size: 13px;
	}

	/* Icône d'action au centre : elle grossit et s'efface, comme sur YouTube. */
	.flash {
		position: absolute;
		top: 50%;
		left: 50%;
		display: grid;
		place-items: center;
		width: var(--player-flash);
		height: var(--player-flash);
		border-radius: 50%;
		background: rgba(0, 0, 0, 0.55);
		font-size: 24px;
		font-weight: 800;
		pointer-events: none;
		animation: flash 600ms var(--ease) forwards;
	}

	.flash img {
		width: 44px;
		height: 44px;
	}

	@keyframes flash {
		from {
			opacity: 1;
			transform: translate(-50%, -50%) scale(0.8);
		}
		to {
			opacity: 0;
			transform: translate(-50%, -50%) scale(1.25);
		}
	}

	.spinner {
		position: absolute;
		top: 50%;
		left: 50%;
		width: 56px;
		height: 56px;
		margin: -28px 0 0 -28px;
		border-radius: 50%;
		border: 5px solid rgba(255, 255, 255, 0.15);
		border-top-color: var(--accent);
		animation: spin 900ms linear infinite;
	}

	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}
</style>
