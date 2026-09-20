<script lang="ts">
	import { onMount } from 'svelte';
	import Backdrop from './lib/Backdrop.svelte';
	import TopBar from './lib/TopBar.svelte';
	import Home from './lib/Home.svelte';
	import Library from './lib/Library.svelte';
	import Detail from './lib/Detail.svelte';
	import HelpBar from './lib/HelpBar.svelte';
	import { listen, padCount, type Action } from './lib/gamepad';
	import { play } from './lib/launcher';
	import { games, view, toggleFavorite, isFavorite, type Filter, type Sort } from './lib/library.svelte.js';
	import type { Game, Section } from './lib/types';

	const SECTIONS: Section[] = ['home', 'library', 'search', 'settings'];
	const FILTERS: Filter[] = ['all', 'favorites', 'recent'];
	const SORTS: Sort[] = ['title', 'recent', 'playtime'];
	const COLUMNS = 6;

	/* Outil de développement, comme le `--capture` de la version Godot :
	   `?screen=detail&index=3` ouvre directement un écran pour la capture. */
	const params = new URLSearchParams(location.search);

	/** Section affichée, et si la sélection est montée sur la barre du haut. */
	let section = $state<Section>((params.get('screen') as Section) ?? 'home');
	let onTabs = $state(false);
	/** Jeu ouvert en fiche détaillée. Null : on est sur la section courante. */
	let opened = $state<Game | null>(null);

	let homeIndex = $state(Number(params.get('index') ?? 0));
	let libraryIndex = $state(0);
	let filter = $state<Filter>('all');
	let sort = $state<Sort>('title');

	let clock = $state(formatClock());
	let pads = $state(0);
	let notice = $state('');

	const libraryGames = $derived(view(filter, sort));
	const selected = $derived(
		opened ?? (section === 'library' ? libraryGames[libraryIndex] : games[homeIndex])
	);

	function formatClock() {
		return new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
	}

	/**
	 * Changement d'écran animé par le navigateur : la jaquette de la tuile et
	 * celle de la fiche portent le même `view-transition-name`, le reste est
	 * automatique. C'est l'équivalent de la « jaquette fantôme » de la version
	 * Godot, en une ligne.
	 */
	function transition(change: () => void) {
		if (!document.startViewTransition) {
			change();
			return;
		}
		document.startViewTransition(change);
	}

	function openDetail(game: Game | undefined) {
		if (!game) return;
		transition(() => (opened = game));
	}

	function closeDetail() {
		transition(() => (opened = null));
	}

	function goToSection(next: Section) {
		if (next === section) return;
		transition(() => {
			section = next;
			libraryIndex = 0;
		});
	}

	/** Entrées de la barre du haut : on change de section en la parcourant. */
	function handleTabs(action: Action) {
		const current = SECTIONS.indexOf(section);
		if (action === 'left') goToSection(SECTIONS[Math.max(0, current - 1)]);
		else if (action === 'right') goToSection(SECTIONS[Math.min(SECTIONS.length - 1, current + 1)]);
		else if (action === 'down' || action === 'accept') onTabs = false;
		else if (action === 'cancel') onTabs = false;
	}

	function handleHome(action: Action) {
		if (action === 'left') homeIndex = Math.max(0, homeIndex - 1);
		else if (action === 'right') homeIndex = Math.min(games.length - 1, homeIndex + 1);
		else if (action === 'up') onTabs = true;
		else if (action === 'accept') openDetail(games[homeIndex]);
	}

	function handleLibrary(action: Action) {
		const total = libraryGames.length;
		const row = Math.floor(libraryIndex / COLUMNS);
		if (action === 'left') libraryIndex = Math.max(0, libraryIndex - 1);
		else if (action === 'right') libraryIndex = Math.min(total - 1, libraryIndex + 1);
		else if (action === 'down') libraryIndex = Math.min(total - 1, libraryIndex + COLUMNS);
		else if (action === 'up') {
			// Depuis la première ligne, on remonte vers les onglets.
			if (row === 0) onTabs = true;
			else libraryIndex = Math.max(0, libraryIndex - COLUMNS);
		} else if (action === 'accept') openDetail(libraryGames[libraryIndex]);
		else if (action === 'options') {
			// X parcourt les filtres, Y les tris : deux touches, aucun sous-menu.
			filter = FILTERS[(FILTERS.indexOf(filter) + 1) % FILTERS.length];
			libraryIndex = 0;
		} else if (action === 'search') {
			sort = SORTS[(SORTS.indexOf(sort) + 1) % SORTS.length];
			libraryIndex = 0;
		} else if (action === 'cancel') goToSection('home');
	}

	function handleDetail(action: Action) {
		if (action === 'cancel') closeDetail();
		else if (action === 'accept') launch();
		else if (action === 'options' && opened) {
			toggleFavorite(opened.id);
			notify(isFavorite(opened.id) ? 'Ajouté aux favoris.' : 'Retiré des favoris.');
		}
	}

	function handle(action: Action) {
		if (opened) return handleDetail(action);
		if (onTabs) return handleTabs(action);
		if (section === 'library') return handleLibrary(action);
		if (section === 'home') return handleHome(action);
		// Sections encore vides : seule la remontée vers les onglets répond.
		if (action === 'up') onTabs = true;
		else if (action === 'cancel') goToSection('home');
	}

	function notify(message: string) {
		notice = message;
		setTimeout(() => (notice = ''), 3000);
	}

	async function launch() {
		if (!selected) return;
		notify(await play(selected));
	}

	onMount(() => {
		const stop = listen(handle);
		const timer = setInterval(() => {
			clock = formatClock();
			pads = padCount();
		}, 1000);
		pads = padCount();
		return () => {
			stop();
			clearInterval(timer);
		};
	});

	/** Aide contextuelle : ce que font les touches, ici et maintenant. */
	const help = $derived(
		opened
			? [
					{ button: 'a' as const, label: 'Jouer' },
					{ button: 'x' as const, label: isFavorite(opened.id) ? 'Retirer des favoris' : 'Favori' },
					{ button: 'b' as const, label: 'Retour' },
				]
			: section === 'library'
				? [
						{ button: 'a' as const, label: 'Ouvrir' },
						{ button: 'x' as const, label: 'Filtre' },
						{ button: 'y' as const, label: 'Tri' },
						{ button: 'b' as const, label: 'Accueil' },
					]
				: [
						{ button: 'a' as const, label: 'Ouvrir' },
						{ button: 'x' as const, label: 'Options' },
						{ button: 'y' as const, label: 'Recherche' },
					]
	);
