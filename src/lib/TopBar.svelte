<script lang="ts">
	import type { Section } from './types';

	/**
	 * Barre du haut, dans l'esprit d'un tableau de bord de console : profil à
	 * gauche, sections en pastilles au centre, état de la machine à droite.
	 * Tout ce qui s'y affiche vient de données réelles — pas d'indicateur
	 * décoratif.
	 */
	let {
		section,
		focused = false,
		gamesCount,
		clock,
		pads = 0,
		profileName = 'Joueur',
		avatar = '',
		onSelectSection,
	}: {
		section: Section;
		focused?: boolean;
		gamesCount: number;
		clock: string;
		pads?: number;
		profileName?: string;
		avatar?: string;
		onSelectSection?: (section: Section) => void;
	} = $props();

	const SECTIONS: { id: Section; label: string; icon: string }[] = [
		{ id: 'home', label: 'Accueil', icon: 'home' },
		{ id: 'library', label: 'Bibliothèque', icon: 'library' },
		{ id: 'search', label: 'Recherche', icon: 'search' },
		{ id: 'settings', label: 'Réglages', icon: 'settings' },
	];

</script>

<header class="top" class:focused>
	<div class="profile">
		<div class="avatar">
			{#if avatar}
				<img src={avatar} alt="" />
			{:else}
				{profileName.charAt(0).toUpperCase()}
			{/if}
		</div>
		<div class="identity">
			<div class="name">{profileName}</div>
			<div class="stat">{gamesCount} jeux</div>
		</div>
	</div>

	<!-- Les sections s'écrivent en toutes lettres : sur une télé, une icône
	     seule oblige à deviner, et rien ne dit où l'on se trouve. -->
	<nav class="sections">
		{#each SECTIONS as entry}
			<button
				type="button"
				class="tab"
				class:active={entry.id === section}
				onclick={() => onSelectSection?.(entry.id)}
			>
				<img src="/assets/icons/{entry.icon}.svg" alt="" />
				<span>{entry.label}</span>
			</button>
		{/each}
	</nav>

	<div class="right">
		{#if pads > 0}
			<span class="chip">
				<img src="/assets/icons/controller.svg" alt="" />
				{pads}
			</span>
		{/if}
		<span class="clock">{clock}</span>
	</div>
</header>

<style>
	.top {
		position: relative;
		z-index: 2;
		display: flex;
		align-items: center;
		gap: 44px;
		height: 110px;
		padding: 0 var(--safe-x);
		/* La barre s'efface quand la sélection est descendue dans le contenu :
		   elle reste lisible, sans tirer l'œil hors du jeu regardé. */
		opacity: 0.72;
		transition: opacity var(--normal) var(--ease);
	}

	.top.focused {
		opacity: 1;
	}

	.profile {
		display: flex;
		align-items: center;
		gap: 14px;
	}

	.avatar {
		display: grid;
		place-items: center;
		width: 52px;
		height: 52px;
		overflow: hidden;
		border-radius: 50%;
		background: var(--accent);
		color: #06210f;
		font-size: 26px;
		font-weight: 700;
		/* Anneau fin autour de l'avatar : le repère « profil » d'une console. */
		box-shadow: 0 0 0 3px var(--accent-soft);
	}

	.avatar img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}

	.identity {
		line-height: 1.25;
	}

	.name {
		font-size: 21px;
		font-weight: 600;
	}

	.stat {
		font-size: 15px;
		color: var(--text-dim);
	}

	/* Onglets alignés à la suite du profil, pas de cartouche autour : la barre
	   se lit comme une ligne de titres, à la manière d'une console de salon. */
	.sections {
		display: flex;
		align-items: center;
		gap: 34px;
		margin-right: auto;
	}

	.tab {
		position: relative;
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 6px 2px 10px;
		border: none;
		background: none;
		color: var(--text-dim);
		font-size: 20px;
		font-weight: 600;
		cursor: pointer;
		transition: color var(--fast) var(--ease);
	}

	.tab img {
		width: 22px;
		height: 22px;
		opacity: 0.55;
		transition: opacity var(--fast) var(--ease);
	}

	/* Le trait d'accent est toujours là, mais il ne se révèle que sous
	   l'onglet courant : sa largeur s'anime d'un onglet à l'autre. */
	.tab::after {
		content: '';
		position: absolute;
		left: 0;
		right: 0;
		bottom: 0;
		height: 3px;
		border-radius: 3px;
		background: var(--accent);
		transform: scaleX(0);
		transform-origin: center;
		transition: transform var(--normal) var(--ease);
	}

	.tab.active {
		color: var(--text);
	}

	.tab.active img {
		opacity: 1;
	}

	.tab.active::after {
		transform: scaleX(1);
	}

	/* Quand la barre a la main, l'onglet courant s'allume franchement : la
	   sélection ne doit jamais se perdre. */
	.top.focused .tab.active {
		text-shadow: 0 0 24px var(--accent-soft);
	}

	.top.focused .tab.active::after {
		box-shadow: 0 0 18px 3px var(--accent-soft);
	}

	.right {
		display: flex;
		align-items: center;
		gap: 16px;
	}

	.chip {
		display: flex;
		align-items: center;
		gap: 8px;
		padding: 7px 14px;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.06);
		font-size: 16px;
		color: var(--text-dim);
	}

	.chip img {
		width: 20px;
		height: 20px;
		opacity: 0.75;
	}

	.clock {
		font-size: 22px;
		font-variant-numeric: tabular-nums;
	}
</style>
