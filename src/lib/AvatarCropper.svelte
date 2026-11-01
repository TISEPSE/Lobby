<script lang="ts">
	import { onMount } from 'svelte';
	import Glyph from './Glyph.svelte';
	import type { Action } from './gamepad';
	import { imageUrl, releaseImage, saveAvatarImage } from './images';

	/**
	 * Recadrage d'une photo importée. L'image glisse derrière un disque fixe : ce
	 * qui est dans le disque est ce qui sera gardé, et elle le couvre toujours,
	 * à tous les zooms et dans toutes les positions. Tout se fait à la manette :
	 * croix ou stick pour déplacer, LT / RT pour zoomer, A valide, B revient à
	 * l'explorateur.
	 */
	let {
		path,
		onDone,
		onCancel,
	}: {
		/** Chemin de l'image choisie sur le PC. */
		path: string;
		/** L'adresse de la photo enregistrée. */
		onDone?: (src: string) => void;
		onCancel?: () => void;
	} = $props();

	/** Côté de l'image enregistrée, en pixels. */
	const OUTPUT = 512;
	/** Déplacement par appui ; maintenue, la direction se répète. */
	const STEP = 28;
	const ZOOM_STEP = 1.2;
	const MAX_ZOOM = 6;

	let src = $state('');
	let error = $state('');
	let saving = $state(false);
	let photo = $state<HTMLImageElement | null>(null);
	/** Taille réelle de l'image, connue une fois chargée. */
	let width = $state(0);
	let height = $state(0);
	/** Diamètres du disque de recadrage et de l'aperçu, lus sur le rendu. */
	let disc = $state(0);
	let preview = $state(0);
	let zoom = $state(1);
	/** Décalage de l'image par rapport au centre du disque. */
	let x = $state(0);
	let y = $state(0);

	const ready = $derived(width > 0 && disc > 0);
	/** Échelle à laquelle l'image couvre tout juste le disque. */
	const fit = $derived(ready ? disc / Math.min(width, height) : 1);
	const scale = $derived(fit * zoom);

	/** L'image doit toujours couvrir le disque : jamais de vide dans la photo. */
	function clamp(nextX: number, nextY: number, nextScale = scale) {
		const maxX = Math.max(0, (width * nextScale - disc) / 2);
		const maxY = Math.max(0, (height * nextScale - disc) / 2);
		x = Math.max(-maxX, Math.min(maxX, nextX));
		y = Math.max(-maxY, Math.min(maxY, nextY));
	}

	function setZoom(next: number) {
		zoom = Math.max(1, Math.min(MAX_ZOOM, next));
		clamp(x, y, fit * zoom);
	}

	/** Transformation de l'image dans un disque de diamètre `size`. */
	function placement(size: number): string {
		const ratio = disc ? size / disc : 1;
		return `transform: translate(-50%, -50%) translate(${x * ratio}px, ${y * ratio}px) scale(${scale * ratio})`;
	}

	async function confirm() {
		if (!photo || !ready || saving) return;
		saving = true;
		error = '';
		try {
			const canvas = document.createElement('canvas');
			canvas.width = OUTPUT;
			canvas.height = OUTPUT;
			const context = canvas.getContext('2d');
			if (!context) throw new Error('Photo impossible à préparer.');
			context.imageSmoothingQuality = 'high';
			const side = disc / scale;
			const left = width / 2 - x / scale - side / 2;
			const top = height / 2 - y / scale - side / 2;
			context.drawImage(photo, left, top, side, side, 0, 0, OUTPUT, OUTPUT);
			onDone?.(await saveAvatarImage(canvas));
		} catch (e) {
			error = String(e);
			saving = false;
		}
	}

	onMount(() => {
		let cancelled = false;
		imageUrl(path)
			.then((url) => {
				if (cancelled) releaseImage(url);
				else src = url;
			})
			.catch((e) => (error = String(e)));
		return () => {
			cancelled = true;
			releaseImage(src);
		};
	});

	export function handleAction(action: Action) {
		if (action === 'cancel') return onCancel?.();
		if (!ready || saving) return;
		if (action === 'left') clamp(x + STEP, y);
		else if (action === 'right') clamp(x - STEP, y);
		else if (action === 'up') clamp(x, y + STEP);
		else if (action === 'down') clamp(x, y - STEP);
		else if (action === 'pageNext') setZoom(zoom * ZOOM_STEP);
		else if (action === 'pagePrev') setZoom(zoom / ZOOM_STEP);
		else if (action === 'accept') void confirm();
	}
