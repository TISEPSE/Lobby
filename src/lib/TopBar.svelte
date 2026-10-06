<script lang="ts">
	import type { Section } from './types';
	import { padLayout } from './gamepad';
	import { glyphSrc } from './glyphs';
	import Glyph from './Glyph.svelte';

	/**
	 * Dock du haut, à la manière du tableau de bord Xbox : une pilule compacte
	 * posée sur l'artwork. On y circule **uniquement avec L1 / R1** (LB / RB),
	 * dont les glyphes encadrent le dock : la sélection reste toujours dans le
	 * contenu, le dock dit seulement où l'on se trouve.
	 *
	 * La section courante est une pilule claire qui porte son nom ; les autres
	 * ne montrent que leur icône. Le profil est la dernière section, à droite.
	 */
	let {
		section,
		gamesCount,
		clock,
		pads = 0,
		profileName = 'Joueur',
		avatar = '',
		searching = false,
		onSelectSection,
		onOpenSearch,
	}: {
		section: Section;
		gamesCount: number;
		clock: string;
		pads?: number;
		profileName?: string;
		avatar?: string;
		/** Fenêtre de recherche ouverte. */
		searching?: boolean;
		onSelectSection?: (section: Section) => void;
		/** La recherche est une fenêtre (Y), pas une section du dock. */
		onOpenSearch?: () => void;
	} = $props();

	type Entry = { id: Section; label: string; icon: string };

	const LEFT: Entry[] = [
		{ id: 'home', label: 'Accueil', icon: 'home' },
		{ id: 'library', label: 'Bibliothèque', icon: 'library' },
	];
	const RIGHT: Entry[] = [{ id: 'settings', label: 'Réglages', icon: 'settings' }];

	/** Glyphes LB / RB ou L1 / R1, selon la manette branchée. */
	let layout = $state<'xbox' | 'ps5'>('xbox');
	$effect(() => {
		layout = padLayout();
		const timer = setInterval(() => (layout = padLayout()), 1000);
		return () => clearInterval(timer);
	});
</script>

