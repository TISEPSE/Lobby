<script lang="ts">
	import { onMount } from 'svelte';
	import type { Action } from './gamepad';
	import type { VolumeKey } from './types';
	import VirtualKeyboard from './VirtualKeyboard.svelte';

	let {
		focused = true,
		gameFolders = [],
		buttonLayout = 'ps5',
		bootVideo = '',
		bootVideoEnabled = true,
		soundEnabled = true,
		volumes = { volume_master: 100, volume_menu: 100, volume_alerts: 100, volume_launch: 100, volume_video: 100 },
		onStepVolume,
		screensaverMinutes = 5,
		steamGridKey = '',
		initialCategory = 'games',
		initialKeyboard = false,
		fullscreen = true,
		onToggleFullscreen,
		homeOrderLabel = '',
		onCycleHomeOrder,
		onBack,
		onReturnToHub = onBack,
		onOpenScan,
		onAddFolder,
		onRemoveFolder,
		onChangeLayout,
		onCycleBootVideo,
		onToggleBootVideo,
		onToggleSound,
		onCycleScreensaver,
		onChangeSteamGridKey,
	}: {
		focused?: boolean;
		gameFolders: string[];
		buttonLayout: string;
		bootVideo?: string;
		bootVideoEnabled?: boolean;
		soundEnabled?: boolean;
		/** Volumes en pour cent (Réglages → Audio). */
		volumes?: Record<VolumeKey, number>;
		/** Monte ou baisse un volume de `delta` points. */
		onStepVolume?: (key: VolumeKey, delta: number) => void;
		screensaverMinutes?: number;
		steamGridKey?: string;
		/** Catégorie ouverte au premier affichage (outil de capture). */
		initialCategory?: string;
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
		onAddFolder: (path: string) => void;
		onRemoveFolder: (path: string) => void;
		onChangeLayout: (layout: string) => void;
		onCycleBootVideo?: () => void;
		onToggleBootVideo?: () => void;
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
			hint: 'Affichage de la console.',
		},
	];

	let activeCatIndex = $state(Math.max(0, CATEGORIES.findIndex((c) => c.id === initialCategory)));
	let focusCol = $state<'categories' | 'content'>('categories');
	let focusRow = $state(0);

	let isKeyboardOpen = $state(initialKeyboard);
	/** Ce que le clavier est en train de saisir : le pseudo ou la clé d'API. */
	/** La seule saisie des réglages : la clé SteamGridDB (le pseudo est dans le Profil). */
	let keyboardTarget = $state<'steamgrid'>('steamgrid');
	let keyboardComponent = $state<any>(null);

	let isAddingFolder = $state(false);
	let newFolderInput = $state('');

	const currentCategory = $derived(CATEGORIES[activeCatIndex]);

	/** Volumes réglables, dans l'ordre de la page Audio. */
	const VOLUMES: { key: VolumeKey; title: string; desc: string }[] = [
		{ key: 'volume_master', title: 'Volume général', desc: 'Tous les sons et les vidéos de l’interface' },
		{ key: 'volume_menu', title: 'Menus', desc: 'Déplacements, validation et retour' },
		{ key: 'volume_alerts', title: 'Notifications', desc: 'Manette connectée, erreurs' },
		{ key: 'volume_launch', title: 'Lancement d’un jeu', desc: 'Le son joué quand une partie démarre' },
		{ key: 'volume_video', title: 'Vidéos', desc: 'Vidéo d’introduction et bandes-annonces' },
	];

	/** Ligne de volume sélectionnée, ou null. */
	const focusedVolume = $derived(
		currentCategory.id === 'audio' && focusCol === 'content' && focusRow >= 1 ? VOLUMES[focusRow - 1] : null
	);
	/** La clé ne s'affiche jamais en entier : quatre caractères suffisent. */
	const screensaverLabel = $derived(
		screensaverMinutes > 0 ? `${screensaverMinutes} min` : 'Jamais'
	);

	/**
	 * État de la clé : une clé mal recopiée resterait sinon silencieuse jusqu'au
	 * prochain jeu sans jaquette. On la teste à la saisie et on le dit ici.
	 */
	let steamGridStatus = $state<'unknown' | 'testing' | 'ok' | 'bad' | 'offline'>('unknown');

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

	/** « /assets/boot/steamos_startup.webm » se lit « Steamos startup ». */
	const bootVideoName = $derived.by(() => {
		if (!bootVideo) return 'Aucune';
		const base = bootVideo.split('/').pop()?.replace(/\.[^.]+$/, '') ?? '';
		const words = base.replace(/[_-]+/g, ' ').trim();
		return words.charAt(0).toUpperCase() + words.slice(1);
	});

	// Nombre d'éléments interactifs dans le panneau de droite selon la catégorie
	const contentRowsCount = $derived.by(() => {
		switch (currentCategory.id) {
			case 'games':
				// [0: scanner, 1: clé SteamGridDB, 2: ajouter dossier, 3..N: dossiers]
				return 3 + gameFolders.length;
			case 'appearance':
				return 5; // [0: touches, 1: vidéo, 2: jouer au démarrage, 3: veille, 4: ordre de l'accueil]
			case 'audio':
				return 1 + VOLUMES.length; // [0: sons activés, 1..: volumes]
			case 'system':
				return 1; // [0: plein écran]
			default:
				return 0;
		}
	});

	/** Empreinte de la sélection, pour ne sonner que si elle bouge. Inconnue sous le clavier. */
	export function selectionKey(): string | null {
		if (isKeyboardOpen || isAddingFolder) return null;
		return `${focusCol}|${activeCatIndex}|${focusRow}`;
	}

	export function isKeyboardActive(): boolean {
		return isKeyboardOpen;
	}

	export function focusProfile() {
		focusCol = 'categories';
		activeCatIndex = 0;
		focusRow = 0;
	}

	export function handleAction(action: Action) {
		if (isKeyboardOpen) {
			keyboardComponent?.handleAction(action);
			return;
		}

		if (isAddingFolder) {
			if (action === 'accept') {
				confirmAddFolder();
			} else if (action === 'cancel') {
				isAddingFolder = false;
			}
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
				if (contentRowsCount > 0) {
					focusCol = 'content';
					focusRow = 0;
				}
			} else if (action === 'cancel') {
				onReturnToHub?.();
			}
		} else {
			// focusCol === 'content'
			if (action === 'up') {
				if (focusRow > 0) {
					focusRow--;
				} else {
					focusCol = 'categories';
				}
			} else if (action === 'down') {
				if (focusRow < contentRowsCount - 1) {
					focusRow++;
				}
			} else if (focusedVolume && (action === 'left' || action === 'right')) {
				// Sur un volume, gauche / droite le règlent ; B revient aux catégories.
				onStepVolume?.(focusedVolume.key, action === 'left' ? -10 : 10);
			} else if (action === 'left' || action === 'cancel') {
				focusCol = 'categories';
			} else if (action === 'accept') {
				executeContentAction();
			}
		}
	}

	function executeContentAction() {
		const cat = currentCategory.id;
		if (cat === 'games') {
			if (focusRow === 0) {
				onOpenScan();
			} else if (focusRow === 1) {
				keyboardTarget = 'steamgrid';
				isKeyboardOpen = true;
			} else if (focusRow === 2) {
				newFolderInput = 'D:/Jeux';
				isAddingFolder = true;
			} else {
				// Supprimer le dossier
				const folderIdx = focusRow - 3;
				if (folderIdx >= 0 && folderIdx < gameFolders.length) {
					onRemoveFolder(gameFolders[folderIdx]);
					focusRow = Math.max(1, focusRow - 1);
				}
			}
		} else if (cat === 'system') {
			if (focusRow === 0) onToggleFullscreen?.();
		} else if (cat === 'appearance') {
			if (focusRow === 0) {
				const next = buttonLayout === 'ps5' ? 'xbox' : buttonLayout === 'xbox' ? 'auto' : 'ps5';
				onChangeLayout(next);
			} else if (focusRow === 1) {
				onCycleBootVideo?.();
			} else if (focusRow === 2) {
				onToggleBootVideo?.();
			} else if (focusRow === 3) {
				onCycleScreensaver?.();
			} else if (focusRow === 4) {
				onCycleHomeOrder?.();
			}
		} else if (cat === 'audio') {
			if (focusRow === 0) {
				onToggleSound?.();
			} else if (focusedVolume) {
				// A fait le tour : +10 %, puis retour à 0 après 100 %.
				const value = volumes[focusedVolume.key];
				onStepVolume?.(focusedVolume.key, value >= 100 ? -100 : 10);
			}
		}
	}

	function confirmAddFolder() {
		const clean = newFolderInput.trim();
		if (clean) {
			onAddFolder(clean);
		}
		isAddingFolder = false;
	}
