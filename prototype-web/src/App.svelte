<script lang="ts">
	import { onMount } from 'svelte';
	import Backdrop from './lib/Backdrop.svelte';
	import Home from './lib/Home.svelte';
	import Detail from './lib/Detail.svelte';
	import { listen, hasGamepad, type Action } from './lib/gamepad';
	import games from './lib/data/games.json';
	import type { Game } from './lib/types';
	import { play } from './lib/launcher';

	const library = games as Game[];

	/* Outil de développement, comme le `--capture` de la version Godot :
	   `?screen=detail&index=3` ouvre directement un écran pour la capture. */
	const params = new URLSearchParams(location.search);

	let index = $state(Number(params.get('index') ?? 0));
	let screen = $state<'home' | 'detail'>(params.get('screen') === 'detail' ? 'detail' : 'home');
	let clock = $state(formatClock());
	let pad = $state(false);
	let notice = $state('');

	const selected = $derived(library[index]);

	function formatClock() {
		return new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
	}

	/**
	 * Changement d'écran animé par le navigateur : la jaquette de la tuile et
	 * celle de la fiche portent le même `view-transition-name`, le reste est
	 * automatique. C'est l'équivalent de la « jaquette fantôme » de la version
	 * Godot, en une ligne.
	 */
	function go(next: 'home' | 'detail') {
		if (!document.startViewTransition) {
			screen = next;
			return;
		}
		document.startViewTransition(() => {
			screen = next;
		});
	}

	function handle(action: Action) {
		if (screen === 'home') {
			if (action === 'left') index = Math.max(0, index - 1);
			else if (action === 'right') index = Math.min(library.length - 1, index + 1);
			else if (action === 'accept') go('detail');
			return;
		}
		if (action === 'cancel') go('home');
		else if (action === 'accept' && selected) launch();
	}

	async function launch() {
		if (!selected) return;
		notice = await play(selected);
		setTimeout(() => (notice = ''), 4000);
	}

	onMount(() => {
		const stop = listen(handle);
		const timer = setInterval(() => {
			clock = formatClock();
			pad = hasGamepad();
		}, 1000);
		pad = hasGamepad();
		return () => {
			stop();
			clearInterval(timer);
		};
	});
</script>

<Backdrop src={selected?.hero ?? ''} dimmed={screen === 'detail'} />

<main>
	{#if screen === 'home'}
		<Home games={library} {index} {clock} />
	{:else if selected}
		<Detail game={selected} onplay={launch} />
	{/if}
</main>

{#if notice}
	<div class="notice">{notice}</div>
{/if}

<footer class="help">
	{#if screen === 'home'}
		<span><b class="a">A</b> Ouvrir</span>
		<span><b class="x">X</b> Options</span>
		<span><b class="y">Y</b> Recherche</span>
	{:else}
		<span><b class="a">A</b> Jouer</span>
		<span><b class="b">B</b> Retour</span>
	{/if}
	{#if !pad}
		<span class="hint">Flèches · Entrée · Échap</span>
	{/if}
</footer>

<style>
	main {
		position: relative;
		z-index: 1;
		height: 100%;
	}

	.help {
		position: fixed;
		z-index: 3;
		left: var(--safe-x);
		bottom: calc(var(--safe-y) * 0.45);
		display: flex;
		gap: 26px;
		align-items: center;
		font-size: 17px;
		color: var(--text-dim);
	}

	.help b {
		display: inline-grid;
		place-items: center;
		width: 26px;
		height: 26px;
		margin-right: 8px;
		border-radius: 50%;
		font-size: 14px;
		font-weight: 700;
		color: #05130a;
	}

	.a {
		background: var(--accent);
	}
	.b {
		background: #ef4444;
		color: #fff;
	}
	.x {
		background: #3b82f6;
		color: #fff;
	}
	.y {
		background: #facc15;
	}

	.hint {
		opacity: 0.5;
	}

	.notice {
		position: fixed;
		z-index: 4;
		right: var(--safe-x);
		bottom: calc(var(--safe-y) * 0.45);
		padding: 14px 22px;
		border-radius: var(--radius);
		background: var(--surface-strong);
		backdrop-filter: blur(12px);
		font-size: 18px;
		animation: rise 220ms var(--ease) both;
	}

	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(10px);
		}
	}
</style>