{#snippet button(entry: Entry)}
	<button
		type="button"
		class="item"
		class:active={entry.id === section}
		onclick={() => onSelectSection?.(entry.id)}
		aria-label={entry.label}
		aria-current={entry.id === section}
	>
		<img src="/assets/icons/{entry.icon}.svg" alt="" />
		<span class="label"><span class="text">{entry.label}</span></span>
	</button>
{/snippet}

<header class="top">
	<div class="dock">
		<div class="group">
			<img class="bumper" src={glyphSrc(layout, 'l1')} alt="L1" />
			{#each LEFT as entry (entry.id)}
				{@render button(entry)}
			{/each}
		</div>

		<!-- La recherche n'est pas une étape de L1 / R1 : c'est une fenêtre,
		     ouverte par Y de partout. Le champ porte le glyphe de ce bouton. -->
		<button
			type="button"
			class="search"
			class:active={searching}
			onclick={() => onOpenSearch?.()}
		>
			<img src="/assets/icons/search.svg" alt="" />
			<span>Rechercher parmi {gamesCount} jeux</span>
			<span class="y"><Glyph button="y" size="26px" /></span>
		</button>

		<div class="group">
			{#each RIGHT as entry (entry.id)}
				{@render button(entry)}
			{/each}

			<button
				type="button"
				class="profile"
				class:active={section === 'profile'}
				onclick={() => onSelectSection?.('profile')}
				aria-label="Profil"
				aria-current={section === 'profile'}
			>
				<span class="avatar">
					{#if avatar}
						<img src={avatar} alt="" />
					{:else}
						{profileName.charAt(0).toUpperCase()}
					{/if}
				</span>
				<span class="label"><span class="text">{profileName}</span></span>
			</button>
			<img class="bumper" src={glyphSrc(layout, 'r1')} alt="R1" />
		</div>
	</div>

	<!-- L'heure et les manettes ne sont pas des sections : elles vivent hors
	     du dock, dans le coin, comme sur le tableau de bord d'une console. -->
	<span class="status">
		{#if pads > 0}
			<span class="pads">
				<img src="/assets/icons/controller.svg" alt="" />
				{pads}
			</span>
		{/if}
		<span class="clock">{clock}</span>
	</span>
</header>

<style>
	.top {
		position: relative;
		z-index: 2;
		display: flex;
		align-items: center;
		justify-content: center;
		height: var(--topbar-height);
		padding: 0 var(--safe-x);
		/* Le dock ne participe pas aux transitions de la fiche : sans nom
		   propre, il était photographié avec la page et clignotait. */
		view-transition-name: dock;
	}

	/* Pilule translucide floutée, liseré fin : elle flotte sur l'artwork sans
	   le masquer. */
	/* Largeur du contenu, centrée : ni étirée d'un bord à l'autre, ni collée
	   à un côté. */
	.dock {
		display: flex;
		align-items: center;
		gap: 14px;
		width: fit-content;
		max-width: 100%;
		padding: var(--dock-pad);
		border-radius: 999px;
		background: var(--dock-bg);
		border: 1px solid var(--dock-border);
		backdrop-filter: blur(18px) saturate(1.2);
		box-shadow: 0 10px 30px rgba(0, 0, 0, 0.3);
	}

	.group {
		display: flex;
		align-items: center;
		gap: 6px;
	}


	/* LB / RB aux deux bouts : c'est avec eux qu'on circule dans le dock. */
	.bumper {
		width: var(--dock-glyph);
		height: var(--dock-glyph);
		margin: -4px 2px;
	}

	/* Bouton rond ; la section courante s'allonge en pilule claire avec son
	   nom. Seule la largeur du nom s'anime (voir `.label`) : pas de padding ni
	   de marge qui changent en même temps. */
	/* Chaque bouton montre **toujours** son icône et son nom : rien ne s'ouvre
	   ni ne se ferme, le dock garde la même taille et se lit d'un coup d'œil. */
	.item,
	.profile {
		display: flex;
		align-items: center;
		gap: 10px;
		height: var(--dock-button);
		padding: 0 16px 0 calc((var(--dock-button) - var(--dock-icon)) / 2);
		border-radius: 999px;
		color: var(--text-dim);
		transition:
			background var(--fast) var(--ease),
			color var(--fast) var(--ease),
			transform var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	/* Survol : la pilule s'éclaire et se soulève à peine. */
	.item:hover,
	.profile:hover,
	.search:hover {
		background: var(--dock-hover);
		color: var(--text);
		transform: translateY(-1px);
		box-shadow: 0 6px 16px rgba(0, 0, 0, 0.3);
	}

	.item:hover img,
	.search:hover img {
		opacity: 1;
	}

	.item:active,
	.profile:active,
	.search:active {
		transform: translateY(0) scale(0.97);
	}

	.item img,
	.search img {
		flex: none;
		width: var(--dock-icon);
		height: var(--dock-icon);
		opacity: 0.6;
		transition: opacity var(--fast) var(--ease);
	}

	.label {
		flex: none;
	}

	.text {
		display: block;
		max-width: var(--dock-label);
		overflow: hidden;
		white-space: nowrap;
		text-overflow: ellipsis;
		font-size: 17px;
		font-weight: 600;
	}

	/* Section courante : pilule claire, icône pleine, nom affiché. Pas de
	   contour d'accent — ce n'est pas une sélection, la sélection est dans le
	   contenu. */
	.item.active,
	.profile.active,
	.search.active {
		background: var(--dock-active);
		color: var(--text);
	}

	.item.active img,
	.search.active img {
		opacity: 1;
	}

	.search {
		display: flex;
		align-items: center;
		gap: 12px;
		width: var(--dock-search);
		height: var(--dock-button);
		padding: 0 20px;
		border-radius: 999px;
		background: var(--surface);
		color: var(--text-dim);
		font-size: 17px;
		transition: background var(--normal) var(--ease);
	}

	.search.active {
		color: var(--text);
	}

	.y {
		display: flex;
		margin-left: auto;
		margin-right: -12px;
	}

	.status {
		position: absolute;
		right: var(--safe-x);
		top: 50%;
		transform: translateY(-50%);
		display: flex;
		align-items: center;
		gap: 18px;
	}

	.pads {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 17px;
		color: var(--text-dim);
	}

	.pads img {
		width: 22px;
		height: 22px;
		opacity: 0.75;
	}

	.clock {
		font-size: 24px;
		font-weight: 600;
		text-shadow: 0 2px 12px rgba(0, 0, 0, 0.6);
		font-variant-numeric: tabular-nums;
	}

	/* Le profil : la photo, cerclée d'accent comme sur une Xbox ; le pseudo
	   apparaît quand c'est la section courante. */
	/* La photo occupe le début de la pilule, le pseudo suit. */
	.profile {
		padding: 0 16px 0 3px;
	}

	.avatar {
		display: grid;
		flex: none;
		place-items: center;
		width: calc(var(--dock-button) - 6px);
		height: calc(var(--dock-button) - 6px);
		overflow: hidden;
		border-radius: 50%;
		background: var(--accent);
		color: var(--on-accent);
		font-size: 17px;
		font-weight: 700;
		box-shadow: 0 0 0 2px var(--accent);
	}

	.avatar img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}
</style>