</script>

<Backdrop src={selected?.hero ?? ''} dimmed={opened !== null || section !== 'home'} />

<TopBar
	{section}
	focused={onTabs}
	{clock}
	{pads}
	gamesCount={games.length}
/>

<main>
	{#if opened}
		<Detail game={opened} favorite={isFavorite(opened.id)} onplay={launch} />
	{:else if section === 'home'}
		<Home {games} index={homeIndex} />
	{:else if section === 'library'}
		<Library games={libraryGames} index={libraryIndex} {filter} {sort} columns={COLUMNS} />
	{:else}
		<section class="todo">
			<h1>{section === 'search' ? 'Recherche' : 'Réglages'}</h1>
			<p>Cet écran arrive à l'étape suivante.</p>
		</section>
	{/if}
</main>

{#if notice}
	<div class="notice">{notice}</div>
{/if}

<HelpBar entries={help} />

<style>
	main {
		position: relative;
		z-index: 1;
		height: calc(100% - 110px);
	}

	.todo {
		display: flex;
		flex-direction: column;
		justify-content: center;
		height: 100%;
		padding: 0 var(--safe-x);
	}

	.todo h1 {
		margin: 0;
		font-size: clamp(32px, 3.4vw, 56px);
	}

	.todo p {
		font-size: 20px;
		color: var(--text-dim);
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
