<script lang="ts">
	import { padName } from './gamepad';
	import { play as playSound } from './sound';

	import { untrack } from 'svelte';

	/**
	 * Notification « manette connectée », façon Xbox : un rond d'accent portant
	 * la manette surgit en bas de l'écran, puis la pilule s'ouvre vers la droite
	 * pour dire laquelle et à quel joueur elle revient. Elle se referme seule.
	 *
	 * Une même manette s'annonce souvent **plusieurs fois d'un coup** (pilote
	 * XInput et HID, manettes virtuelles de Steam Input…) : tout ce qui arrive
	 * dans la même seconde ne donne qu'**une** notification, et une seule est
	 * à l'écran à la fois — une nouvelle remplace la précédente.
	 */
	type Toast = { key: number; connected: boolean; name: string; player: number };
	type PadEvent = { connected: boolean; name: string; player: number };

	/** Fenêtre de regroupement des annonces simultanées. */
	const BURST = 800;
	const STAY = 3600;

	let current = $state<Toast | null>(null);
	let seq = 0;
	let burst: PadEvent[] = [];
	let burstTimer: ReturnType<typeof setTimeout> | null = null;
	let hideTimer: ReturnType<typeof setTimeout> | null = null;

	function flush() {
		burstTimer = null;
		const events = burst;
		burst = [];
		if (events.length === 0) return;
		// Les branchements l'emportent : une manette virtuelle qui disparaît
		// pendant qu'une vraie arrive ne doit pas annoncer « déconnectée ».
		const connected = events.some((e) => e.connected);
		const kept = events.filter((e) => e.connected === connected);
		// Une seule manette physique vue sous plusieurs noms : on garde le plus
		// parlant (une marque reconnue plutôt qu'un nom générique), puis le
		// premier joueur.
		const known = kept.filter((e) => e.name.startsWith('Manette '));
		const pool = known.length > 0 ? known : kept;
		const first = pool.reduce((a, b) => (b.player < a.player ? b : a));
		current = { key: ++seq, connected, name: first.name, player: first.player };
		playSound('pad');
		if (hideTimer) clearTimeout(hideTimer);
		hideTimer = setTimeout(() => (current = null), STAY);
	}

	function push(pad: Gamepad, connected: boolean) {
		burst.push({ connected, name: padName(pad.id), player: pad.index + 1 });
		if (!burstTimer) burstTimer = setTimeout(flush, BURST);
	}

	$effect(() => {
		const onConnect = (event: GamepadEvent) => push(event.gamepad, true);
		const onDisconnect = (event: GamepadEvent) => push(event.gamepad, false);
		window.addEventListener('gamepadconnected', onConnect);
		window.addEventListener('gamepaddisconnected', onDisconnect);

		// Capture : ?pad=xbox|ps5 simule un branchement (?pad=triple : trois
		// annonces d'un coup, qui ne doivent donner qu'une notification).
		const demo = new URLSearchParams(location.search).get('pad');
		if (demo) {
			const id = demo === 'ps5' ? 'DualSense Wireless Controller (Vendor: 054c Product: 0ce6)' : 'Xbox Controller (XInput)';
			untrack(() => {
				const times = demo === 'triple' ? 3 : 1;
				for (let index = 0; index < times; index++) push({ id, index } as Gamepad, true);
			});
		}

		return () => {
			window.removeEventListener('gamepadconnected', onConnect);
			window.removeEventListener('gamepaddisconnected', onDisconnect);
			if (burstTimer) clearTimeout(burstTimer);
			if (hideTimer) clearTimeout(hideTimer);
		};
	});
</script>

{#if current}
	{#key current.key}
		<div class="toast" class:off={!current.connected} role="status">
			<span class="badge">
				<img src="/assets/icons/controller.svg" alt="" />
			</span>
			<span class="body">
				<span class="title">Manette {current.connected ? 'connectée' : 'déconnectée'}</span>
				<span class="sub">
					{current.name}{#if current.connected}<span class="dot">·</span>Joueur {current.player}{/if}
				</span>
			</span>
		</div>
	{/key}
{/if}

<style>
	/* En bas, au centre, à hauteur de la barre d'aide — là où une Xbox pose
	   ses notifications, sans cacher les jaquettes. */
	.toast {
		position: fixed;
		z-index: 6;
		left: 50%;
		bottom: var(--toast-bottom);
		display: flex;
		align-items: center;
		height: var(--toast-height);
		max-width: var(--toast-width);
		padding: var(--toast-pad);
		border-radius: 999px;
		background: var(--toast-bg);
		border: 1px solid var(--dock-border);
		backdrop-filter: blur(18px) saturate(1.2);
		box-shadow: 0 16px 40px rgba(0, 0, 0, 0.45);
		overflow: hidden;
		transform: translateX(-50%);
		/* Le rond surgit, puis la pilule s'ouvre et le texte apparaît. */
		animation:
			toast-pop var(--normal) var(--ease) both,
			toast-open var(--toast-open) var(--ease) var(--normal) both,
			toast-close var(--normal) var(--ease) var(--toast-stay) forwards;
	}

	@keyframes toast-pop {
		from {
			opacity: 0;
			transform: translateX(-50%) translateY(24px) scale(0.6);
		}
	}

	/* `max-width` de la seule pastille à la pilule entière. */
	@keyframes toast-open {
		from {
			max-width: var(--toast-height);
		}
	}

	@keyframes toast-close {
		to {
			opacity: 0;
			transform: translateX(-50%) translateY(16px) scale(0.92);
		}
	}

	.badge {
		display: grid;
		flex: none;
		place-items: center;
		width: calc(var(--toast-height) - 2 * var(--toast-inset));
		height: calc(var(--toast-height) - 2 * var(--toast-inset));
		margin-left: calc(var(--toast-inset) - 1px);
		border-radius: 50%;
		background: var(--accent);
		box-shadow: 0 0 24px var(--accent-soft);
	}

	.badge img {
		width: 34px;
		height: 34px;
		/* Icône blanche passée en sombre sur l'aplat d'accent. */
		filter: brightness(0.12);
	}

	/* Débranchée : le rond s'éteint, ce n'est pas une bonne nouvelle. */
	.off .badge {
		background: var(--surface-strong);
		box-shadow: none;
	}

	.off .badge img {
		filter: none;
		opacity: 0.8;
	}

	.body {
		display: flex;
		flex-direction: column;
		gap: 2px;
		padding: 0 30px 0 18px;
		white-space: nowrap;
		animation: toast-text var(--normal) var(--ease) var(--toast-open) both;
	}

	@keyframes toast-text {
		from {
			opacity: 0;
			transform: translateX(-10px);
		}
	}

	.title {
		font-size: 20px;
		font-weight: 700;
	}

	.sub {
		font-size: 17px;
		color: var(--text-dim);
	}

	.dot {
		margin: 0 8px;
	}
</style>