</script>

<div class="settings-screen">
	<!-- Colonne de gauche : Catégories -->
	<aside class="sidebar">
		<h1 class="page-title">Réglages</h1>
		<nav class="categories">
			{#each CATEGORIES as cat, i}
				<button
					type="button"
					class="cat-btn"
					class:active={activeCatIndex === i}
					class:focused={focused && focusCol === 'categories' && activeCatIndex === i}
					onclick={() => {
						activeCatIndex = i;
						focusCol = 'categories';
						focusRow = 0;
					}}
				>
					<span class="cat-icon">
						<img src="/assets/icons/{cat.icon}.svg" alt="" />
					</span>
					<span class="cat-label">{cat.label}</span>
				</button>
			{/each}
		</nav>
	</aside>

	<!-- Volet de droite : Contenu dynamique -->
	<main class="panel">
		<header class="panel-header">
			<h2>{currentCategory.label}</h2>
			<p class="panel-hint">{currentCategory.hint}</p>
		</header>

		<div class="panel-body">
			{#if currentCategory.id === 'games'}
				<!-- Gestion des jeux et du scan -->
				<div class="hero-action-card">
					<div class="hero-info">
						<div class="hero-title-row">
							<img src="/assets/icons/library.svg" alt="" class="hero-icon" />
							<span class="hero-title">Détection des jeux PC</span>
						</div>
						<span class="hero-desc">
							Analyse automatique de Steam, Epic Games, des raccourcis du Bureau et de tes dossiers de jeux.
						</span>
					</div>
					<button
						type="button"
						class="btn-scan"
						class:focused={focused && focusCol === 'content' && focusRow === 0}
						onclick={() => {
							focusCol = 'content';
							focusRow = 0;
							onOpenScan();
						}}
					>
						Lancer la détection
					</button>
				</div>

				<div class="section-divider">
					<h3>Jaquettes</h3>
				</div>

				<div class="rows-list">
					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 1}
						onclick={() => {
							focusCol = 'content';
							focusRow = 1;
							keyboardTarget = 'steamgrid';
							isKeyboardOpen = true;
						}}
					>
						<div class="row-label">
							<span class="title">Clé SteamGridDB</span>
							<span class="desc">
								Jaquettes des jeux absents de Steam. Clé gratuite sur steamgriddb.com
								(Preferences → API) ; elle reste sur cette machine.
							</span>
						</div>
						<span class="badge-layout">{steamGridKeyLabel} ▸</span>
					</button>
				</div>

				<div class="section-divider">
					<h3>Dossiers surveillés</h3>
				</div>

				<div class="rows-list">
					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 2}
						onclick={() => {
							focusCol = 'content';
							focusRow = 2;
							newFolderInput = 'D:/Jeux';
							isAddingFolder = true;
						}}
					>
						<div class="row-label">
							<span class="title">Ajouter un dossier de jeux</span>
							<span class="desc">Scanne les sous-dossiers contenant un exécutable ou une installation</span>
						</div>
						<span class="action-tag">+ Ajouter</span>
					</button>

					{#if isAddingFolder}
						<div class="folder-input-box">
							<input
								type="text"
								bind:value={newFolderInput}
								class="folder-input"
								placeholder="Ex : D:/Jeux ou C:/Games"
								onkeydown={(e) => {
									if (e.key === 'Enter') confirmAddFolder();
									if (e.key === 'Escape') isAddingFolder = false;
								}}
							/>
							<button type="button" class="btn-sm" onclick={confirmAddFolder}>Ajouter</button>
							<button type="button" class="btn-sm secondary" onclick={() => (isAddingFolder = false)}>
								Annuler
							</button>
						</div>
					{/if}

					{#each gameFolders as folder, i}
						<!-- La clé SteamGridDB occupe la ligne 1, les dossiers commencent à 3. -->
						{@const rowIdx = 3 + i}
						<div
							class="setting-row folder-row"
							class:focused={focused && focusCol === 'content' && focusRow === rowIdx}
						>
							<div class="row-label">
								<span class="title">{folder}</span>
								<span class="desc">Dossier personnalisé actif</span>
							</div>
							<button
								type="button"
								class="btn-delete"
								onclick={() => onRemoveFolder(folder)}
							>
								Retirer
							</button>
						</div>
					{/each}
				</div>

			{:else if currentCategory.id === 'appearance'}
				<!-- Réglages d'apparence -->
				<div class="rows-list">
					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 0}
						onclick={() => {
							focusCol = 'content';
							focusRow = 0;
							executeContentAction();
						}}
					>
						<div class="row-label">
							<span class="title">Disposition des touches</span>
							<span class="desc">Style des icônes de la manette dans l’interface et la barre d’aide</span>
						</div>
						<span class="badge-layout">
							{buttonLayout === 'ps5' ? 'PlayStation ▸' : buttonLayout === 'xbox' ? 'Xbox ▸' : 'Auto ▸'}
						</span>
					</button>

					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 1}
						onclick={() => {
							focusCol = 'content';
							focusRow = 1;
							executeContentAction();
						}}
					>
						<div class="row-label">
							<span class="title">Vidéo d'introduction</span>
							<span class="desc">Jouée au lancement de la console</span>
						</div>
						<span class="badge-layout">{bootVideoName} ▸</span>
					</button>

					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 2}
						onclick={() => {
							focusCol = 'content';
							focusRow = 2;
							executeContentAction();
						}}
					>
						<div class="row-label">
							<span class="title">Jouer au démarrage</span>
							<span class="desc">Passe directement à l'accueil si désactivé</span>
						</div>
						<span class="badge-layout">{bootVideoEnabled ? 'Oui ▸' : 'Non ▸'}</span>
					</button>

					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 3}
						onclick={() => {
							focusCol = 'content';
							focusRow = 3;
							executeContentAction();
						}}
					>
						<div class="row-label">
							<span class="title">Écran de veille</span>
							<span class="desc">Artworks de la bibliothèque après un moment sans rien toucher</span>
						</div>
						<span class="badge-layout">{screensaverLabel} ▸</span>
					</button>

					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 4}
						onclick={() => {
							focusCol = 'content';
							focusRow = 4;
							executeContentAction();
						}}
					>
						<div class="row-label">
							<span class="title">Ordre de l'accueil</span>
							<span class="desc">Les jeux auxquels tu as joué en dernier d'abord, ou par titre</span>
						</div>
						<span class="badge-layout">{homeOrderLabel} ▸</span>
					</button>
				</div>

			{:else if currentCategory.id === 'audio'}
				<div class="rows-list">
					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 0}
						onclick={() => {
							focusCol = 'content';
							focusRow = 0;
							executeContentAction();
						}}
					>
						<div class="row-label">
							<span class="title">Sons de l'interface</span>
							<span class="desc">Petits sons de navigation, de validation et de lancement</span>
						</div>
						<span class="badge-layout">{soundEnabled ? 'Oui ▸' : 'Non ▸'}</span>
					</button>

					{#each VOLUMES as entry, i (entry.key)}
						{@const value = volumes[entry.key]}
						<button
							type="button"
							class="setting-row"
							class:focused={focused && focusCol === 'content' && focusRow === i + 1}
							class:muted={!soundEnabled && entry.key !== 'volume_video'}
							onclick={() => {
								focusCol = 'content';
								focusRow = i + 1;
								executeContentAction();
							}}
						>
							<div class="row-label">
								<span class="title">{entry.title}</span>
								<span class="desc">{entry.desc}</span>
							</div>
							<span class="volume">
								<span class="arrow">◂</span>
								<span class="bar"><span class="fill" style="width: {value}%"></span></span>
								<span class="percent">{value} %</span>
								<span class="arrow">▸</span>
							</span>
						</button>
					{/each}
				</div>

			{:else if currentCategory.id === 'system'}
				<div class="rows-list">
					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 0}
						onclick={() => {
							focusCol = 'content';
							focusRow = 0;
							onToggleFullscreen?.();
						}}
					>
						<div class="row-label">
							<span class="title">Affichage</span>
							<span class="desc">Plein écran sans bordure, ou fenêtre avec sa barre de titre (F11)</span>
						</div>
						<span class="badge-layout">{fullscreen ? 'Plein écran ▸' : 'Fenêtre ▸'}</span>
					</button>
				</div>
			{/if}
		</div>
	</main>

	<!-- Clavier virtuel console pour modification du pseudo -->
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
		grid-template-columns: 280px 1fr;
		gap: 40px;
		height: 100%;
		padding: 0 var(--safe-x);
		animation: fade-in 220ms var(--ease);
	}

	/* Colonne de gauche */
	.sidebar {
		display: flex;
		flex-direction: column;
		gap: 24px;
		padding-top: 10px;
	}

	.page-title {
		margin: 0;
		font-size: clamp(28px, 2.5vw, 42px);
		font-weight: 800;
		color: var(--text);
	}

	.categories {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	.cat-btn {
		display: flex;
		align-items: center;
		gap: 16px;
		padding: 14px 20px;
		border-radius: var(--radius);
		background: var(--surface);
		border: 2px solid transparent;
		cursor: pointer;
		transition:
			transform var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease),
			border-color var(--fast) var(--ease),
			background var(--fast) var(--ease);
		text-align: left;
	}

	.cat-btn.active {
		background: var(--surface-strong);
		border-color: rgba(255, 255, 255, 0.16);
	}

	/* Hover & focus avec le même contour vert que les tuiles classiques */
	.cat-btn:hover,
	.cat-btn.focused {
		border-color: var(--accent);
		background: rgba(34, 211, 102, 0.08);
		transform: translateX(6px);
		outline: 3px solid var(--accent);
		box-shadow:
			0 0 34px 6px var(--accent-soft),
			0 12px 30px rgba(0, 0, 0, 0.5);
	}

	.cat-icon img {
		width: 24px;
		height: 24px;
		opacity: 0.8;
		transition: opacity 150ms var(--ease), filter 150ms var(--ease);
	}

	.cat-btn.active .cat-icon img,
	.cat-btn:hover .cat-icon img,
	.cat-btn.focused .cat-icon img {
		opacity: 1;
	}

	.cat-btn:hover .cat-icon img,
	.cat-btn.focused .cat-icon img {
		filter: drop-shadow(0 0 6px var(--accent-soft));
	}

	.cat-label {
		font-size: 18px;
		font-weight: 600;
		color: var(--text);
	}

	/* Volet de droite */
	.panel {
		display: flex;
		flex-direction: column;
		gap: 24px;
		padding: 30px 40px;
		border-radius: calc(var(--radius) * 1.5);
		background: rgba(14, 18, 26, 0.65);
		backdrop-filter: blur(20px);
		border: 1px solid var(--border);
		overflow-y: auto;
		max-height: calc(100vh - 170px);
	}

	.panel-header h2 {
		margin: 0 0 6px;
		font-size: 26px;
		font-weight: 700;
	}

	.panel-hint {
		margin: 0;
		font-size: 15px;
		color: var(--text-dim);
	}

	.panel-body {
		display: flex;
		flex-direction: column;
		gap: 20px;
	}

	/* Lignes de réglages */
	.rows-list {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}

	.setting-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 18px 24px;
		border-radius: var(--radius);
		background: var(--surface);
		border: 2px solid transparent;
		cursor: pointer;
		transition:
			transform var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease),
			border-color var(--fast) var(--ease),
			background var(--fast) var(--ease);
		text-align: left;
	}

	/* Hover & focus avec le contour vert des tuiles classiques */
	.setting-row:hover,
	.setting-row.focused {
		border-color: var(--accent);
		background: rgba(34, 211, 102, 0.08);
		transform: translateX(6px);
		outline: 3px solid var(--accent);
		box-shadow:
			0 0 34px 6px var(--accent-soft),
			0 12px 30px rgba(0, 0, 0, 0.5);
	}

	.row-label {
		display: flex;
		flex-direction: column;
		gap: 4px;
	}

	.row-label .title {
		font-size: 17px;
		font-weight: 600;
		color: var(--text);
	}

	.row-label .desc {
		font-size: 13px;
		color: var(--text-dim);
	}

	.action-tag {
		font-size: 15px;
		font-weight: 600;
		color: var(--text-dim);
		transition: color 150ms var(--ease);
	}

	.setting-row:hover .action-tag,
	.setting-row.focused .action-tag {
		color: var(--accent);
	}

	.badge-layout {
		padding: 6px 14px;
		border-radius: 8px;
		background: var(--surface-strong);
		font-size: 15px;
		font-weight: 700;
		color: #ffffff;
		border: 1px solid rgba(255, 255, 255, 0.12);
	}

	/* Carte de détection de jeux (recherche) - Style sobre et élégant */
	.hero-action-card {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 20px;
		padding: 24px 28px;
		border-radius: var(--radius);
		background: var(--surface-strong);
		border: 2px solid rgba(255, 255, 255, 0.1);
		transition: all 180ms var(--ease);
	}

	.hero-action-card:hover {
		border-color: rgba(34, 211, 102, 0.5);
		box-shadow: 0 0 28px var(--accent-soft);
	}

	.hero-info {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.hero-title-row {
		display: flex;
		align-items: center;
		gap: 12px;
	}

	.hero-icon {
		width: 22px;
		height: 22px;
		opacity: 0.85;
	}

	.hero-title {
		font-size: 20px;
		font-weight: 700;
		color: var(--text);
	}

	.hero-desc {
		font-size: 14px;
		color: var(--text-dim);
		max-width: 520px;
		line-height: 1.4;
	}

	.btn-scan {
		padding: 14px 24px;
		border-radius: var(--radius);
		border: 2px solid rgba(255, 255, 255, 0.16);
		background: rgba(255, 255, 255, 0.08);
		color: var(--text);
		font-size: 16px;
		font-weight: 700;
		cursor: pointer;
		white-space: nowrap;
		transition:
			transform var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease),
			border-color var(--fast) var(--ease),
			background var(--fast) var(--ease);
	}

	.btn-scan:hover,
	.btn-scan.focused {
		background: rgba(34, 211, 102, 0.15);
		color: #ffffff;
		border-color: var(--accent);
		outline: 3px solid var(--accent);
		transform: scale(1.03);
		box-shadow:
			0 0 34px 6px var(--accent-soft),
			0 12px 30px rgba(0, 0, 0, 0.5);
	}

	.section-divider h3 {
		margin: 10px 0 0;
		font-size: 17px;
		font-weight: 600;
		color: var(--text-dim);
		text-transform: uppercase;
		letter-spacing: 1px;
	}

	.folder-row {
		cursor: default;
	}

	.btn-delete {
		padding: 6px 14px;
		border-radius: 8px;
		background: rgba(255, 60, 60, 0.2);
		color: #ff6e6e;
		font-size: 13px;
		font-weight: 600;
		cursor: pointer;
		transition: all 150ms var(--ease);
	}

	.btn-delete:hover {
		background: rgba(255, 60, 60, 0.35);
	}

	.folder-input-box {
		display: flex;
		gap: 10px;
		align-items: center;
		padding: 10px 14px;
		background: var(--surface-strong);
		border-radius: var(--radius);
		border: 1px solid rgba(255, 255, 255, 0.1);
	}

	.folder-input {
		flex: 1;
		padding: 10px 14px;
		border-radius: 8px;
		border: 1px solid rgba(255, 255, 255, 0.2);
		background: rgba(0, 0, 0, 0.4);
		color: #fff;
		font-size: 16px;
		outline: none;
	}

	.btn-sm {
		padding: 10px 18px;
		border-radius: 8px;
		border: 2px solid rgba(255, 255, 255, 0.2);
		background: rgba(255, 255, 255, 0.12);
		color: #ffffff;
		font-weight: 700;
		cursor: pointer;
		transition: all 150ms var(--ease);
	}

	.btn-sm:hover,
	.btn-sm:focus-visible {
		background: rgba(34, 211, 102, 0.15);
		color: #ffffff;
		border-color: var(--accent);
		outline: 3px solid var(--accent);
		box-shadow: 0 0 24px 4px var(--accent-soft);
	}

	.btn-sm.secondary {
		background: var(--surface);
		color: var(--text-dim);
		border-color: transparent;
	}

	/* Jauge de volume : gauche / droite la règlent par pas de 10 %. */
	.volume {
		display: flex;
		align-items: center;
		gap: 12px;
		font-size: 17px;
		font-weight: 700;
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
		min-width: 4ch;
		text-align: right;
		font-variant-numeric: tabular-nums;
	}

	.arrow {
		color: var(--text-dim);
		opacity: 0;
		transition: opacity var(--fast) var(--ease);
	}

	/* Les flèches n'apparaissent que sur la ligne sélectionnée : c'est là que
	   gauche / droite agissent. */
	.setting-row.focused .arrow {
		opacity: 1;
	}

	/* Sons coupés : leurs volumes restent réglables, mais en retrait. */
	.setting-row.muted {
		opacity: 0.5;
	}

	@keyframes fade-in {
		from { opacity: 0; transform: translateY(6px); }
		to { opacity: 1; transform: translateY(0); }
	}
</style>
