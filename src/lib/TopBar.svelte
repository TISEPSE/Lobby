<script lang="ts">
	import type { Section } from './types';

	/**
	 * Barre du haut : profil à gauche, sections au centre, manettes et heure à
	 * droite. Tout ce qui s'y affiche vient de données réelles — pas
	 * d'indicateur décoratif.
	 */
	let {
		section,
		focused = false,
		gamesCount,
		clock,
		pads = 0,
		profileName = 'Joueur',
		avatar = '',
	}: {
		section: Section;
		focused?: boolean;
		gamesCount: number;
		clock: string;
		pads?: number;
		profileName?: string;
		avatar?: string;
	} = $props();

	const SECTIONS: { id: Section; label: string }[] = [
		{ id: 'home', label: 'Accueil' },
		{ id: 'library', label: 'Bibliothèque' },
		{ id: 'search', label: 'Recherche' },
		{ id: 'settings', label: 'Réglages' },
	];
</script>

<header class="top">
	<div class="profile">
		<div class="avatar">
			{#if avatar}
				<img src={avatar} alt="" />
			{:else}
				{profileName.charAt(0).toUpperCase()}
			{/if}
		</div>
		<div>
			<div class="name">{profileName}</div>
			<div class="stat">{gamesCount} jeux installés</div>
		</div>
	</div>

	<nav class="sections" class:focused>
		{#each SECTIONS as entry}
			<span class="section" class:active={entry.id === section}>{entry.label}</span>
		{/each}
	</nav>

	<div class="right">
		{#if pads > 0}
			<span class="pads">
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
		justify-content: space-between;
		gap: 32px;
		padding: var(--safe-y) var(--safe-x) 0;
	}

	.profile {
		display: flex;
		align-items: center;
		gap: 14px;
	}

	.avatar {
		display: grid;
		place-items: center;
		width: 46px;
		height: 46px;
		overflow: hidden;
		border-radius: 50%;
		background: var(--accent);
		color: #06210f;
		font-size: 24px;
		font-weight: 700;
	}

	.avatar img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}

	.name {
		font-size: 22px;
		font-weight: 600;
	}

	.stat {
		font-size: 15px;
		color: var(--text-dim);
	}

	.sections {
		display: flex;
		gap: 28px;
		padding: 6px 18px;
		border-radius: var(--radius);
		transition: background var(--fast) var(--ease);
	}

	/* La barre n'a de halo que lorsque la sélection y est montée. */
	.sections.focused {
		background: var(--surface);
		box-shadow: 0 0 0 2px var(--accent-soft);
	}

	.section {
		font-size: 17px;
		color: var(--text-dim);
		padding-bottom: 6px;
		border-bottom: 2px solid transparent;
		transition: color var(--fast) var(--ease);
	}

	.section.active {
		color: var(--text);
		border-color: var(--accent);
	}

	.right {
		display: flex;
		align-items: center;
		gap: 20px;
	}

	.pads {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 18px;
		color: var(--text-dim);
	}

	.pads img {
		width: 24px;
		height: 24px;
		opacity: 0.7;
	}

	.clock {
		font-size: 22px;
		font-variant-numeric: tabular-nums;
	}
</style>
