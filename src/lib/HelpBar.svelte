<script lang="ts">
	import { hasGamepad, padLayout } from './gamepad';

	/**
	 * Barre d'aide : le vrai glyphe de la touche, puis ce qu'elle fait. Les
	 * images viennent de `public/assets/buttons/` — jeu Xbox ou PlayStation
	 * selon la manette branchée, comme sur une console.
	 */
	type Entry = { button: 'a' | 'b' | 'x' | 'y'; label: string };

	let { entries }: { entries: Entry[] } = $props();

	/** Correspondance entre nos actions et les fichiers de chaque famille. */
	const FILES: Record<'xbox' | 'ps5', Record<Entry['button'], string>> = {
		xbox: { a: 'xbox/a', b: 'xbox/b', x: 'xbox/x', y: 'xbox/y' },
		ps5: { a: 'ps5/cross', b: 'ps5/circle', x: 'ps5/square', y: 'ps5/triangle' },
	};

	let layout = $state<'xbox' | 'ps5'>('xbox');
	let pad = $state(false);

	$effect(() => {
		const timer = setInterval(() => {
			pad = hasGamepad();
			layout = padLayout();
		}, 1000);
		pad = hasGamepad();
		layout = padLayout();
		return () => clearInterval(timer);
	});
</script>

<footer class="help">
	{#each entries as entry}
		<span class="entry">
			<img src="/assets/buttons/{FILES[layout][entry.button]}.svg" alt={entry.button.toUpperCase()} />
			{entry.label}
		</span>
	{/each}
	{#if !pad}
		<span class="hint">Flèches · Entrée · Échap</span>
	{/if}
</footer>

<style>
	.help {
		position: fixed;
		z-index: 3;
		left: var(--safe-x);
		bottom: calc(var(--safe-y) * 0.45);
		display: flex;
		gap: 28px;
		align-items: center;
		font-size: 18px;
		color: var(--text-dim);
	}

	.entry {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	img {
		width: 30px;
		height: 30px;
	}

	.hint {
		opacity: 0.45;
	}
</style>
