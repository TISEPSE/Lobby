<script lang="ts">
	import { onMount } from 'svelte';
	import { fade, scale } from 'svelte/transition';
	import { cubicIn, cubicOut } from 'svelte/easing';
	import { play as playSound } from './sound';

	/**
	 * Animation de démarrage (maquette Claude Design de l'utilisateur), rejouée
	 * en direct pour être **personnelle** : pseudo, photo, vrai nombre de jeux,
	 * et une jauge qui suit le vrai chargement.
	 *
	 * 1. Quatre traits de couleur convergent des coins vers le centre.
	 * 2. Éclat : une onde verte, et les quatre pastilles de la manette (Y jaune,
	 *    B rouge, A vert, X bleu) éclosent en losange.
	 * 3. Le nom, LOBBY, sous-titré CONSOLE.
	 * 4. Chargement : les pastilles tournent dans une couronne de graduations
	 *    qui s'allument au rythme du vrai chargement, « 24 / 35 jeux » et
	 *    l'étape en cours. Cette phase dure au moins `MIN_LOADING`, et tant
	 *    qu'il le faut.
	 * 5. « Bonjour, <pseudo> » sous la photo de profil, cerclée d'accent.
	 * 6. Sortie : le fond s'efface sur l'accueil déjà prêt derrière, et la photo
	 *    file vers sa place dans le dock.
	 *
	 * N'importe quelle touche passe l'animation (l'appelant appelle `skip`).
	 */
	let {
		name,
		avatar = '',
		/** Jeux de la bibliothèque (installés et possédés) : il grandit en direct. */
		total,
		/** Jeux prêts (images décodées, comptes arrivés). */
		ready,
		/** Étape réelle du chargement, affichée sous le compteur. */
		step,
		/** Avancement réel du chargement, de 0 à 1. */
		progress,
		onDone,
		onPhase,
		onReveal,
	}: {
		name: string;
		avatar?: string;
		total: number;
		ready: number;
		step: string;
		progress: number;
		onDone: () => void;
		/** Chaque changement de phase (trace de diagnostic). */
		onPhase?: (phase: string) => void;
		/** La sortie commence : l'interface derrière peut se montrer. */
		onReveal?: () => void;
	} = $props();

	/** Repères de la séquence, en millisecondes depuis le début. */
	const CONVERGE = 1300;
	const BRAND = 2200;
	const LOADING = 3400;
	/** Durée minimale de la jauge, même si tout est déjà chargé. */
	const MIN_LOADING = 2200;
	const GREET_HOLD = 1700;
	const EXIT = 900;
	/** Sortie quand on passe l'animation : courte, sans vol de la photo. */
	const SKIP_EXIT = 350;
	/** Graduations de la couronne. */
	const TICKS = 60;

	type Phase = 'converge' | 'burst' | 'brand' | 'loading' | 'greet' | 'exit';
	let phase = $state<Phase>('converge');
	$effect(() => onPhase?.(phase));
	let skipped = $state(false);

	/** Avancement affiché : il rattrape le vrai en douceur, jamais à reculons. */
	let shown = $state(0);
	let loadingSince = 0;
	const lit = $derived(Math.round(shown * TICKS));
	/** Le compteur ne dépasse jamais ce que la jauge montre : ils avancent ensemble. */
	const counter = $derived(Math.min(ready, Math.round(shown * total)));
	const greeting = (() => {
		const hour = new Date().getHours();
		return hour >= 5 && hour < 18 ? 'Bonjour' : 'Bonsoir';
	})();

	let avatarEl = $state<HTMLElement | null>(null);
	/** Déplacement de la photo vers le dock, calculé au moment de la sortie. */
	let flight = $state('');

	const timers: ReturnType<typeof setTimeout>[] = [];
	const at = (ms: number, fn: () => void) => timers.push(setTimeout(fn, ms));
	let frame = 0;

	onMount(() => {
		at(CONVERGE, () => {
			phase = 'burst';
			playSound('boot');
		});
		at(BRAND, () => (phase = 'brand'));
		at(LOADING, () => {
			phase = 'loading';
			loadingSince = performance.now();
		});

		// La jauge suit le vrai chargement, lissée image par image — mais
		// jamais plus vite que `MIN_LOADING` pour un tour complet : bibliothèque
		// en cache, le compteur sautait d'un coup à « 35 / 35 ».
		let last = performance.now();
		const tick = () => {
			const now = performance.now();
			const dt = now - last;
			last = now;
			if (phase === 'loading') {
				const step = Math.min(Math.max(0, progress - shown), dt / MIN_LOADING);
				shown = Math.min(1, shown + step);
				if (phase === 'loading' && shown >= 0.999 && performance.now() - loadingSince >= MIN_LOADING) {
					shown = 1;
					greet();
					return;
				}
			}
			frame = requestAnimationFrame(tick);
		};
		frame = requestAnimationFrame(tick);

		return () => {
			timers.forEach(clearTimeout);
			cancelAnimationFrame(frame);
		};
	});

	function greet() {
		phase = 'greet';
		at(GREET_HOLD, exit);
	}

	function exit() {
		if (phase === 'exit') return;
		// L'accueil n'apparaît qu'ici, quand le fond commence à s'effacer :
		// avant, il est masqué (il se montrait entre le début et le chargement).
		onReveal?.();
		// La photo file vers celle du dock (même place, même taille).
		const target = document.querySelector('.top .profile .avatar');
		if (avatarEl && target && !skipped) {
			const from = avatarEl.getBoundingClientRect();
			const to = target.getBoundingClientRect();
			const dx = to.left + to.width / 2 - (from.left + from.width / 2);
			const dy = to.top + to.height / 2 - (from.top + from.height / 2);
			flight = `translate(${dx}px, ${dy}px) scale(${to.width / from.width})`;
		}
		phase = 'exit';
		at(skipped ? SKIP_EXIT : EXIT, onDone);
	}

	/** On ne passe pas l'animation pendant ses premiers instants. */
	const SKIP_GRACE = 1500;
	const startedAt = performance.now();

	/** Une touche : on passe directement à l'accueil. */
	export function skip() {
		if (phase === 'exit') return;
		// Un appui parasite au lancement (manette qui se réveille) ne doit pas
		// passer l'animation avant même qu'on l'ait vue.
		if (performance.now() - startedAt < SKIP_GRACE) return;
		skipped = true;
		timers.forEach(clearTimeout);
		cancelAnimationFrame(frame);
		exit();
	}
