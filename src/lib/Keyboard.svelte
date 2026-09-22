<script lang="ts">
	/**
	 * Clavier à l'écran, partagé par tous les écrans qui demandent du texte :
	 * la recherche et les champs des réglages. Une touche a donc la même
	 * allure partout, et son style se change à un seul endroit.
	 *
	 * Les lettres sont volontairement grandes : un clavier de console se lit à
	 * trois mètres, et de petites capitales serrées font tout de suite « boîte
	 * de dialogue » plutôt que console de salon. Les touches qui n'écrivent
	 * rien portent une icône, pas une légende en bas de page.
	 */
	import { SEARCH_ROWS, SEARCH_COLUMNS, type SearchKey } from './searchKeys';
	import { padLayout } from './gamepad';

	/** Glyphes des boutons, comme dans la barre d'aide. */
	const FILES: Record<'xbox' | 'ps5', Record<'a' | 'b' | 'x' | 'y', string>> = {
		xbox: { a: 'xbox/a', b: 'xbox/b', x: 'xbox/x', y: 'xbox/y' },
		ps5: { a: 'ps5/cross', b: 'ps5/circle', x: 'ps5/square', y: 'ps5/triangle' },
	};

	let layout = $state<'xbox' | 'ps5'>('xbox');

	$effect(() => {
		const timer = setInterval(() => (layout = padLayout()), 1000);
		layout = padLayout();
		return () => clearInterval(timer);
	});

	let {
		rows = SEARCH_ROWS,
		row = 0,
		col = 0,
		active = true,
		onPress,
	}: {
		rows?: SearchKey[][];
		row?: number;
		col?: number;
		active?: boolean;
		/** Clic à la souris, pour le développement au navigateur. */
		onPress?: (row: number, col: number) => void;
	} = $props();
</script>

<div class="keyboard" class:dimmed={!active} style="--columns: {SEARCH_COLUMNS}">
	{#each rows as keys, r}
		<div class="krow">
			{#each keys as key, c}
				<button
					type="button"
					class="key"
					class:selected={active && r === row && c === col}
					style="--span: {key.span ?? 1}"
					onclick={() => onPress?.(r, c)}
				>
					{#if key.icon}
						<img src="/assets/icons/{key.icon}.svg" alt="" />
					{/if}
					{#if key.label}
						<span class="label">{key.label}</span>
					{:else}
						{key.value}
					{/if}
					{#if key.button}
						<!-- Le raccourci manette se lit sur la touche même. -->
						<img class="pad" src="/assets/buttons/{FILES[layout][key.button]}.svg" alt="" />
					{/if}
				</button>
			{/each}
		</div>
	{/each}
</div>

<style>
	.keyboard {
		display: flex;
		flex-direction: column;
		gap: var(--key-gap, 10px);
		transition: opacity var(--fast) var(--ease);
	}

	/* Le clavier inactif s'efface sans disparaître : on sait où on reviendra. */
	.dimmed {
		opacity: 0.4;
	}

	.krow {
		display: grid;
		grid-template-columns: repeat(var(--columns), 1fr);
		gap: var(--key-gap, 10px);
	}

	.key {
		position: relative;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 10px;
		grid-column: span var(--span);
		/* Les touches d'une même rangée gardent la même hauteur, quelle que soit
		   leur largeur : une touche « Espace » plus plate casserait la grille. */
		height: var(--key-size, 58px);
		padding: 0 8px;
		border-radius: 12px;
		background: rgba(255, 255, 255, 0.07);
		font-size: var(--key-font, 26px);
		font-weight: 600;
		/* Une touche ne grossit pas et ne s'auréole pas : elle **inverse ses
		   couleurs**. Sur une grille serrée, un agrandissement ferait sauter
		   tout le clavier à chaque déplacement. */
		transition:
			background var(--fast) var(--ease),
			color var(--fast) var(--ease);
	}

	/* Toutes les icônes occupent la même boîte : dessinées à des échelles
	   différentes, elles paraissaient sinon montées ou descendues. */
	.key img {
		width: 24px;
		height: 24px;
		object-fit: contain;
		opacity: 0.85;
	}

	.key .label {
		font-size: 18px;
		font-weight: 600;
	}

	/* Le glyphe se pose au bord droit de la touche : dans le flux, il décalait
	   l'icône et le mot vers la gauche et plus rien n'était centré. */
	.key .pad {
		position: absolute;
		right: 12px;
		top: 50%;
		width: 22px;
		height: 22px;
		transform: translateY(-50%);
		opacity: 0.75;
	}

	.key.selected {
		background: var(--accent);
		color: #06210f;
	}

	/* Sur fond d'accent, une icône blanche disparaîtrait : on l'assombrit. Le
	   glyphe de manette, lui, a ses propres couleurs : on le laisse tel quel. */
	.key.selected img:not(.pad) {
		filter: brightness(0.1);
		opacity: 1;
	}

	.key.selected .pad {
		opacity: 1;
	}
</style>
