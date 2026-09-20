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

<header class="top">
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

	<nav class="sections" class:focused>
		{#each SECTIONS as entry}
			<button
				type="button"
				class="pill"
				class:active={entry.id === section}
				class:is-hub={entry.id === 'home'}
				title={entry.label}
				onclick={() => onSelectSection?.(entry.id)}
			>
				<img src="/assets/icons/{entry.icon}.svg" alt={entry.label} />
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
		justify-content: space-between;
		gap: 32px;
		height: 110px;
		padding: 0 var(--safe-x);
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
		box-shadow: 0 0 0 3px rgba(34, 211, 102, 0.22);
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

	/* Les sections sont des pastilles, comme sur un tableau de bord de console. */
	.sections {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: 8px 14px;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.04);
		transition:
			background var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	.sections.focused {
		background: rgba(255, 255, 255, 0.09);
		box-shadow: 0 0 0 2px var(--accent-soft);
	}

	.pill {
		display: grid;
		place-items: center;
		width: 46px;
		height: 46px;
		border-radius: 50%;
		border: none;
		background: rgba(255, 255, 255, 0.06);
		cursor: pointer;
		outline: none;
		padding: 0;
		transition:
			background var(--fast) var(--ease),
			transform var(--fast) var(--ease),
			outline var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	.pill img {
		width: 24px;
		height: 24px;
		opacity: 0.7;
		transition: opacity var(--fast) var(--ease);
	}

	.pill:hover {
		outline: 3px solid var(--accent);
		box-shadow: 0 0 20px 4px var(--accent-soft);
	}

	.pill.active {
		background: var(--accent);
		transform: scale(1.04);
	}

	.pill:hover {
		outline: 3px solid var(--accent);
		outline-offset: 2px;
		box-shadow: 0 0 20px 4px var(--accent-soft);
	}

	.sections.focused .pill.active {
		outline: 4px solid var(--accent);
		outline-offset: 3px;
		box-shadow:
			0 0 32px 6px var(--accent-soft),
			0 0 12px var(--accent);
		transform: scale(1.1);
	}

	.pill.active img {
		opacity: 1;
		/* L'icône passe en sombre sur la pastille d'accent. */
		filter: brightness(0) saturate(100%) invert(8%) sepia(24%) saturate(1200%) hue-rotate(96deg);
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
