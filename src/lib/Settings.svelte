<script lang="ts">
	import type { Action } from './gamepad';
	import type { GlyphButton } from './glyphs';
	import type { Game, VolumeKey } from './types';
	import { notices } from './notices.svelte.js';
	import { LAYOUT_LABELS, nextLayout } from './settings.svelte.js';
	import VirtualKeyboard from './VirtualKeyboard.svelte';

	let {
		focused = true,
		gameFolders = [],
		buttonLayout = 'ps5',
		soundEnabled = true,
		volumes = { volume_master: 100, volume_menu: 100, volume_alerts: 100, volume_launch: 100, volume_video: 100 },
		onStepVolume,
		screensaverMinutes = 5,
		steamGridKey = '',
		initialCategory = 'games',
		initialRow = -1,
		initialKeyboard = false,
		fullscreen = true,
		onToggleFullscreen,
		homeOrderLabel = '',
		onCycleHomeOrder,
		onBack,
		onReturnToHub = onBack,
		onOpenScan,
		onPickFolder,
		onRemoveFolder,
		hiddenGames = [],
		onRestoreGame,
		onChangeLayout,
		onToggleSound,
		onCycleScreensaver,
		onChangeSteamGridKey,
	}: {
		focused?: boolean;
		gameFolders: string[];
		buttonLayout: string;
		soundEnabled?: boolean;
		/** Volumes en pour cent (Réglages → Audio). */
		volumes?: Record<VolumeKey, number>;
		/** Monte ou baisse un volume de `delta` points. */
		onStepVolume?: (key: VolumeKey, delta: number) => void;
		screensaverMinutes?: number;
		steamGridKey?: string;
		/** Catégorie ouverte au premier affichage (outil de capture). */
		initialCategory?: string;
		/** Ligne sélectionnée au premier affichage, -1 pour les catégories (outil de capture). */
		initialRow?: number;
		/** Ouvre le clavier au premier affichage (outil de capture). */
		initialKeyboard?: boolean;
		/** Plein écran sans bordure, ou fenêtre classique. */
		fullscreen?: boolean;
		onToggleFullscreen?: () => void;
		/** Ordre de la rangée d'accueil, tel qu'affiché. */
		homeOrderLabel?: string;
		onCycleHomeOrder?: () => void;
		onBack: () => void;
		onReturnToHub?: () => void;
		onOpenScan: () => void;
		/** Ouvre l'explorateur pour choisir un dossier de jeux. */
		onPickFolder: () => void;
		onRemoveFolder: (path: string) => void;
		/** Entrées retirées de la bibliothèque, qu'on peut rétablir ici. */
		hiddenGames?: Game[];
		onRestoreGame?: (id: string) => void;
		onChangeLayout: (layout: string) => void;
		onToggleSound?: () => void;
		onCycleScreensaver?: () => void;
		onChangeSteamGridKey?: (key: string) => void;
	} = $props();

	type CategoryId = 'games' | 'appearance' | 'audio' | 'system';

	interface Category {
		id: CategoryId;
		label: string;
		icon: string;
		hint: string;
	}

	const CATEGORIES: Category[] = [
		{
			id: 'games',
			label: 'Jeux',
			icon: 'library',
			hint: 'Détection automatique et dossiers où chercher tes jeux.',
		},
		{
			id: 'appearance',
			label: 'Apparence',
			icon: 'controller',
			hint: 'Style de l’interface et disposition des touches manette.',
		},
		{
			id: 'audio',
			label: 'Audio',
			icon: 'volume',
			hint: 'Sons de l’interface et volume de chaque famille de sons.',
		},
		{
			id: 'system',
			label: 'Système',
			icon: 'settings',
			hint: 'Affichage, et journal des derniers messages.',
		},
	];

	/** Ce que montre le côté droit d'une ligne : une présentation par type de réglage. */
	type Control =
		| { kind: 'open' }
		| { kind: 'value'; text: string }
		| { kind: 'switch'; on: boolean }
		| { kind: 'volume'; key: VolumeKey }
		| { kind: 'remove' }
		| { kind: 'restore' };

	interface Row {
		title: string;
		desc: string;
		control: Control;
		/** Ce que fait A, pour la barre d'aide. */
		accept: string;
		run: () => void;
		/** Titre de groupe, affiché au-dessus de la ligne. */
		section?: string;
		/** Réglage sans effet pour l'instant : volumes quand les sons sont coupés. */
		muted?: boolean;
	}

	let activeCatIndex = $state(Math.max(0, CATEGORIES.findIndex((c) => c.id === initialCategory)));
	let focusCol = $state<'categories' | 'content'>(initialRow >= 0 ? 'content' : 'categories');
	let focusRow = $state(Math.max(0, initialRow));

	let isKeyboardOpen = $state(initialKeyboard);
	let keyboardComponent = $state<any>(null);
	let scroller = $state<HTMLElement | null>(null);
	/** Position de la ligne sélectionnée dans la liste : le cadre y glisse. */
	let rowTop = $state(0);

	const currentCategory = $derived(CATEGORIES[activeCatIndex]);

	/** Volumes réglables, dans l'ordre de la page Audio. */
	const VOLUMES: { key: VolumeKey; title: string; desc: string }[] = [
		{ key: 'volume_master', title: 'Volume général', desc: 'Tous les sons et les vidéos de l’interface' },
		{ key: 'volume_menu', title: 'Menus', desc: 'Déplacements, validation et retour' },
		{ key: 'volume_alerts', title: 'Notifications', desc: 'Manette connectée, erreurs' },
		{ key: 'volume_launch', title: 'Lancement d’un jeu', desc: 'Le son joué quand une partie démarre' },
		{ key: 'volume_video', title: 'Vidéos', desc: 'Bandes-annonces des fiches de jeu' },
	];

	const screensaverLabel = $derived(
		screensaverMinutes > 0 ? `${screensaverMinutes} min` : 'Jamais'
	);

	/**
	 * État de la clé : une clé mal recopiée resterait sinon silencieuse jusqu'au
	 * prochain jeu sans jaquette. On la teste à la saisie et on le dit ici.
	 */
	let steamGridStatus = $state<'unknown' | 'testing' | 'ok' | 'bad' | 'offline'>('unknown');

	/** La clé ne s'affiche jamais en entier : quatre caractères suffisent. */
	const steamGridKeyLabel = $derived.by(() => {
		if (!steamGridKey) return 'Non configurée';
		const masked = `Configurée ····${steamGridKey.slice(-4)}`;
		if (steamGridStatus === 'testing') return `${masked} · vérification…`;
		if (steamGridStatus === 'ok') return `${masked} · vérifiée`;
		if (steamGridStatus === 'bad') return `${masked} · refusée`;
		if (steamGridStatus === 'offline') return `${masked} · non vérifiée`;
		return masked;
	});

	/** Clé déjà essayée, pour ne pas relancer la vérification à chaque rendu. */
	let testedKey = $state('');

	$effect(() => {
		const key = steamGridKey;
		if (!key || testedKey === key) return;
		testedKey = key;
		void checkSteamGridKey(key);
	});

	/** Essaie la clé auprès de SteamGridDB sans jamais l'afficher ni l'envoyer ailleurs. */
	export async function checkSteamGridKey(key: string): Promise<string> {
		if (!key) {
			steamGridStatus = 'unknown';
			return 'empty';
		}
		const tauri = (window as any).__TAURI_INTERNALS__;
		if (!tauri) {
			steamGridStatus = 'unknown';
			return 'offline';
		}
		steamGridStatus = 'testing';
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			const result = await invoke<string>('test_steamgriddb_key', { key });
			steamGridStatus = result === 'ok' ? 'ok' : result === 'unauthorized' ? 'bad' : 'offline';
			return result;
		} catch {
			steamGridStatus = 'offline';
			return 'offline';
		}
	}

	/** La ligne sélectionnée disparaît : la sélection reste dans la liste. */
	function dropRow(action: () => void) {
		action();
		focusRow = Math.min(focusRow, rows.length - 1);
	}

	/**
	 * Les lignes de la catégorie ouverte. Tout en découle (rendu, navigation,
	 * action de A, barre d'aide) : rien à garder aligné par des numéros de ligne.
	 */
	const rows = $derived.by((): Row[] => {
		switch (currentCategory.id) {
			case 'games':
				return [
					{
						title: 'Détecter mes jeux',
						desc: 'Cherche dans Steam, Epic Games, les raccourcis du Bureau et tes dossiers.',
						control: { kind: 'open' },
						accept: 'Lancer',
						run: () => onOpenScan(),
					},
					{
						section: 'Jaquettes',
						title: 'Clé SteamGridDB',
						desc: 'Pour les jeux absents de Steam. Clé gratuite sur steamgriddb.com, gardée sur ce PC.',
						control: { kind: 'value', text: steamGridKeyLabel },
						accept: 'Modifier',
						run: () => (isKeyboardOpen = true),
					},
					{
						section: 'Dossiers surveillés',
						title: 'Ajouter un dossier',
						desc: 'Les sous-dossiers qui contiennent un jeu seront détectés.',
						control: { kind: 'open' },
						accept: 'Parcourir',
						run: () => onPickFolder(),
					},
					...gameFolders.map((folder): Row => ({
						title: folder,
						desc: 'Analysé à chaque détection',
						control: { kind: 'remove' },
						accept: 'Retirer',
						run: () => dropRow(() => onRemoveFolder(folder)),
					})),
					...hiddenGames.map((game, i): Row => ({
						section: i === 0 ? 'Jeux retirés' : undefined,
						title: game.title,
						desc: 'Ignoré par la détection. Rien n’a été désinstallé.',
						control: { kind: 'restore' },
						accept: 'Rétablir',
						run: () => dropRow(() => onRestoreGame?.(game.id)),
					})),
				];
			case 'appearance':
				return [
					{
						title: 'Disposition des touches',
						desc: 'Style des icônes de la manette dans l’interface et la barre d’aide',
						control: { kind: 'value', text: LAYOUT_LABELS[buttonLayout] ?? LAYOUT_LABELS.auto },
						accept: 'Changer',
						run: () => onChangeLayout(nextLayout(buttonLayout)),
					},
					{
						title: 'Écran de veille',
						desc: 'Artworks de la bibliothèque après un moment sans rien toucher',
						control: { kind: 'value', text: screensaverLabel },
						accept: 'Changer',
						run: () => onCycleScreensaver?.(),
					},
					{
						title: 'Ordre de l’accueil',
						desc: 'Les jeux auxquels tu as joué en dernier d’abord, ou par titre',
						control: { kind: 'value', text: homeOrderLabel },
						accept: 'Changer',
						run: () => onCycleHomeOrder?.(),
					},
				];
			case 'audio':
				return [
					{
						title: 'Sons de l’interface',
						desc: 'Petits sons de navigation, de validation et de lancement',
						control: { kind: 'switch', on: soundEnabled },
						accept: soundEnabled ? 'Désactiver' : 'Activer',
						run: () => onToggleSound?.(),
					},
					...VOLUMES.map((entry): Row => ({
						title: entry.title,
						desc: entry.desc,
						control: { kind: 'volume', key: entry.key },
						accept: 'Régler',
						muted: !soundEnabled && entry.key !== 'volume_video',
						// A fait le tour : +10 %, puis retour à 0 après 100 %.
						run: () => onStepVolume?.(entry.key, volumes[entry.key] >= 100 ? -100 : 10),
					})),
				];
			case 'system':
				return [
					{
						title: 'Affichage',
						desc: 'Plein écran sans bordure, ou fenêtre avec sa barre de titre (F11)',
						control: { kind: 'value', text: fullscreen ? 'Plein écran' : 'Fenêtre' },
						accept: 'Changer',
						run: () => onToggleFullscreen?.(),
					},
				];
		}
	});

	const focusedRow = $derived(focusCol === 'content' ? (rows[focusRow] ?? null) : null);
	/** Volume sélectionné, ou null : gauche / droite le règlent. */
	const focusedVolume = $derived(focusedRow?.control.kind === 'volume' ? focusedRow.control.key : null);

	// La ligne sélectionnée reste au centre de la liste, jamais hors de l'écran.
	// Les titres de groupe décalent les lignes : le cadre lit leur vraie position.
	$effect(() => {
		void rows.length;
		const row = scroller?.querySelector<HTMLElement>(`[data-row="${focusRow}"]`);
		if (!scroller || !row) return;
		rowTop = row.offsetTop;
		const top = focusCol === 'content' ? row.offsetTop - (scroller.clientHeight - row.offsetHeight) / 2 : 0;
		scroller.scrollTo({ top, behavior: 'smooth' });
	});

	/** Empreinte de la sélection, pour ne sonner que si elle bouge. Inconnue sous le clavier. */
	export function selectionKey(): string | null {
		if (isKeyboardOpen) return null;
		return `${focusCol}|${activeCatIndex}|${focusRow}`;
	}

	export function isKeyboardActive(): boolean {
		return isKeyboardOpen;
	}

	/** Touches de la barre d'aide pour la sélection du moment. */
	export function hints(): [GlyphButton, string][] {
		if (!focusedRow) return [['a', 'Ouvrir'], ['b', 'Accueil']];
		if (focusedVolume) return [['dpad', 'Régler'], ['b', 'Retour']];
		return [['a', focusedRow.accept], ['b', 'Retour']];
	}

	export function handleAction(action: Action) {
		if (isKeyboardOpen) {
			keyboardComponent?.handleAction(action);
			return;
		}

		if (focusCol === 'categories') {
			if (action === 'up') {
				// Rien au-dessus de la première catégorie : le dock se parcourt
				// avec L1 / R1.
				if (activeCatIndex > 0) {
					activeCatIndex -= 1;
					focusRow = 0;
				}
			} else if (action === 'down') {
				activeCatIndex = Math.min(CATEGORIES.length - 1, activeCatIndex + 1);
				focusRow = 0;
			} else if (action === 'right' || action === 'accept') {
				focusCol = 'content';
				focusRow = 0;
			} else if (action === 'cancel') {
				onReturnToHub?.();
			}
			return;
		}

		if (action === 'up') {
			focusRow = Math.max(0, focusRow - 1);
		} else if (action === 'down') {
			focusRow = Math.min(rows.length - 1, focusRow + 1);
		} else if (focusedVolume && (action === 'left' || action === 'right')) {
			// Sur un volume, gauche / droite le règlent ; B revient aux catégories.
			onStepVolume?.(focusedVolume, action === 'left' ? -10 : 10);
		} else if (action === 'left' || action === 'cancel') {
			focusCol = 'categories';
		} else if (action === 'accept') {
			focusedRow?.run();
		}
	}
