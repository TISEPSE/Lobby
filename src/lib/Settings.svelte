<script lang="ts">
	import { onMount } from 'svelte';
	import type { Action } from './gamepad';
	import VirtualKeyboard from './VirtualKeyboard.svelte';

	let {
		focused = true,
		profileName = 'Joueur',
		avatar = '',
		gamesCount = 0,
		favoriteCount = 0,
		totalPlaytime = '0 min',
		gameFolders = [],
		buttonLayout = 'ps5',
		bootVideo = '',
		bootVideoEnabled = true,
		onBack,
		onReturnToHub = onBack,
		onOpenAvatarPicker,
		onOpenScan,
		onChangeName,
		onAddFolder,
		onRemoveFolder,
		onChangeLayout,
		onCycleBootVideo,
		onToggleBootVideo,
	}: {
		focused?: boolean;
		profileName: string;
		avatar: string;
		gamesCount: number;
		favoriteCount: number;
		totalPlaytime: string;
		gameFolders: string[];
		buttonLayout: string;
		bootVideo?: string;
		bootVideoEnabled?: boolean;
		onBack: () => void;
		onReturnToHub?: () => void;
		onOpenAvatarPicker: () => void;
		onOpenScan: () => void;
		onChangeName: (name: string) => void;
		onAddFolder: (path: string) => void;
		onRemoveFolder: (path: string) => void;
		onChangeLayout: (layout: string) => void;
		onCycleBootVideo?: () => void;
		onToggleBootVideo?: () => void;
	} = $props();

	type CategoryId = 'profile' | 'games' | 'appearance' | 'system';

	interface Category {
		id: CategoryId;
		label: string;
		icon: string;
		hint: string;
	}

	const CATEGORIES: Category[] = [
		{
			id: 'profile',
			label: 'Profil',
			icon: 'user',
			hint: 'Ton pseudo et ta photo, affichés en haut de l’interface.',
		},
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
			id: 'system',
			label: 'Système',
			icon: 'settings',
			hint: 'État et télémétrie de la console.',
		},
	];

	let activeCatIndex = $state(0);
	let focusCol = $state<'categories' | 'content'>('categories');
	let focusRow = $state(0);

	let isKeyboardOpen = $state(false);
	let keyboardComponent = $state<any>(null);

	let isAddingFolder = $state(false);
	let newFolderInput = $state('');

	const currentCategory = $derived(CATEGORIES[activeCatIndex]);

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
			case 'profile':
				return 2; // [0: modifier pseudo, 1: changer photo]
			case 'games':
				return 2 + gameFolders.length; // [0: scanner, 1: ajouter dossier, 2..N: dossiers]
			case 'appearance':
				return 3; // [0: touches, 1: vidéo d'intro, 2: jouer au démarrage]
			case 'system':
				return 0;
			default:
				return 0;
		}
	});

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
				if (activeCatIndex === 0) {
					onReturnToHub?.();
				} else {
					activeCatIndex = Math.max(0, activeCatIndex - 1);
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
			} else if (action === 'left' || action === 'cancel') {
				focusCol = 'categories';
			} else if (action === 'accept') {
				executeContentAction();
			}
		}
	}

	function executeContentAction() {
		const cat = currentCategory.id;
		if (cat === 'profile') {
			if (focusRow === 0) {
				isKeyboardOpen = true;
			} else if (focusRow === 1) {
				onOpenAvatarPicker();
			}
		} else if (cat === 'games') {
			if (focusRow === 0) {
				onOpenScan();
			} else if (focusRow === 1) {
				newFolderInput = 'D:/Jeux';
				isAddingFolder = true;
			} else {
				// Supprimer le dossier
				const folderIdx = focusRow - 2;
				if (folderIdx >= 0 && folderIdx < gameFolders.length) {
					onRemoveFolder(gameFolders[folderIdx]);
					focusRow = Math.max(1, focusRow - 1);
				}
			}
		} else if (cat === 'appearance') {
			if (focusRow === 0) {
				const next = buttonLayout === 'ps5' ? 'xbox' : buttonLayout === 'xbox' ? 'auto' : 'ps5';
				onChangeLayout(next);
			} else if (focusRow === 1) {
				onCycleBootVideo?.();
			} else if (focusRow === 2) {
				onToggleBootVideo?.();
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
			{#if currentCategory.id === 'profile'}
				<!-- Carte de Profil Joueur -->
				<div class="profile-card">
					<button
						type="button"
						class="profile-avatar-btn"
						onclick={onOpenAvatarPicker}
						title="Changer de photo de profil"
					>
						<div class="big-avatar">
							{#if avatar}
								<img src={avatar} alt="" class="avatar-img" />
							{:else}
								<span class="initial">{profileName.charAt(0).toUpperCase() || 'J'}</span>
							{/if}
						</div>
					</button>

					<div class="profile-info">
						<div class="profile-name">{profileName}</div>

						<div class="stats-row">
							<div class="stat-pill">
								<strong>{gamesCount}</strong> jeux
							</div>
							<div class="stat-pill">
								<strong>{favoriteCount}</strong> favoris
							</div>
							<div class="stat-pill">
								<strong>{totalPlaytime}</strong> joués
							</div>
						</div>
					</div>
				</div>

				<!-- Actions profil -->
				<div class="rows-list">
					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 0}
						onclick={() => {
							focusCol = 'content';
							focusRow = 0;
							isKeyboardOpen = true;
						}}
					>
						<div class="row-label">
							<span class="title">Modifier le pseudo</span>
							<span class="desc">Personnaliser le nom affiché sur la console</span>
						</div>
					</button>

					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 1}
						onclick={() => {
							focusCol = 'content';
							focusRow = 1;
							onOpenAvatarPicker();
						}}
					>
						<div class="row-label">
							<span class="title">Changer de photo de profil</span>
							<span class="desc">Sélectionner un avatar parmi les choix disponibles</span>
						</div>
					</button>
				</div>

			{:else if currentCategory.id === 'games'}
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
					<h3>Dossiers surveillés</h3>
				</div>

				<div class="rows-list">
					<button
						type="button"
						class="setting-row"
						class:focused={focused && focusCol === 'content' && focusRow === 1}
						onclick={() => {
							focusCol = 'content';
							focusRow = 1;
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
						{@const rowIdx = 2 + i}
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
				</div>

			{:else if currentCategory.id === 'system'}
				<!-- Télémétrie Système -->
				<div class="system-grid">
					<div class="sys-card">
						<span class="sys-title">Plateforme</span>
						<span class="sys-val">Windows (WebView2)</span>
					</div>
					<div class="sys-card">
						<span class="sys-title">Moteur de rendu</span>
						<span class="sys-val">Tauri 2 + Svelte 5</span>
					</div>
					<div class="sys-card">
						<span class="sys-title">Navigation</span>
						<span class="sys-val">100% Manette / Clavier</span>
					</div>
					<div class="sys-card">
						<span class="sys-title">Stockage Jeux</span>
						<span class="sys-val">Lecteurs C: & D:</span>
					</div>
				</div>
			{/if}
		</div>
	</main>

	<!-- Clavier virtuel console pour modification du pseudo -->
	<VirtualKeyboard
		open={isKeyboardOpen}
		title="Modifier le pseudo"
		subtitle="Saisis ton nom avec la manette ou le clavier"
		initialValue={profileName}
		maxLength={24}
		onConfirm={(name) => {
			if (name.trim()) onChangeName(name.trim());
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

	/* Carte profil */
	.profile-card {
		display: flex;
		align-items: center;
		gap: 28px;
		padding: 24px 30px;
		border-radius: var(--radius);
		background: var(--surface-strong);
		border: 1px solid rgba(255, 255, 255, 0.1);
	}

	.profile-avatar-btn {
		background: none;
		border: none;
		padding: 0;
		cursor: pointer;
		outline: none;
		border-radius: 50%;
	}

	.profile-avatar-btn:hover .big-avatar,
	.profile-avatar-btn:focus-visible .big-avatar {
		border-color: var(--accent);
		transform: scale(1.05);
		box-shadow: 0 0 24px 4px var(--accent-soft);
	}

	.big-avatar {
		display: grid;
		place-items: center;
		width: 96px;
		height: 96px;
		border-radius: 50%;
		background: var(--surface);
		border: 2px solid rgba(255, 255, 255, 0.2);
		overflow: hidden;
		transition: transform var(--fast) var(--ease), border-color var(--fast) var(--ease), box-shadow var(--fast) var(--ease);
	}

	.avatar-img {
		width: 68px;
		height: 68px;
		object-fit: contain;
	}

	.big-avatar .initial {
		font-size: 44px;
		font-weight: 800;
		color: #ffffff;
	}

	.profile-info {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}

	.profile-name {
		font-size: 32px;
		font-weight: 800;
		color: var(--text);
		letter-spacing: -0.5px;
	}

	.stats-row {
		display: flex;
		gap: 12px;
	}

	.stat-pill {
		padding: 6px 14px;
		border-radius: 999px;
		background: var(--surface);
		font-size: 14px;
		color: var(--text-dim);
	}

	.stat-pill strong {
		color: var(--text);
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

	/* Grille système */
	.system-grid {
		display: grid;
		grid-template-columns: repeat(2, 1fr);
		gap: 16px;
	}

	.sys-card {
		display: flex;
		flex-direction: column;
		gap: 8px;
		padding: 20px;
		border-radius: var(--radius);
		background: var(--surface);
		border: 2px solid rgba(255, 255, 255, 0.08);
		transition: all 180ms var(--ease);
	}

	.sys-card:hover {
		border-color: var(--accent);
		outline: 3px solid var(--accent);
		box-shadow:
			0 0 30px 6px var(--accent-soft),
			0 12px 30px rgba(0, 0, 0, 0.5);
		transform: translateY(-2px);
	}

	.sys-title {
		font-size: 14px;
		color: var(--text-dim);
		text-transform: uppercase;
		letter-spacing: 0.5px;
	}

	.sys-val {
		font-size: 18px;
		font-weight: 700;
		color: var(--text);
	}

	@keyframes fade-in {
		from { opacity: 0; transform: translateY(6px); }
		to { opacity: 1; transform: translateY(0); }
	}
</style>
