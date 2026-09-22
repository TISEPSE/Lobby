<script lang="ts">
	/**
	 * Écran de veille.
	 *
	 * Après un moment sans toucher à la manette, l'interface s'efface au profit
	 * des artworks de la bibliothèque, qui se relaient lentement. Le but est
	 * double : éviter de marquer une dalle OLED avec une barre d'aide fixe, et
	 * donner quelque chose d'agréable à regarder quand la console reste allumée.
	 *
	 * Comme pour le fond de l'accueil, deux couches se relaient : la nouvelle
	 * image ne s'affiche qu'une fois chargée, sinon on verrait un éclair noir.
	 */
	let { images }: { images: string[] } = $props();

	/** Durée d'un artwork à l'écran. Assez long pour ne pas clignoter. */
	const HOLD_MS = 12_000;

	let index = $state(0);
	let shown = $state(images[0] ?? '');
	let clock = $state(formatClock());

	function formatClock() {
		return new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
	}

	const today = new Date().toLocaleDateString('fr-FR', {
		weekday: 'long',
		day: 'numeric',
		month: 'long',
	});

	$effect(() => {
		const tick = setInterval(() => (clock = formatClock()), 20_000);
		return () => clearInterval(tick);
	});

	$effect(() => {
		if (images.length < 2) return;
		const next = setInterval(() => (index = (index + 1) % images.length), HOLD_MS);
		return () => clearInterval(next);
	});

	/** On précharge avant d'échanger : la bascule se fait sur une image prête. */
	$effect(() => {
		const src = images[index];
		if (!src || src === shown) return;
		const probe = new Image();
		probe.onload = () => (shown = src);
		probe.src = src;
	});
</script>

<div class="saver">
	{#key shown}
		<img class="art" src={shown} alt="" />
	{/key}
	<div class="veil"></div>
	<div class="clock">
		<span class="hour">{clock}</span>
		<span class="date">{today}</span>
	</div>
	<p class="hint">Appuyer sur une touche pour reprendre</p>
</div>

<style>
	.saver {
		position: fixed;
		inset: 0;
		z-index: 9;
		background: #000;
		overflow: hidden;
		animation: fade-in 700ms var(--ease) both;
	}

	/* Lent panoramique : l'image ne reste jamais immobile au même pixel. */
	.art {
		position: absolute;
		inset: -4%;
		width: 108%;
		height: 108%;
		object-fit: cover;
		animation:
			fade-in 1200ms var(--ease) both,
			drift 24s linear infinite alternate;
	}

	.veil {
		position: absolute;
		inset: 0;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.85), rgba(0, 0, 0, 0.2) 60%);
	}

	.clock {
		position: absolute;
		left: var(--safe-x);
		bottom: var(--safe-y);
		display: flex;
		flex-direction: column;
		gap: 4px;
		text-shadow: 0 4px 24px rgba(0, 0, 0, 0.9);
	}

	.hour {
		font-size: clamp(56px, 7vw, 120px);
		font-weight: 300;
		line-height: 1;
		letter-spacing: -0.03em;
	}

	.date {
		font-size: 22px;
		color: var(--text-dim);
		text-transform: capitalize;
	}

	.hint {
		position: absolute;
		right: var(--safe-x);
		bottom: var(--safe-y);
		margin: 0;
		font-size: 17px;
		color: var(--text-dim);
	}

	@keyframes fade-in {
		from {
			opacity: 0;
		}
	}

	@keyframes drift {
		from {
			transform: scale(1.04) translate3d(-1%, -1%, 0);
		}
		to {
			transform: scale(1.12) translate3d(1%, 1%, 0);
		}
	}
</style>