</script>

<div class="intro {phase}" data-intro class:skipped style="--exit: {skipped ? SKIP_EXIT : EXIT}ms">
	<div class="glow"></div>

	<!-- 1. Les quatre traits qui convergent. -->
	{#if phase === 'converge'}
		<div class="streaks" out:fade={{ duration: 120 }}>
			<span class="streak yellow" style="--angle: -150deg"></span>
			<span class="streak red" style="--angle: -30deg"></span>
			<span class="streak blue" style="--angle: 150deg"></span>
			<span class="streak green" style="--angle: 30deg"></span>
		</div>
	{/if}

	<!-- Le point où les traits se rejoignent : il reste allumé pendant l'éclat
	     et les pastilles en sortent, sans un instant de noir entre les deux. -->
	{#if phase === 'converge' || phase === 'burst'}
		<span class="core" out:fade={{ duration: 200 }}></span>
	{/if}

	<!-- 2. L'onde de l'éclat. -->
	{#if phase === 'burst' || phase === 'brand'}
		<span class="shockwave"></span>
	{/if}

	<div class="center">
		{#if phase !== 'converge' && phase !== 'greet' && phase !== 'exit'}
			<div class="mark" out:scale={{ start: 0.4, duration: 280, easing: cubicIn }}>
				{#if phase === 'loading'}
					<!-- 4. La couronne de graduations, allumées au fil du chargement. -->
					<div class="ring">
						{#each Array(TICKS) as _, i}
							<span class="tick" class:on={i < lit} style="--i: {i}"></span>
						{/each}
						<span class="orbit"></span>
					</div>
				{/if}
				<div class="dots">
					<span class="dot yellow"></span>
					<span class="dot red"></span>
					<span class="dot green"></span>
					<span class="dot blue"></span>
				</div>
			</div>
		{/if}

		{#if phase === 'brand' || phase === 'loading'}
			<!-- 3. Le nom. -->
			<div class="brand" out:fade={{ duration: 220 }}>
				<span class="word">LOBBY</span>
				<span class="sub">CONSOLE</span>
			</div>
		{/if}

		{#if phase === 'loading'}
			<div class="status" out:fade={{ duration: 180 }}>
				<span class="count"><b>{counter}</b> / {total} jeux</span>
				<span class="step">{step}</span>
			</div>
		{/if}

		{#if phase === 'greet' || phase === 'exit'}
			<!-- 5. L'accueil personnel. -->
			<div class="greet" in:scale={{ start: 0.6, duration: 320, easing: cubicOut }}>
				<span class="avatar" bind:this={avatarEl} style:transform={phase === 'exit' ? flight : ''}>
					{#if avatar}
						<img src={avatar} alt="" />
					{:else}
						{name.charAt(0).toUpperCase()}
					{/if}
					<svg viewBox="0 0 100 100" aria-hidden="true"><circle cx="50" cy="50" r="48" /></svg>
				</span>
				<span class="hello">{greeting}, {name}</span>
			</div>
		{/if}
	</div>
</div>

<style>
	/* Par-dessus tout, dock compris : l'accueil se construit derrière. */
	.intro {
		position: fixed;
		inset: 0;
		z-index: 20;
		display: grid;
		place-items: center;
		overflow: hidden;
		background: var(--intro-bg);
		transition: background var(--exit) var(--ease);
	}

	/* 6. Sortie : le fond s'efface sur l'accueil. */
	.intro.exit {
		background: transparent;
		pointer-events: none;
	}

	.glow {
		position: absolute;
		inset: 0;
		background: radial-gradient(circle at 50% 50%, var(--intro-glow) 0%, transparent 38%);
		opacity: 0;
		transition: opacity 900ms var(--ease);
	}

	.intro:not(.converge):not(.exit) .glow {
		opacity: 1;
	}

	/* --- 1. Traits ----------------------------------------------------------- */
	.streaks {
		position: absolute;
		inset: 0;
		display: grid;
		place-items: center;
	}

	/* Chaque trait part du coin et file vers le centre en raccourcissant. */
	.streak {
		position: absolute;
		top: 50%;
		left: 50%;
		width: 26vmax;
		height: 2px;
		margin-top: -1px;
		border-radius: 2px;
		transform-origin: 0 50%;
		/* La tête, blanche, est du côté du centre : c'est elle qui avance. */
		background: linear-gradient(90deg, #fff, var(--c) 25%, transparent);
		box-shadow: 0 0 12px var(--c);
		animation: streak 1250ms cubic-bezier(0.55, 0, 0.85, 0.35) both;
	}

	@keyframes streak {
		from {
			transform: rotate(var(--angle)) translateX(60vmax) scaleX(1);
			opacity: 0;
		}
		4% {
			opacity: 1;
		}
		to {
			transform: rotate(var(--angle)) translateX(0) scaleX(0.05);
			opacity: 1;
		}
	}

	.core {
		position: absolute;
		top: 50%;
		left: 50%;
		width: 18px;
		height: 18px;
		margin: -9px 0 0 -9px;
		border-radius: 50%;
		background: #9a9a9a;
		box-shadow: 0 0 22px rgba(255, 255, 255, 0.35);
		animation: core 1300ms var(--ease) both;
	}

	@keyframes core {
		0%,
		55% {
			transform: scale(0);
		}
		to {
			transform: scale(1.2);
			background: #fff;
		}
	}

	/* À l'éclat, le point s'illumine puis se résorbe dans les pastilles. */
	.burst .core {
		animation: core-flash 700ms var(--ease) forwards;
	}

	@keyframes core-flash {
		from {
			transform: scale(1.2);
			background: #fff;
			box-shadow: 0 0 40px 10px rgba(255, 255, 255, 0.6);
		}
		35% {
			transform: scale(1.8);
		}
		to {
			transform: scale(0.2);
			opacity: 0;
		}
	}

	/* --- 2. Éclat ------------------------------------------------------------ */
	.shockwave {
		position: absolute;
		top: 50%;
		left: 50%;
		width: 240px;
		height: 240px;
		margin: -120px 0 0 -120px;
		border-radius: 50%;
		border: 1.5px solid var(--accent);
		animation: shock 1100ms cubic-bezier(0.2, 0.7, 0.3, 1) both;
	}

	@keyframes shock {
		from {
			transform: scale(0.05);
			opacity: 1;
		}
		to {
			transform: scale(4.5);
			opacity: 0;
		}
	}

	/* Le logo reste pile au centre de l'écran d'un bout à l'autre ; le nom,
	   le compteur et le « Bonjour » se posent dessous sans le déplacer (en
	   flux, l'apparition du nom faisait remonter les pastilles). */
	.center {
		position: relative;
		display: grid;
		place-items: center;
		width: var(--intro-ring);
		height: var(--intro-ring);
	}

	.brand,
	.status,
	.hello {
		position: absolute;
		left: 50%;
		white-space: nowrap;
	}

	.mark {
		position: relative;
		display: grid;
		place-items: center;
		width: var(--intro-ring);
		height: var(--intro-ring);
	}

	/* Les pastilles : Y jaune en haut, B rouge à droite, A vert en bas, X bleu
	   à gauche — comme sur une manette. */
	.dots {
		position: relative;
		width: var(--intro-dots);
		height: var(--intro-dots);
		transition: transform 700ms var(--ease);
	}

	.dot {
		position: absolute;
		top: 50%;
		left: 50%;
		width: var(--intro-dot);
		height: var(--intro-dot);
		margin: calc(var(--intro-dot) / -2) 0 0 calc(var(--intro-dot) / -2);
		border-radius: 50%;
		background: var(--c);
		box-shadow: 0 0 18px var(--c);
		animation: bloom 650ms cubic-bezier(0.3, 1.6, 0.5, 1) both;
	}

	.dot.yellow { --x: 0; --y: -1; animation-delay: 0ms; }
	.dot.red { --x: 1; --y: 0; animation-delay: 70ms; }
	.dot.green { --x: 0; --y: 1; animation-delay: 140ms; }
	.dot.blue { --x: -1; --y: 0; animation-delay: 210ms; }

	/* Le losange s'ouvre depuis le centre. */
	@keyframes bloom {
		from {
			transform: translate(0, 0) scale(0);
		}
		to {
			transform: translate(calc(var(--x) * var(--intro-spread)), calc(var(--y) * var(--intro-spread))) scale(1);
		}
	}

	.yellow { --c: var(--pad-yellow); }
	.red { --c: var(--pad-red); }
	.green { --c: var(--pad-green); }
	.blue { --c: var(--pad-blue); }

	/* Pendant le chargement, le losange se resserre et tourne. */
	.loading .dots {
		transform: scale(0.62);
		animation: spin-dots 2400ms linear infinite;
	}

	@keyframes spin-dots {
		to {
			transform: scale(0.62) rotate(360deg);
		}
	}

	/* --- 3. Nom --------------------------------------------------------------- */
	.brand {
		top: calc(100% + 24px);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		transform: translateX(-50%);
	}

	.word {
		font-size: var(--intro-word);
		font-weight: 800;
		line-height: 1;
		letter-spacing: 0.35em;
		margin-right: -0.35em;
		animation: word 900ms var(--ease) both;
	}

	@keyframes word {
		from {
			opacity: 0;
			letter-spacing: 0.7em;
			margin-right: -0.7em;
			filter: blur(6px);
		}
	}

	.sub {
		font-size: 17px;
		letter-spacing: 0.55em;
		margin-right: -0.55em;
		color: var(--text-dim);
		animation: fade-up 700ms var(--ease) 300ms both;
	}

	@keyframes fade-up {
		from {
			opacity: 0;
			transform: translateY(8px);
		}
	}

	/* --- 4. Chargement ---------------------------------------------------------- */
	.ring {
		position: absolute;
		inset: 0;
		animation: fade-in 500ms var(--ease) both;
	}

	@keyframes fade-in {
		from {
			opacity: 0;
			transform: scale(0.9);
		}
	}

	.tick {
		position: absolute;
		top: 0;
		left: 50%;
		width: 3px;
		height: 14px;
		margin-left: -1.5px;
		border-radius: 2px;
		background: rgba(255, 255, 255, 0.14);
		transform-origin: 50% calc(var(--intro-ring) / 2);
		transform: rotate(calc(var(--i) * 6deg));
		transition:
			background 250ms var(--ease),
			box-shadow 250ms var(--ease),
			height 250ms var(--ease);
	}

	.tick.on {
		height: 18px;
		background: var(--accent);
		box-shadow: 0 0 10px var(--accent-soft);
	}

	/* Un point blanc fait le tour de la couronne : ça travaille. */
	.orbit {
		position: absolute;
		inset: -10px;
		border-radius: 50%;
		animation: orbit 1600ms linear infinite;
	}

	.orbit::before {
		content: '';
		position: absolute;
		top: 0;
		left: 50%;
		width: 6px;
		height: 6px;
		margin-left: -3px;
		border-radius: 50%;
		background: #fff;
		box-shadow: 0 0 10px #fff;
	}

	@keyframes orbit {
		to {
			transform: rotate(360deg);
		}
	}

	.status {
		top: calc(100% + 24px + var(--intro-word) + 60px);
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		transform: translateX(-50%);
		animation: fade-up-centered 500ms var(--ease) both;
	}

	@keyframes fade-up-centered {
		from {
			opacity: 0;
			transform: translate(-50%, 8px);
		}
	}

	.count {
		font-size: 22px;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	.count b {
		color: var(--text);
	}

	.step {
		font-size: 17px;
		color: var(--text-dim);
	}

	/* --- 5. Accueil personnel ----------------------------------------------------- */
	.greet {
		position: absolute;
		inset: 0;
		display: grid;
		place-items: center;
	}

	.avatar {
		position: relative;
		display: grid;
		place-items: center;
		width: var(--intro-avatar);
		height: var(--intro-avatar);
		border-radius: 50%;
		background: var(--intro-avatar-bg);
		font-size: calc(var(--intro-avatar) * 0.42);
		font-weight: 800;
		transition: transform var(--exit) cubic-bezier(0.6, 0, 0.3, 1);
	}

	.avatar img {
		width: 100%;
		height: 100%;
		border-radius: 50%;
		object-fit: cover;
	}

	@keyframes pop {
		from {
			transform: scale(0.4);
			opacity: 0;
		}
	}

	/* L'anneau d'accent se trace autour de la photo. */
	.avatar svg {
		position: absolute;
		inset: -7px;
		width: calc(100% + 14px);
		height: calc(100% + 14px);
		transform: rotate(-90deg);
	}

	.avatar circle {
		fill: none;
		stroke: var(--accent);
		stroke-width: 3;
		stroke-dasharray: 302;
		stroke-dashoffset: 302;
		animation: trace 800ms var(--ease) 250ms forwards;
	}

	@keyframes trace {
		to {
			stroke-dashoffset: 0;
		}
	}

	.hello {
		top: calc(50% + var(--intro-avatar) / 2 + 30px);
		font-size: var(--intro-hello);
		font-weight: 800;
		animation: fade-up-centered 600ms var(--ease) 450ms both;
		transform: translateX(-50%);
	}

	/* --- 6. Sortie ------------------------------------------------------------- */
	.exit .hello {
		opacity: 0;
		transition: opacity 300ms var(--ease);
	}

	/* Passée d'une touche : tout s'efface d'un coup, sans vol. */
	.exit.skipped .center {
		opacity: 0;
		transition: opacity var(--exit) var(--ease);
	}

	.exit:not(.skipped) .avatar svg {
		opacity: 0;
		transition: opacity 400ms var(--ease);
	}
</style>