</script>

<div class="settings-screen">
	<aside class="sidebar">
		<h1>Réglages</h1>
		<nav class="categories" style="--cat: {activeCatIndex}">
			<span class="glider pill" class:focus-ring={focused && focusCol === 'categories'}></span>
			{#each CATEGORIES as cat, i (cat.id)}
				<button
					type="button"
					class="category"
					class:active={activeCatIndex === i}
					onclick={() => {
						activeCatIndex = i;
						focusCol = 'categories';
						focusRow = 0;
					}}
				>
					<img src="/assets/icons/{cat.icon}.svg" alt="" />
					{cat.label}
				</button>
			{/each}
		</nav>
	</aside>

	<section class="page">
		<header>
			<h2>{currentCategory.label}</h2>
			<p>{currentCategory.hint}</p>
		</header>

		<div class="rows" bind:this={scroller}>
			<span
				class="glider cursor focus-ring"
				class:off={!focused || focusCol !== 'content'}
				style="--glide-y: {rowTop}px"
			></span>
			{#each rows as row, i (row.title)}
				{#if row.section}
					<h3>{row.section}</h3>
				{/if}
				<button
					type="button"
					class="row"
					class:muted={row.muted}
					class:selected={focused && focusCol === 'content' && focusRow === i}
					data-row={i}
					onclick={() => {
						focusCol = 'content';
						focusRow = i;
						row.run();
					}}
				>
					<span class="text">
						<span class="title">{row.title}</span>
						<span class="desc">{row.desc}</span>
					</span>

					{#if row.control.kind === 'value'}
						<span class="value">{row.control.text}</span>
						<img class="chevron" src="/assets/icons/chevron.svg" alt="" />
					{:else if row.control.kind === 'open'}
						<img class="chevron" src="/assets/icons/chevron.svg" alt="" />
					{:else if row.control.kind === 'switch'}
						<span class="value">{row.control.on ? 'Activés' : 'Désactivés'}</span>
						<span class="switch" class:on={row.control.on}></span>
					{:else if row.control.kind === 'volume'}
						{@const value = volumes[row.control.key]}
						<span class="volume">
							<span class="arrow">◂</span>
							<span class="bar"><span class="fill" style="width: {value}%"></span></span>
							<span class="percent">{value} %</span>
							<span class="arrow">▸</span>
						</span>
					{:else if row.control.kind === 'restore'}
						<span class="value restore">Rétablir</span>
					{:else}
						<span class="value remove">Retirer</span>
					{/if}
				</button>
			{/each}

			{#if currentCategory.id === 'system'}
				<!-- Les derniers messages du bandeau : un avertissement passé trop
				     vite se relit ici. -->
				<h3>Journal</h3>
				{#if notices.length === 0}
					<p class="journal-empty">Aucun message depuis le démarrage.</p>
				{:else}
					<ul class="journal">
						{#each notices.slice(0, 12) as entry (entry.at + entry.message)}
							<li class:failed={!entry.ok}>
								<span class="journal-time">
									{new Date(entry.at).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
								</span>
								<span>{entry.message}</span>
							</li>
						{/each}
					</ul>
				{/if}
			{/if}
		</div>
	</section>

	<!-- Clavier virtuel : la seule saisie des réglages, la clé SteamGridDB. -->
	<VirtualKeyboard
		open={isKeyboardOpen}
		title="Clé SteamGridDB"
		subtitle="Colle ta clé (steamgriddb.com > Preferences > API). Elle reste sur cette machine."
		initialValue={steamGridKey}
		maxLength={64}
		onConfirm={(value) => {
			onChangeSteamGridKey?.(value.trim());
			isKeyboardOpen = false;
		}}
		onClose={() => {
			isKeyboardOpen = false;
		}}
		bind:this={keyboardComponent}
	/>
</div>

<style>
	.settings-screen {
		position: relative;
		display: grid;
		grid-template-columns: var(--settings-nav) minmax(0, 1fr);
		gap: var(--settings-columns);
		height: 100%;
		padding: 0 var(--safe-x) var(--settings-bottom);
	}

	/* Colonne de gauche : les catégories. */
	.sidebar {
		display: flex;
		flex-direction: column;
		min-height: 0;
	}

	h1 {
		flex: none;
		height: var(--settings-header);
		margin: 0;
		font-size: var(--settings-title);
		font-weight: 800;
		line-height: 1.2;
	}

	.categories {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--settings-row-gap);
		isolation: isolate;
	}

	/* Catégorie ouverte : la pilule claire du dock, qui glisse d'une catégorie à
	   l'autre ; le contour ne s'y ajoute que si la sélection est ici. */
	.pill {
		top: 0;
		left: 0;
		right: 0;
		height: var(--settings-nav-row);
		--glide-y: calc(var(--cat) * (var(--settings-nav-row) + var(--settings-row-gap)));
		border-radius: var(--settings-radius);
		background: var(--dock-active);
	}

	.category {
		position: relative;
		z-index: 1;
		display: flex;
		align-items: center;
		gap: 16px;
		width: 100%;
		height: var(--settings-nav-row);
		padding: 0 20px;
		border-radius: var(--settings-radius);
		font-size: var(--settings-label);
		font-weight: 600;
		color: var(--text-dim);
		text-align: left;
		transition:
			background var(--fast) var(--ease),
			color var(--fast) var(--ease);
	}

	.category img {
		width: var(--settings-icon);
		height: var(--settings-icon);
		opacity: 0.7;
	}

	.category:hover:not(.active) {
		background: var(--dock-hover);
		color: var(--text);
	}

	.category.active {
		color: var(--text);
	}

	.category.active img {
		opacity: 1;
	}

	/* Colonne de droite : le titre reste en place, seules les lignes défilent. */
	.page {
		display: flex;
		flex-direction: column;
		min-width: 0;
		min-height: 0;
	}

	/* Le décalage pose le titre sur la ligne de base de « Réglages ». */
	.page header {
		flex: none;
		height: var(--settings-header);
		padding-top: var(--settings-heading-top);
	}

	h2 {
		margin: 0 0 4px;
		font-size: var(--settings-heading);
		font-weight: 700;
		line-height: 1.2;
	}

	.page header p {
		margin: 0;
		font-size: var(--settings-text);
		color: var(--text-dim);
	}

	/* La gouttière laisse la place au contour et à l'agrandissement de la
	   sélection, que le défilement trancherait sinon. */
	.rows {
		position: relative;
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: var(--settings-row-gap);
		min-height: 0;
		margin: calc(-1 * var(--hover-room));
		padding: var(--hover-room);
		overflow-y: auto;
		scrollbar-width: none;
		isolation: isolate;
	}

	.cursor {
		top: 0;
		left: var(--hover-room);
		right: var(--hover-room);
		height: var(--settings-row);
		--glide-scale: var(--settings-focus-scale);
		border-radius: var(--settings-radius);
		background: var(--settings-row-hover);
	}

	.cursor.off {
		opacity: 0;
	}

	h3 {
		flex: none;
		margin: 14px 0 4px;
		font-size: var(--settings-text);
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--text-dim);
	}

	.row {
		flex: none;
		display: flex;
		align-items: center;
		gap: 18px;
		width: 100%;
		height: var(--settings-row);
		padding: 0 var(--settings-row-pad);
		border-radius: var(--settings-radius);
		background: var(--settings-row-bg);
		text-align: left;
		transition: background var(--fast) var(--ease);
	}

	.row:hover {
		background: var(--settings-row-hover);
	}

	/* C'est le cadre qui marque la sélection : la ligne le laisse transparaître. */
	.row.selected {
		background: transparent;
	}

	.row > * {
		position: relative;
		z-index: 1;
	}

	/* Sons coupés : leurs volumes restent réglables, mais en retrait. Sur le
	   contenu, pas sur la ligne : voir `.glider`. */
	.row.muted > * {
		opacity: 0.5;
	}

	.text {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 3px;
		min-width: 0;
	}

	.title,
	.desc {
		overflow: hidden;
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	.title {
		font-size: var(--settings-label);
		font-weight: 600;
	}

	.desc {
		font-size: var(--settings-text);
		color: var(--text-dim);
	}

	/* Valeur d'un réglage : la même partout. */
	.value {
		flex: none;
		font-size: var(--settings-value);
		font-weight: 600;
		color: var(--text-dim);
		transition: color var(--fast) var(--ease);
	}

	.row.selected .value {
		color: var(--text);
	}

	.value.remove,
	.row.selected .value.remove {
		color: var(--danger);
	}

	.value.restore,
	.row.selected .value.restore {
		color: var(--accent);
	}

	.chevron {
		flex: none;
		width: var(--settings-chevron);
		height: var(--settings-chevron);
		opacity: 0.5;
		transition: opacity var(--fast) var(--ease);
	}

	.row.selected .chevron {
		opacity: 1;
	}

	.switch {
		flex: none;
		position: relative;
		width: var(--settings-switch);
		height: var(--settings-switch-height);
		border-radius: 999px;
		background: var(--surface-strong);
		transition: background var(--fast) var(--ease);
	}

	.switch::after {
		content: '';
		position: absolute;
		top: var(--settings-switch-pad);
		left: var(--settings-switch-pad);
		width: calc(var(--settings-switch-height) - 2 * var(--settings-switch-pad));
		aspect-ratio: 1;
		border-radius: 50%;
		background: var(--text);
		transition: transform var(--fast) var(--ease);
	}

	.switch.on {
		background: var(--accent);
	}

	.switch.on::after {
		background: var(--on-accent);
		transform: translateX(calc(var(--settings-switch) - var(--settings-switch-height)));
	}

	/* Jauge de volume : gauche / droite la règlent par pas de 10 %. */
	.volume {
		flex: none;
		display: flex;
		align-items: center;
		gap: 12px;
		font-size: var(--settings-value);
		font-weight: 600;
	}

	.bar {
		position: relative;
		width: var(--volume-bar);
		height: var(--volume-bar-height);
		border-radius: 999px;
		background: var(--surface-strong);
		overflow: hidden;
	}

	.fill {
		position: absolute;
		inset: 0 auto 0 0;
		border-radius: inherit;
		background: var(--accent);
		transition: width var(--fast) var(--ease);
	}

	.percent {
		min-width: 5ch;
		text-align: right;
		font-variant-numeric: tabular-nums;
	}

	/* Les flèches n'apparaissent que sur la ligne sélectionnée : c'est là que
	   gauche / droite agissent. */
	.arrow {
		color: var(--text-dim);
		opacity: 0;
		transition: opacity var(--fast) var(--ease);
	}

	.row.selected .arrow {
		opacity: 1;
	}

	/* Journal des messages (Réglages → Système). */
	.journal {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.journal li {
		display: flex;
		gap: 16px;
		padding: 10px var(--settings-row-pad);
		border-radius: var(--settings-radius);
		background: var(--settings-row-bg);
		font-size: var(--settings-text);
	}

	.journal li.failed {
		box-shadow: inset 3px 0 0 var(--danger);
	}

	.journal-time {
		flex: none;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	.journal-empty {
		margin: 0;
		font-size: var(--settings-text);
		color: var(--text-dim);
	}
</style>