</script>

<div class="overlay" role="dialog" aria-modal="true" aria-label="Recadrer la photo">
	<div class="dialog">
		<header>
			<h2>Recadre ta photo</h2>
			<p>Ce qui est dans le cercle sera ta photo de profil.</p>
		</header>

		<div class="body">
			<div class="stage">
				{#if src}
					<img
						class="photo"
						bind:this={photo}
						{src}
						alt=""
						style={placement(disc)}
						onload={(event) => {
							const image = event.currentTarget;
							width = image.naturalWidth;
							height = image.naturalHeight;
						}}
						onerror={() => (error = 'Cette image ne peut pas être ouverte.')}
					/>
				{/if}
				<span class="disc" bind:clientWidth={disc}></span>
			</div>

			<aside>
				<span class="round" bind:clientWidth={preview}>
					{#if src}<img class="photo" {src} alt="" style={placement(preview)} />{/if}
				</span>
				<span class="caption">Aperçu</span>
			</aside>
		</div>

		{#if error}
			<p class="error">{error}</p>
		{/if}

		<footer>
			<span class="hint"><Glyph button="dpad" size="var(--crop-glyph)" />Déplacer</span>
			<span class="hint">
				<Glyph button="l2" size="var(--crop-glyph)" /><Glyph button="r2" size="var(--crop-glyph)" />Zoom
			</span>
			<span class="hint"><Glyph button="a" size="var(--crop-glyph)" />{saving ? 'Enregistrement…' : 'Valider'}</span>
			<span class="hint"><Glyph button="b" size="var(--crop-glyph)" />Retour</span>
		</footer>
	</div>
</div>

<style>
	.overlay {
		position: fixed;
		inset: 0;
		z-index: 10;
		display: grid;
		place-items: center;
		background: var(--files-veil);
		backdrop-filter: blur(var(--files-blur));
		animation: appear var(--fast) var(--ease) both;
	}

	@keyframes appear {
		from {
			opacity: 0;
		}
	}

	.dialog {
		display: flex;
		flex-direction: column;
		gap: 22px;
		padding: 30px 34px;
		border: 1px solid var(--xbox-line);
		border-radius: var(--radius-lg);
		background: var(--files-panel);
		box-shadow: 0 30px 80px rgba(0, 0, 0, 0.7);
	}

	h2 {
		margin: 0;
		font-size: 30px;
		font-weight: 700;
	}

	header p {
		margin: 4px 0 0;
		font-size: 18px;
		color: var(--text-dim);
	}

	.body {
		display: flex;
		align-items: center;
		gap: 34px;
	}

	.stage {
		position: relative;
		width: var(--crop-stage);
		height: var(--crop-stage-height);
		overflow: hidden;
		border-radius: var(--settings-radius);
		background: #000;
	}

	/* Taille réelle, mise à l'échelle par `transform` : pas de bornes héritées. */
	.photo {
		position: absolute;
		top: 50%;
		left: 50%;
		max-width: none;
		transform-origin: center;
		transition: transform var(--fast) var(--ease);
	}

	/* L'ombre assombrit tout ce qui sera coupé, le disque reste net. */
	.disc {
		position: absolute;
		top: 50%;
		left: 50%;
		width: var(--crop-disc);
		height: var(--crop-disc);
		border-radius: 50%;
		outline: 3px solid var(--accent);
		box-shadow: 0 0 0 100vmax var(--crop-shade);
		transform: translate(-50%, -50%);
		pointer-events: none;
	}

	aside {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 12px;
	}

	.round {
		position: relative;
		display: block;
		width: var(--crop-preview);
		height: var(--crop-preview);
		overflow: hidden;
		border-radius: 50%;
		background: #000;
		box-shadow: 0 0 0 2px var(--accent);
	}

	.caption {
		font-size: 17px;
		color: var(--text-dim);
	}

	.error {
		margin: 0;
		font-size: 18px;
		color: var(--danger);
	}

	footer {
		display: flex;
		justify-content: flex-end;
		gap: 28px;
		font-size: 18px;
		color: var(--text-dim);
	}

	.hint {
		display: flex;
		align-items: center;
		gap: 8px;
	}
</style>
