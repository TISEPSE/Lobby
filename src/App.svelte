<script lang="ts">
	import { onMount } from 'svelte';
	import Backdrop from './lib/Backdrop.svelte';
	import TopBar from './lib/TopBar.svelte';
	import Home from './lib/Home.svelte';
	import Library from './lib/Library.svelte';
	import SearchModal from './lib/SearchModal.svelte';
	import VirtualKeyboard from './lib/VirtualKeyboard.svelte';
	import Detail from './lib/Detail.svelte';
	import HelpBar from './lib/HelpBar.svelte';
	import PowerMenu from './lib/PowerMenu.svelte';
	import DownloadBar from './lib/DownloadBar.svelte';
	import ScreenSaver from './lib/ScreenSaver.svelte';
	import { watchDownloads, downloads } from './lib/downloads.svelte.js';
	import { play as playSound, setSoundEnabled as applySound, preloadSounds, setVolumes } from './lib/sound';
	import Settings from './lib/Settings.svelte';
	import Stats from './lib/Stats.svelte';
	import Profile from './lib/Profile.svelte';
	import { demoLog, formatMinutes, summarize, type Period } from './lib/stats';
	import AvatarPicker from './lib/AvatarPicker.svelte';
	import ScanResultsModal from './lib/ScanResultsModal.svelte';
	import ArtPicker from './lib/ArtPicker.svelte';
	import OptionsMenu from './lib/OptionsMenu.svelte';
	import { runPower, POWER_ENTRIES, type PowerAction } from './lib/power';
	import { updateGame, verifyGame, uninstallGame, installGame, installEpicGame } from './lib/steamActions';
	import { artwork, details, heroFor, mediaOf, initArtStore, DEMO_MEDIA } from './lib/steam.svelte.js';
	import MediaViewer from './lib/MediaViewer.svelte';
	import PadToast from './lib/PadToast.svelte';
	import LaunchOverlay from './lib/LaunchOverlay.svelte';
	import FilePicker from './lib/FilePicker.svelte';
	import { remember } from './lib/notices.svelte.js';
	import type { TileAction, Game, Section, Outcome } from './lib/types';
	import { allowInBackground, listen, onGameCombo, padCount, type Action } from './lib/gamepad';
	import { endSession, session, sessionPid, setSessionWindow } from './lib/session.svelte.js';
	import type { GlyphButton } from './lib/glyphs';
	import {
		forgetSteamLibrary,
		initSteamAccount,
		initSteamLibrary,
		loginSteamLibrary,
		steamAccount,
		steamLibrary,
	} from './lib/steamAccount.svelte.js';
	import {
		epicAccount,
		initEpicAccount,
		loginEpic,
		logoutEpic,
		refreshEpicAccount,
	} from './lib/epicAccount.svelte.js';
	import { play } from './lib/launcher';
	import {
		games,
		view,
		toggleFavorite,
		isFavorite,
		playtimeText,
		initLibrary,
		lastPlayedGame,
		homeView,
		playtimeOf,
		HOME_ORDER_LABELS,
		addGames,
		syncLibrary,
		setGameExecutable,
		FILTERS,
		SORTS,
		uninstalledSteamGames,
		uninstalledEpicGames,
		stats,
		sessions,
		type Filter,
		type Sort,
	} from './lib/library.svelte.js';
	import {
		settings,
		initSettings,
		setProfileName,
		setAvatar,
		setButtonLayout,
		setSoundEnabled as saveSoundEnabled,
		setScreensaverMinutes,
		setHomeOrder,
		setLibraryView,
		stepVolume,
		setSteamGridKey,
		addGameFolder,
		removeGameFolder,
	} from './lib/settings.svelte.js';

	const SECTIONS: Section[] = ['home', 'library', 'settings', 'profile'];
	const COLUMNS = 8;

	/* Outil de développement, comme le `--capture` de la version Godot :
	   `?screen=detail&index=3` ouvre directement un écran pour la capture. */
	const params = new URLSearchParams(location.search);

	const wanted = params.get('screen');
	const wantedIndex = Number(params.get('index') ?? 0);

	/** Section affichée, et si la sélection est montée sur la barre du haut. */
	let section = $state<Section>(
		wanted === 'library' || wanted === 'settings' || wanted === 'profile'
			? wanted
			: wanted === 'stats'
				? 'profile'
				: 'home'
	);
	/**
	 * Statistiques : une sous-page des Réglages (Système), posée par-dessus. Les
	 * réglages restent montés dessous et gardent leur sélection pour le retour.
	 */
	let statsOpen = $state(wanted === 'stats');
	/** Saisie du pseudo, ouverte depuis le Profil (A sur le pseudo). */
	let nameKeyboardOpen = $state(false);
	let nameKeyboard: { handleAction: (action: Action) => void } | null = $state(null);
	/** Fiche : boutons de la présentation, ou grille des médias en dessous. */
	let detailZone = $state<'actions' | 'media'>(params.get('media') ? 'media' : 'actions');
	let mediaIndex = $state(Number(params.get('slide') ?? 0));
	/** Visionneuse ouverte ; `?viewer=1` l'ouvre (capture, avec `media=demo`). */
	let viewerOpen = $state(params.get('viewer') === '1');
	let viewerComponent: { handleAction: (action: Action) => void; poke: () => void } | null = $state(null);
	/** Plein écran sans bordure (mode console) ou fenêtre classique. */
	let fullscreen = $state(true);

	/** F11 ou Réglages → Système : la porte de sortie vers une fenêtre normale. */
	async function toggleFullscreen() {
		const tauri = (window as any).__TAURI_INTERNALS__;
		if (!tauri) return;
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			fullscreen = await invoke<boolean>('toggle_fullscreen');
			notify(fullscreen ? 'Plein écran.' : 'Fenêtre (F11 pour revenir en plein écran).');
		} catch (e) {
			notify(`Impossible de changer d'affichage : ${e}`, false);
		}
	}
	/** Jeu ouvert en fiche détaillée. Null : on est sur la section courante. */
	let opened = $state<Game | null>(wanted === 'detail' ? (games[wantedIndex] ?? null) : null);

	/**
	 * -1 : la carte « Reprendre », en tête de l'accueil. On démarre dessus : le
	 * dernier jeu se relance en un appui, dès l'allumage.
	 */
	/** Accueil : la rangée de jeux, ou les panneaux du bas (`?zone=panels`). */
	let homeZone = $state<'row' | 'panels'>(params.get('zone') === 'panels' ? 'panels' : 'row');
	let panelIndex = $state(Number(params.get('panel') ?? 0));
	let homeIndex = $state(params.has('index') ? wantedIndex : -1);
	/** La bibliothèque enregistrée est chargée : on sait s'il y a un jeu à reprendre. */
	let libraryReady = $state(false);

	let libraryIndex = $state(wanted === 'library' ? wantedIndex : 0);
	/**
	 * Recherche : une fenêtre (clavier virtuel + jeux), plus une page. Y
	 * l'ouvre de partout ; `?search=1` l'ouvre directement (capture).
	 */
	let searchOpen = $state(params.get('search') === '1' || wanted === 'search');
	let searchComponent: {
		handleAction: (action: Action) => void;
		selectionKey?: () => string | null;
	} | null = $state(null);

	/**
	 * Écran de veille : on garde l'instant de la dernière action plutôt qu'un
	 * compte à rebours à annuler et relancer sans arrêt.
	 */
	let saverOn = $state(params.get('saver') === '1');
	let lastInput = $state(Date.now());

	/**
	 * Filtre et tri de la bibliothèque : ceux de la dernière session (réglages),
	 * et chaque changement y est enregistré.
	 */
	const filter = $derived<Filter>(
		FILTERS.includes(settings.library_filter as Filter) ? (settings.library_filter as Filter) : 'all'
	);
	const sort = $derived<Sort>(
		SORTS.includes(settings.library_sort as Sort) ? (settings.library_sort as Sort) : 'title'
	);

	/** Volume des bandes-annonces : le leur, multiplié par le général. */
	const videoVolume = $derived((settings.volume_master / 100) * (settings.volume_video / 100));

	// Les volumes des sons suivent les réglages, dès le chargement et à chaque changement.
	$effect(() => {
		setVolumes({
			master: settings.volume_master / 100,
			menu: settings.volume_menu / 100,
			alerts: settings.volume_alerts / 100,
			launch: settings.volume_launch / 100,
		});
	});

	let clock = $state(formatClock());
	let pads = $state(0);
	let notice = $state('');
	/** Ton du bandeau : une erreur ne se lit pas comme une confirmation. */
	let noticeOk = $state(true);

	/** Bouton sélectionné sur une fiche : 0 = Jouer, 1 = Favori. */
	let detailButton = $state(0);
	/** Fenêtre d'alimentation : index sélectionné, et action en attente de confirmation. */
	let powerOpen = $state(params.get('power') === '1');
	/**
	 * Écran de lancement : le jeu qui démarre, tant que sa fenêtre n'est pas
	 * là. Capture : `?launch=demo` (jeu sélectionné), `&slow=1`.
	 */
	let launching = $state<Game | null>(null);
	let launchSlow = $state(params.get('slow') === '1');
	let launchTimers: ReturnType<typeof setTimeout>[] = [];
	let launchPoll: ReturnType<typeof setInterval> | null = null;
	/**
	 * Menu du jeu en cours, façon guide Xbox : View + Menu maintenus pendant
	 * la partie, ou X sur sa carte à l'accueil. Capture : `?gamemenu=1`.
	 */
	let gameMenuOpen = $state(params.get('gamemenu') === '1');
	let gameMenuIndex = $state(0);
	const GAME_MENU: TileAction[] = [
		{ id: 'resume', label: 'Revenir au jeu', icon: 'play' },
		{ id: 'quit', label: 'Quitter le jeu', icon: 'exit' },
		{ id: 'stay', label: "Rester sur l'accueil", icon: 'home' },
	];
	let powerIndex = $state(0);
	let powerPending = $state<PowerAction | null>((params.get('confirm') as PowerAction) ?? null);

	/** Menu d'options de la tuile sélectionnée, sur l'accueil. */
	/** Même menu, ouvert depuis une fiche : il n'y a pas de tuile à prolonger. */
	/**
	 * Menu d'options en fenêtre : sur une fiche, ou dans la bibliothèque (X sur
	 * une jaquette). `?options=detail` ou `?options=library` l'ouvrent (capture).
	 */
	let menuOptionsOpen = $state(params.get('options') === '1' || params.get('options') === 'detail' || params.get('options') === 'library');
	/** Bibliothèque : grille, ou boutons de l'en-tête (0 = Trier, 1 = Synchroniser). */
	let libraryZone = $state<'grid' | 'header'>(params.get('zone') === 'header' ? 'header' : 'grid');
	let headerIndex = $state(0);
	let optionsIndex = $state(0);

	/** Modales et scan */
	let avatarPickerOpen = $state(params.get('modal') === 'avatars');
	let scanModalOpen = $state(params.get('modal') === 'scan');
	/** Choix de l'affiche d'un jeu, ouvert depuis le menu d'options d'une tuile. */
	let artPickerOpen = $state(params.get('modal') === 'art');
	/** Jaquette de la tuile, ou image de fond : la fenêtre est la même. */
	let artPickerTarget = $state<'cover' | 'background'>(
		params.get('art') === 'background' ? 'background' : 'cover'
	);
	let isScanning = $state(false);
	let scannedCandidates = $state<Game[]>([]);

	let settingsComponent: {
		handleAction: (action: Action) => void;
		isKeyboardActive?: () => boolean;
		focusProfile?: () => void;
		checkSteamGridKey?: (key: string) => Promise<string>;
		selectionKey?: () => string | null;
	} | null = $state(null);
	let profileComponent: {
		handleAction: (action: Action) => void;
		selectionKey?: () => string;
	} | null = $state(null);
	function useSteamProfile() {
		if (!steamAccount.persona) return;
		setProfileName(steamAccount.persona);
		if (steamAccount.avatar) setAvatar(steamAccount.avatar);
		notify(`Profil Steam repris : ${steamAccount.persona}.`);
	}

	let statsComponent: {
		handleAction: (action: Action) => void;
		selectionKey?: () => string;
	} | null = $state(null);
	let avatarPickerComponent: { handleAction: (action: string) => void } | null = $state(null);
	let scanModalComponent: { handleAction: (action: string) => void } | null = $state(null);
	let artPickerComponent: { handleAction: (action: Action) => void } | null = $state(null);
	/** Explorateur de fichiers : choisir l'exécutable d'un jeu à la main. */
	let filePickerOpen = $state(params.get('modal') === 'files');
	let filePickerComponent: { handleAction: (action: Action) => void; selectionKey: () => string } | null =
		$state(null);

	// Outil de capture : `?stats=demo` remplit le journal de parties fictives,
	// jamais enregistrées, pour juger l'écran dans un navigateur.
	if (params.get('stats') === 'demo' && sessions.length === 0) sessions.push(...demoLog(games));

	/**
	 * Bibliothèque complète : les jeux installés, plus les jeux Steam possédés
	 * mais pas installés (connexion Steam), mélangés dans « Tous ».
	 */
	const allGames = $derived([
		...games,
		...uninstalledSteamGames(steamAccount.owned),
		...uninstalledEpicGames(epicAccount.library),
	]);
	const libraryGames = $derived(view(filter, sort, allGames));
	/** Le jeu en cours, lancé depuis Lobby. `?running=demo` fait comme si la carte tournait. */
	const runningGame = $derived(
		session.id ? (games.find((game) => game.id === session.id) ?? null) : null
	);
	const isRunning = $derived(
		params.get('gamemenu') === '1' || params.get('running') === 'demo' || runningGame !== null
	);
	/** Dernier jeu lancé. `?resume=demo` en invente un, pour juger la carte dans un navigateur. */
	const resumeGame = $derived(
		params.get('resume') === 'demo' ? (games[1] ?? null) : (runningGame ?? lastPlayedGame())
	);

	/**
	 * Rangée d'accueil, dans l'ordre choisi (dernière partie d'abord par défaut).
	 * Le jeu de la carte « Reprendre » n'y figure pas une seconde fois.
	 */
	const homeGames = $derived(
		homeView(settings.home_order).filter((game) => game.id !== resumeGame?.id)
	);

	// Sans jeu à reprendre, la carte disparaît : la sélection passe à la première tuile.
	$effect(() => {
		if (libraryReady && homeIndex < 0 && !resumeGame) homeIndex = 0;
	});

	const selected = $derived(
		opened ??
			(section === 'library'
				? libraryGames[libraryIndex]
				: homeIndex < 0
						? (resumeGame ?? undefined)
						: homeGames[homeIndex])
	);

	/**
	 * Artwork de fond : celui de la fiche Steam, sinon celui téléchargé pour ce
	 * jeu, sinon celui du fichier de bibliothèque.
	 */
	const backdropSrc = $derived.by(() => {
		if (!selected) return '';
		// Le fichier local d'abord : c'est l'image de fond choisie pour ce jeu.
		return heroFor(selected);
	});

	/** Artworks disponibles pour la veille, sans doublon ni case vide. */
	const saverImages = $derived.by(() => {
		const seen = new Set<string>();
		for (const game of games) {
			const sheet = game.appid ? details[game.appid] : undefined;
			const src = sheet?.hero || artwork[game.id]?.hero || game.hero || '';
			if (src) seen.add(src);
		}
		return [...seen];
	});

	const favoriteCount = $derived(games.filter((g) => isFavorite(g.id)).length);
	const totalPlaytimeMinutes = $derived(
		games.reduce((acc, game) => acc + playtimeOf(game.id), 0)
	);
	const totalPlaytimeFormatted = $derived.by(() => {
		if (totalPlaytimeMinutes <= 0) return '0 min';
		if (totalPlaytimeMinutes < 60) return `${totalPlaytimeMinutes} min`;
		return `${Math.floor(totalPlaytimeMinutes / 60)} h ${String(totalPlaytimeMinutes % 60).padStart(2, '0')}`;
	});
	const alreadyKnownGameIds = $derived(new Set(games.map((g) => g.id)));

	function formatClock() {
		return new Date().toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
	}

	/**
	 * Changements différés par `startViewTransition` : l'état ne bouge qu'après
	 * coup, le compteur dit tout de suite qu'il va bouger (empreinte du son).
	 */
	let navTick = 0;

	function transition(change: () => void) {
		navTick++;
		if (!document.startViewTransition) {
			change();
			return;
		}
		document.startViewTransition(change);
	}

	function openDetail(game: Game | undefined) {
		if (!game) return;
		detailButton = 0;
		detailZone = 'actions';
		mediaIndex = 0;
		viewerOpen = false;
		transition(() => (opened = game));
	}

	function closeDetail() {
		transition(() => (opened = null));
	}

	function goToSection(next: Section) {
		if (next === section) return;
		homeZone = 'row';
		// Pas de `startViewTransition` ici : il photographiait toute la page,
		// dock flouté compris, et le fondu saccadait. Le dock reste en place,
		// seul le contenu entre en fondu (`.screen`).
		section = next;
		libraryIndex = 0;
		libraryZone = 'grid';
		// On revient toujours sur la section elle-même, pas sur une sous-page.
		statsOpen = false;
	}

	/**
	 * L1 / R1 : section précédente / suivante du dock. C'est le **seul** moyen
	 * d'y circuler — la sélection ne monte jamais sur le dock, elle reste dans
	 * le contenu. Pas de bouclage : au bout, on reste au bout.
	 */
	function stepSection(step: number) {
		const at = SECTIONS.indexOf(section);
		const next = SECTIONS[Math.min(SECTIONS.length - 1, Math.max(0, at + step))];
		// Un léger souffle dit qu'on change de section ; au bout du dock, rien.
		if (next !== section) playSound('section');
		opened = null;
		menuOptionsOpen = false;
		goToSection(next);
	}

	/**
	 * Accueil, panneaux du bas : gauche / droite entre eux, haut remonte à la
	 * rangée. A ouvre la bibliothèque, les statistiques, ou la fiche du jeu en
	 * cours de mise à jour.
	 */
	function handlePanels(action: Action) {
		if (action === 'up') homeZone = 'row';
		else if (action === 'left') panelIndex = Math.max(0, panelIndex - 1);
		else if (action === 'right') panelIndex = Math.min(2, panelIndex + 1);
		else if (action === 'accept') {
			if (panelIndex === 0) goToSection('library');
			else if (panelIndex === 1) {
				goToSection('profile');
				statsOpen = true;
			} else {
				const appid = downloads.list[0]?.appid;
				const game = appid ? games.find((g) => g.appid === appid) : undefined;
				if (game) openDetail(game);
			}
		}
	}

	function handleHome(action: Action) {
		if (homeZone === 'panels') return handlePanels(action);
		// Bas : les panneaux (lanceurs, semaine, mises à jour).
		if (action === 'down') {
			homeZone = 'panels';
			return;
		}
		// Aucun jeu (PC neuf) : A ouvre Réglages → Jeux, où se lance la détection.
		if (homeGames.length === 0 && !resumeGame) {
			if (action === 'accept') goToSection('settings');
			return;
		}
		if (action === 'left') homeIndex = Math.max(resumeGame ? -1 : 0, homeIndex - 1);
		else if (action === 'right') homeIndex = Math.min(homeGames.length - 1, homeIndex + 1);
		// La carte « Reprendre » lance directement : c'est tout son intérêt.
		else if (action === 'accept' && homeIndex < 0) launch();
		else if (action === 'accept') openDetail(homeGames[homeIndex]);
		// Le jeu tourne : X ouvre le menu du jeu, déjà sur « Quitter ».
		else if (action === 'options' && homeIndex < 0 && isRunning) openGameMenu(1);
		// X : les options du jeu, dans une fenêtre (comme la bibliothèque et la fiche).
		else if (action === 'options') {
			optionsIndex = 0;
			menuOptionsOpen = true;
		}
	}

	function handleLibrary(action: Action) {
		// En-tête : Trier et Synchroniser, de vrais boutons.
		if (libraryZone === 'header') {
			if (action === 'left') headerIndex = 0;
			else if (action === 'right') headerIndex = 1;
			else if (action === 'down') libraryZone = 'grid';
			else if (action === 'accept') {
				if (headerIndex === 0) cycleSort();
				else runSync();
			} else if (action === 'cancel') goToSection('home');
			return;
		}

		const total = libraryGames.length;
		const row = Math.floor(libraryIndex / COLUMNS);
		if (action === 'left') libraryIndex = Math.max(0, libraryIndex - 1);
		else if (action === 'right') libraryIndex = Math.min(total - 1, libraryIndex + 1);
		else if (action === 'down') {
			// Depuis la dernière rangée, descendre ne fait rien : ramener la
			// sélection sur la toute dernière tuile la faisait sauter en
			// diagonale, à l'autre bout de l'écran.
			const below = libraryIndex + COLUMNS;
			if (below < total) libraryIndex = below;
		} else if (action === 'up') {
			// Au-dessus de la première rangée : les boutons de l'en-tête.
			if (row > 0) libraryIndex = Math.max(0, libraryIndex - COLUMNS);
			else libraryZone = 'header';
		} else if (action === 'accept') openDetail(libraryGames[libraryIndex]);
		else if (action === 'options' && libraryGames[libraryIndex]) {
			// X : les options du jeu, comme sur l'accueil.
			optionsIndex = 0;
			menuOptionsOpen = true;
		} else if (action === 'view') cycleSort();
		else if (action === 'cancel') goToSection('home');
	}

	/** Critère de tri suivant ; la sélection repart du début. */
	function cycleSort() {
		setLibraryView(filter, SORTS[(SORTS.indexOf(sort) + 1) % SORTS.length]);
		libraryIndex = 0;
	}


	/** Y : la recherche, de partout. */
	function openSearch() {
		searchOpen = true;
	}

	/** Médias de la fiche ouverte : bandes-annonces puis captures. */
	const detailMedia = $derived(
		params.get('media') === 'demo'
			? DEMO_MEDIA
			: opened?.appid
				? mediaOf(details[opened.appid])
				: []
	);

	/**
	 * Visionneuse. Sur une capture : gauche / droite (ou L1 / R1) passent au
	 * média voisin. Sur une bande-annonce, c'est un lecteur : A lecture / pause,
	 * gauche / droite ±10 s (`VideoPlayer`), haut / bas le volume, L1 / R1 le
	 * média voisin. B referme.
	 */
	function handleViewer(action: Action) {
		const isVideo = detailMedia[mediaIndex]?.kind === 'video';
		const last = detailMedia.length - 1;
		if (action === 'cancel') viewerOpen = false;
		else if (action === 'prev' || (!isVideo && action === 'left')) mediaIndex = Math.max(0, mediaIndex - 1);
		else if (action === 'next' || (!isVideo && action === 'right')) mediaIndex = Math.min(last, mediaIndex + 1);
		else if (isVideo && (action === 'up' || action === 'down')) {
			// Le même volume que Réglages → Audio → Vidéos.
			stepVolume('volume_video', action === 'up' ? 10 : -10);
			viewerComponent?.poke();
		} else if (isVideo) viewerComponent?.handleAction(action);
	}

	/** Slider « Captures et vidéos », sous la présentation du jeu. */
	function handleMedia(action: Action) {
		const total = detailMedia.length;
		if (action === 'left') mediaIndex = Math.max(0, mediaIndex - 1);
		else if (action === 'right') mediaIndex = Math.min(total - 1, mediaIndex + 1);
		else if (action === 'up' || action === 'cancel') detailZone = 'actions';
		else if (action === 'accept' && total > 0) viewerOpen = true;
	}

	function handleDetail(action: Action) {
		if (!opened) return;
		if (menuOptionsOpen) return handleOptions(action);
		if (viewerOpen) return handleViewer(action);
		if (detailZone === 'media') return handleMedia(action);

		if (action === 'down' && detailMedia.length > 0) {
			detailZone = 'media';
			return;
		}
		if (action === 'cancel') closeDetail();
		else if (action === 'left') detailButton = Math.max(0, detailButton - 1);
		else if (action === 'right') detailButton = Math.min(2, detailButton + 1);
		else if (action === 'accept') {
			if (detailButton === 0) launch();
			// « Détails du jeu » : la page « Captures et vidéos » et « Plus sur… ».
			else if (detailButton === 1) detailZone = 'media';
			else openDetailOptions();
		} else if (action === 'options') openDetailOptions();
	}

	function openDetailOptions() {
		optionsIndex = 0;
		menuOptionsOpen = true;
	}

	function switchFavorite() {
		if (!opened) return;
		toggleFavorite(opened.id);
		notify(isFavorite(opened.id) ? 'Ajouté aux favoris.' : 'Retiré des favoris.');
	}

	async function handlePower(action: Action) {
		const count = powerPending ? 2 : POWER_ENTRIES.length;
		if (action === 'left' || action === 'up') powerIndex = Math.max(0, powerIndex - 1);
		else if (action === 'right' || action === 'down') powerIndex = Math.min(count - 1, powerIndex + 1);
		else if (action === 'cancel') {
			if (powerPending) {
				powerPending = null;
				powerIndex = 0;
			} else powerOpen = false;
		} else if (action === 'accept') {
			if (powerPending) {
				const chosen = powerPending;
				powerPending = null;
				powerIndex = 0;
				powerOpen = false;
				if (chosen) notify(await runPower(chosen));
				return;
			}
			const entry = POWER_ENTRIES[powerIndex];
			if (entry.confirm) {
				powerPending = entry.action;
				powerIndex = 0;
			} else {
				powerOpen = false;
				notify(await runPower(entry.action));
			}
		}
	}

	function openPower() {
		powerOpen = true;
		powerIndex = 0;
		powerPending = null;
	}

	/** Synchronisation en cours (bouton X de la bibliothèque). */
	let syncing = $state(false);

	/**
	 * Resynchronise la bibliothèque avec le disque : nouveaux jeux ajoutés,
	 * dossiers déplacés suivis, jeux disparus retirés. Sans fenêtre de
	 * validation — c'est un geste rapide, le bilan s'affiche en bas.
	 */
	/**
	 * Rescanne les jeux installés (Steam, Epic, dossiers, raccourcis) et met la
	 * bibliothèque à jour sans validation : nouveaux ajoutés, déplacés suivis,
	 * désinstallés retirés. Sert au bouton « Synchroniser » et au démarrage.
	 * Rend le bilan lisible (« 2 ajoutés · 1 retiré »), vide si rien n'a bougé.
	 */
	async function scanAndSync(): Promise<string> {
		const { invoke } = await import('@tauri-apps/api/core');
		const scanned = await invoke<Game[]>('scan_installed_games', {
			customFolders: settings.game_folders,
		});
		const report = await syncLibrary(scanned, (paths) => invoke<boolean[]>('paths_exist', { paths }));
		return [
			report.added && `${report.added} ajouté${report.added > 1 ? 's' : ''}`,
			report.updated && `${report.updated} mis à jour`,
			report.removed && `${report.removed} retiré${report.removed > 1 ? 's' : ''}`,
		]
			.filter(Boolean)
			.join(' · ');
	}

	async function runSync() {
		if (syncing) return;
		const tauri = (window as any).__TAURI_INTERNALS__;
		if (!tauri) return notify('Hors application : rien à synchroniser.');
		syncing = true;
		try {
			const changes = await scanAndSync();
			libraryIndex = 0;
			notify(changes ? `Bibliothèque synchronisée : ${changes}.` : 'Bibliothèque déjà à jour.');
		} catch (e) {
			notify(`Synchronisation impossible : ${e}`, false);
		} finally {
			syncing = false;
		}
	}

	/**
	 * Numéro du scan en cours. Fermer la fenêtre l'incrémente : un résultat
	 * qui arrive pour un ancien numéro est ignoré. C'est ce qui rend
	 * l'annulation instantanée — le scan Rust finit dans son coin, sans rien
	 * afficher.
	 */
	let scanTicket = 0;

	function closeScan() {
		scanTicket++;
		scanModalOpen = false;
		isScanning = false;
	}

	async function runGameScan() {
		const ticket = ++scanTicket;
		scanModalOpen = true;
		isScanning = true;
		scannedCandidates = [];
		const tauri = (window as any).__TAURI_INTERNALS__;
		if (tauri) {
			try {
				const { invoke } = await import('@tauri-apps/api/core');
				const results = await invoke<Game[]>('scan_installed_games', {
					customFolders: settings.game_folders,
				});
				if (ticket !== scanTicket) return;
				scannedCandidates = results;
			} catch (e) {
				if (ticket === scanTicket) notify(`Erreur pendant le scan : ${e}`, false);
			} finally {
				if (ticket === scanTicket) isScanning = false;
			}
		} else {
			// Mock pour développement dans navigateur
			setTimeout(() => {
				scannedCandidates = [
					{
						id: 'epic-sugar',
						title: 'Rocket League',
						cover: 'https://cdn.cloudflare.steamstatic.com/steam/apps/252950/library_600x900_2x.jpg',
						hero: 'https://cdn.cloudflare.steamstatic.com/steam/apps/252950/library_hero.jpg',
						logo: '',
						source: 'epic',
					},
					{
						id: 'scan-deadcells',
						title: 'Dead Cells',
						cover: 'https://cdn.cloudflare.steamstatic.com/steam/apps/588650/library_600x900_2x.jpg',
						hero: 'https://cdn.cloudflare.steamstatic.com/steam/apps/588650/library_hero.jpg',
						logo: '',
						source: 'folder',
					},
				];
				isScanning = false;
			}, 1000);
		}
	}

	function handleScanConfirm(chosen: Game[]) {
		const added = addGames(chosen);
		notify(`${added} jeu${added > 1 ? 'x ajoutés' : ' ajouté'} à la bibliothèque !`);
	}

	function handle(action: Action) {
		lastInput = Date.now();
		// La veille se dissipe sans rien déclencher derrière : on ne veut pas
		// lancer un jeu en voulant simplement réveiller l'écran.
		if (saverOn) {
			saverOn = false;
			return;
		}

		// Un seul endroit décide du son : les écrans n'ont pas à y penser.
		if (action === 'accept') playSound('accept');
		else if (action === 'cancel') playSound('cancel');

		// Une direction ne sonne que si la sélection a vraiment bougé : buter
		// contre le bord d'une rangée ou descendre depuis une tuile de l'accueil
		// ne doit rien faire entendre.
		const move = action === 'up' || action === 'down' || action === 'left' || action === 'right';
		const before = move ? selectionKey() : null;
		dispatch(action);
		if (move) {
			const after = selectionKey();
			if (before === null || after === null || before !== after) playSound('move');
		}
	}

	/**
	 * Empreinte de la sélection, comparée avant et après une direction. `null`
	 * quand une fenêtre ne sait pas la donner : on sonne alors à chaque fois,
	 * comme avant.
	 */
	function selectionKey(): string | null {
		if (avatarPickerOpen || scanModalOpen || artPickerOpen) return null;
		if (filePickerOpen) return filePickerComponent?.selectionKey() ?? null;
		if (searchOpen) return searchComponent?.selectionKey?.() ?? null;
		if (nameKeyboardOpen) return null;
		const settingsKey = section === 'settings' ? (settingsComponent?.selectionKey?.() ?? null) : '';
		if (settingsKey === null) return null;
		return JSON.stringify([
			navTick,
			section,
			homeIndex,
			homeZone,
			panelIndex,
			libraryIndex,
			libraryZone,
			headerIndex,
			searchOpen,
			detailButton,
			detailZone,
			mediaIndex,
			viewerOpen,
			powerIndex,
			optionsIndex,
			gameMenuOpen,
			gameMenuIndex,
			opened?.id,
			section === 'profile' ? (profileComponent?.selectionKey?.() ?? null) : '',
			statsOpen ? (statsComponent?.selectionKey?.() ?? null) : '',
			settingsKey,
		]);
	}

	function dispatch(action: Action) {
		// Écran de lancement : seul B compte, il ramène à Lobby.
		if (launching) {
			if (action === 'cancel') endLaunchCover();
			return;
		}
		if (gameMenuOpen) return handleGameMenu(action);
		if (powerOpen) return handlePower(action);
		if (avatarPickerOpen) return avatarPickerComponent?.handleAction(action);
		if (scanModalOpen) return scanModalComponent?.handleAction(action);
		if (artPickerOpen) return artPickerComponent?.handleAction(action);
		if (filePickerOpen) return filePickerComponent?.handleAction(action);
		if (searchOpen) return searchComponent?.handleAction(action);
		if (nameKeyboardOpen) return nameKeyboard?.handleAction(action);
		if (section === 'settings' && settingsComponent?.isKeyboardActive?.()) {
			return settingsComponent.handleAction(action);
		}
		if (action === 'menu') return openPower();
		// Y : la recherche, depuis n'importe quel écran (hors fenêtres).
		if (action === 'search' && !menuOptionsOpen && !viewerOpen) {
			return openSearch();
		}
		// L1 / R1 : le dock — sauf dans la visionneuse, où ils passent au média voisin.
		if ((action === 'prev' || action === 'next') && opened && viewerOpen) return handleViewer(action);
		if (action === 'prev' || action === 'next') return stepSection(action === 'next' ? 1 : -1);
		// L2 / R2 : les catégories de l'écran, là où il y en a.
		if (action === 'pagePrev' || action === 'pageNext') {
			// Sur les statistiques, les catégories sont les périodes.
			if (section === 'profile' && statsOpen && !opened) {
				return statsComponent?.handleAction(action);
			}
			if (section !== 'library' || opened || menuOptionsOpen) return;
			const step = action === 'pageNext' ? 1 : -1;
			const at = FILTERS.indexOf(filter);
			setLibraryView(FILTERS[(at + step + FILTERS.length) % FILTERS.length], sort);
			libraryIndex = 0;
			return;
		}
		if (menuOptionsOpen && !opened) return handleOptions(action);
		if (opened) return handleDetail(action);
		if (section === 'profile' && statsOpen) return statsComponent?.handleAction(action);
		if (section === 'library') return handleLibrary(action);
		if (section === 'home') return handleHome(action);
		if (section === 'settings') return settingsComponent?.handleAction(action);
		if (section === 'profile') return profileComponent?.handleAction(action);
	}

	let noticeTimer: ReturnType<typeof setTimeout> | null = null;

	/**
	 * Bandeau du bas. Une erreur reste plus longtemps affichée — le temps de la
	 * lire depuis un canapé — et s'accompagne du signal sonore d'erreur.
	 */
	function notify(message: string | Outcome, ok = true) {
		const resolved = typeof message === 'string' ? { ok, message } : message;
		notice = resolved.message;
		noticeOk = resolved.ok;
		remember(resolved.message, resolved.ok);
		if (!resolved.ok) playSound('error');
		if (noticeTimer) clearTimeout(noticeTimer);
		noticeTimer = setTimeout(() => (notice = ''), resolved.ok ? 3000 : 6000);
	}

	async function launch() {
		if (!selected) return;
		// Il tourne déjà : on y revient au lieu d'en lancer un second.
		if (selected.id === session.id) return returnToGame();
		// Un jeu possédé mais pas installé : on confie l'installation à son launcher.
		if (selected.installed === false) {
			playSound('accept');
			return notify(await installSelected());
		}
		playSound('launch');
		const game = selected;
		const outcome = await play(game);
		if (outcome.ok && (window as any).__TAURI_INTERNALS__) startLaunchCover(game);
		else notify(outcome);
	}

	/** Durée minimale de l'écran de lancement : il ne fait jamais qu'un éclair. */
	const LAUNCH_MIN = 1500;
	/** Au-delà, le jeu tarde (mise à jour, launcher) : B est proposé. */
	const LAUNCH_SLOW = 20_000;
	/**
	 * La fenêtre du jeu doit être là à autant de relevés d'affilée (une demi-
	 * seconde d'écart) : une fenêtre de chargement qui s'ouvre et se referme,
	 * ou un écran noir passager, ne coupent plus l'animation trop tôt.
	 */
	const LAUNCH_STABLE = 3;

	/**
	 * Écran de lancement : Lobby passe au-dessus de tout (`set_launch_cover`)
	 * et montre le jeu qui démarre ; toutes les demi-secondes,
	 * `focus_game_window` cherche une grande fenêtre apparue depuis le
	 * lancement — le jeu — et lui donne le focus, puis l'écran s'efface. Ni
	 * bureau, ni fenêtre de lancement entre les deux.
	 */
	function openGameMenu(index = 0) {
		menuOptionsOpen = false;
		gameMenuIndex = index;
		gameMenuOpen = true;
	}

	/** Menu du jeu : haut / bas, A choisit, B revient au jeu — comme le guide Xbox. */
	async function handleGameMenu(action: Action) {
		if (action === 'up') gameMenuIndex = Math.max(0, gameMenuIndex - 1);
		else if (action === 'down') gameMenuIndex = Math.min(GAME_MENU.length - 1, gameMenuIndex + 1);
		else if (action === 'cancel') await returnToGame();
		else if (action === 'accept') {
			const id = GAME_MENU[gameMenuIndex].id;
			if (id === 'resume') await returnToGame();
			else if (id === 'quit') await quitGame();
			else gameMenuOpen = false;
		}
	}

	/**
	 * Choix fait dans le menu posé sur le jeu : y revenir, le quitter (Lobby
	 * revient alors, sur l'accueil), ou aller sur l'accueil sans le quitter.
	 */
	async function onGameMenuChoice(id: string) {
		if (id === 'resume') return returnToGame();
		if (id === 'quit') await quitGame();
		const { invoke } = await import('@tauri-apps/api/core');
		await invoke('bring_to_front').catch(() => {});
		opened = null;
		menuOptionsOpen = false;
		gameMenuOpen = false;
		goToSection('home');
		homeZone = 'row';
		// Sur la carte du jeu en cours (ou du dernier joué) : A y revient.
		homeIndex = -1;
	}

	/** Revenir au jeu en cours : Lobby lui rend le premier plan. */
	async function returnToGame() {
		gameMenuOpen = false;
		const pid = sessionPid();
		if (!(window as any).__TAURI_INTERNALS__) return;
		const { invoke } = await import('@tauri-apps/api/core');
		const ok = pid > 0 && (await invoke<boolean>('focus_process', { pid }).catch(() => false));
		if (!ok) notify('Fenêtre du jeu introuvable : reviens-y avec Alt + Tab.', false);
	}

	/** « Quitter le jeu », comme sur Xbox : son processus est arrêté. */
	async function quitGame() {
		gameMenuOpen = false;
		const game = runningGame;
		const pid = sessionPid();
		if (!game || !pid) {
			notify('Impossible de quitter : Lobby ne sait pas quel processus arrêter.', false);
			return;
		}
		const { invoke } = await import('@tauri-apps/api/core');
		try {
			await invoke('kill_process', { pid });
			endSession(game.id);
			playSound('cancel');
			notify(`${game.title} est fermé.`);
		} catch (error) {
			notify(`Impossible de quitter ${game.title} : ${error}`, false);
		}
	}

	async function startLaunchCover(game: Game) {
		endLaunchCover();
		const { invoke } = await import('@tauri-apps/api/core');
		launching = game;
		launchSlow = false;
		// Le jeu a le focus, Lobby non : B doit quand même pouvoir l'écarter.
		allowInBackground(['cancel']);
		await invoke('set_launch_cover', { on: true }).catch(() => {});
		const shown = Date.now();
		launchTimers.push(setTimeout(() => (launchSlow = true), LAUNCH_SLOW));
		// Pas de limite de temps : l'animation tourne tant que le jeu n'est pas
		// là (B permet toujours de revenir à Lobby).
		let seen = 0;
		let seenPid = 0;
		launchPoll = setInterval(async () => {
			if (Date.now() - shown < LAUNCH_MIN) return;
			const found = await invoke<number>('find_game_window').catch(() => 0);
			// Un jeu Steam ne compte que quand Steam l'annonce en cours.
			const steamReady =
				!session.steamAppid ||
				(await invoke<number>('steam_running_app').catch(() => 0)) === session.steamAppid;
			if (!found || !steamReady) {
				seen = 0;
				return;
			}
			seen = found === seenPid ? seen + 1 : 1;
			seenPid = found;
			if (seen < LAUNCH_STABLE) return;
			// La fenêtre du jeu est là et stable : Rust lui donne le focus.
			const pid = await invoke<number>('focus_game_window').catch(() => 0);
			if (!pid) return;
			// 1 : fenêtre prête mais sans processus désigné (Gamescope).
			if (pid > 1) setSessionWindow(pid);
			endLaunchCover();
		}, 500);
	}

	function endLaunchCover() {
		for (const timer of launchTimers) clearTimeout(timer);
		launchTimers = [];
		if (launchPoll) clearInterval(launchPoll);
		launchPoll = null;
		allowInBackground([]);
		if (!launching) return;
		launching = null;
		launchSlow = false;
		if ((window as any).__TAURI_INTERNALS__) {
			void import('@tauri-apps/api/core').then(({ invoke }) =>
				invoke('set_launch_cover', { on: false }).catch(() => {})
			);
		}
	}

	/** Installation par Steam ou par le launcher Epic, selon la boutique du jeu. */
	async function installSelected(): Promise<Outcome> {
		if (selected?.source === 'epic' && selected.id.startsWith('epic-')) {
			return installEpicGame(selected.id.slice('epic-'.length));
		}
		if (selected?.appid) return installGame(selected.appid);
		return { ok: false, message: 'Installation impossible : boutique inconnue.' };
	}

	/**
	 * Démarrage : réglages, bibliothèque installée, puis — en arrière-plan —
	 * recherche des jeux installés (un jeu installé, désinstallé ou déplacé
	 * depuis un autre launcher est à jour d'office) et lecture des comptes
	 * Steam et Epic.
	 */
	async function startup() {
		await initSettings();
		await Promise.all([initLibrary(), initArtStore()]);
		libraryReady = true;

		if ((window as any).__TAURI_INTERNALS__) {
			scanAndSync()
				.then((changes) => {
					if (changes) notify(`Bibliothèque mise à jour : ${changes}.`);
				})
				.catch((e) => notify(`Recherche des jeux impossible : ${e}`, false));
		}

		// Le compte local d'abord : la liste complète en complète les temps.
		void initSteamAccount().then(() =>
			initSteamLibrary((ok, message) => {
				if (ok) {
					// Première connexion, profil encore par défaut : on reprend
					// le pseudo et la photo du compte Steam.
					if (settings.profile_name === 'Joueur') useSteamProfile();
					notify(`Bibliothèque Steam synchronisée : ${message} jeux.`);
				} else if (message === 'connexion annulée') notify('Connexion Steam annulée.');
				else notify(`Bibliothèque Steam impossible : ${message}`, false);
			})
		);
		void initEpicAccount((ok, message) => {
			if (ok) notify(`Epic Games connecté : ${message}.`);
			// Fenêtre fermée à la main : ce n'est pas une erreur.
			else if (message === 'connexion annulée') notify('Connexion Epic annulée.');
			else notify(`Connexion Epic impossible : ${message}`, false);
		});
	}

	onMount(() => {
		// Les téléchargements Steam sont relus régulièrement tant que
		// l'interface est ouverte.
		const stopDownloads = watchDownloads();
		applySound(settings.sound_enabled);
		// Les sons sont décodés d'avance : le premier appui doit déjà sonner
		// juste, pas retomber sur le bip de secours.
		if (settings.sound_enabled) preloadSounds();
		void startup();
		const stop = listen(handle);
		// Filet de sécurité : sans cela, une erreur non rattrapée laissait une
		// interface figée sans rien dire. On préfère un bandeau explicite.
		const onError = (event: ErrorEvent) => notify(`Erreur : ${event.message}`, false);
		const onRejection = (event: PromiseRejectionEvent) =>
			notify(`Erreur : ${event.reason}`, false);
		const onF11 = (event: KeyboardEvent) => {
			if (event.key !== 'F11') return;
			event.preventDefault();
			toggleFullscreen();
		};
		window.addEventListener('keydown', onF11);
		// Fin de partie : Lobby revient au premier plan.
		const onGameExited = () => {
			endLaunchCover();
			gameMenuOpen = false;
			void import('@tauri-apps/api/core').then(({ invoke }) => invoke('bring_to_front').catch(() => {}));
		};
		window.addEventListener('game-exited', onGameExited);
		// View + Menu maintenus en pleine partie : le menu du jeu s'ouvre **par-
		// dessus le jeu** (fenêtre `overlay`, `GameOverlay.svelte`) ; ses choix
		// reviennent ici (`game-menu`).
		onGameCombo(() => {
			if (!session.id) return;
			void import('@tauri-apps/api/core').then(({ invoke }) =>
				invoke('open_game_overlay', { gameId: session.id }).catch((e) =>
					notify(`Menu du jeu impossible : ${e}`, false)
				)
			);
		});
		let stopGameMenu: (() => void) | null = null;
		if ((window as any).__TAURI_INTERNALS__) {
			void import('@tauri-apps/api/event').then(({ listen: on }) =>
				on<string>('game-menu', (event) => void onGameMenuChoice(event.payload)).then(
					(fn) => (stopGameMenu = fn)
				)
			);
		}
		// Capture : `?launch=demo` montre l'écran de lancement du jeu sélectionné.
		if (params.get('launch') === 'demo') launching = selected ?? null;
		window.addEventListener('error', onError);
		window.addEventListener('unhandledrejection', onRejection);
		const timer = setInterval(() => {
			clock = formatClock();
			pads = padCount();
			// Pas de veille sans artwork à montrer.
			const delay = settings.screensaver_minutes * 60_000;
			if (delay > 0 && saverImages.length > 0) {
				if (Date.now() - lastInput >= delay) saverOn = true;
			}
		}, 1000);
		pads = padCount();
		// Outil de capture : ?notice=error montre le bandeau d'erreur.
		if (params.get('notice') === 'error') {
			notify("Impossible de lancer Hollow Knight : le fichier n'existe plus.", false);
		}
		return () => {
			stop();
			stopDownloads();
			clearInterval(timer);
			window.removeEventListener('keydown', onF11);
			window.removeEventListener('game-exited', onGameExited);
			onGameCombo(null);
			stopGameMenu?.();
			endLaunchCover();
			window.removeEventListener('error', onError);
			window.removeEventListener('unhandledrejection', onRejection);
		};
	});

	const tileActions = $derived<TileAction[]>(
		selected
			? [
					{
						id: 'favorite',
						label: isFavorite(selected.id) ? 'Retirer des favoris' : 'Ajouter aux favoris',
						icon: 'star',
					},
					...(selected.id === session.id ? [{ id: 'quit', label: 'Quitter le jeu', icon: 'exit' }] : []),
					{ id: 'art', label: 'Changer la jaquette', icon: 'image' },
					{ id: 'art-bg', label: "Changer l'image de fond", icon: 'video' },
					// Pas installé : rien à mettre à jour ni à désinstaller.
					...(selected.installed === false
						? [{ id: 'install', label: 'Installer', icon: 'download' }]
						: [
								{ id: 'executable', label: "Changer l'exécutable", icon: 'app' },
								{ id: 'update', label: 'Mettre à jour', icon: 'download' },
								{ id: 'verify', label: 'Vérifier les fichiers', icon: 'restart' },
								{ id: 'uninstall', label: 'Désinstaller', icon: 'trash' },
							]),
				]
			: []
	);

	async function handleOptions(action: Action) {
		if (action === 'up') optionsIndex = Math.max(0, optionsIndex - 1);
		else if (action === 'down') optionsIndex = Math.min(tileActions.length - 1, optionsIndex + 1);
		else if (action === 'cancel' || action === 'options') menuOptionsOpen = false;
		else if (action === 'accept') await runTileAction(tileActions[optionsIndex]?.id);
	}

	async function runTileAction(id: string | undefined) {
		if (!id || !selected) return;
		switch (id) {
			case 'favorite':
				switchFavorite();
				break;
			case 'art':
				// On ne fait plus défiler les affiches à l'aveugle : la fenêtre
				// montre tout ce qui existe et l'utilisateur choisit.
				artPickerTarget = 'cover';
				artPickerOpen = true;
				break;
			case 'art-bg':
				artPickerTarget = 'background';
				artPickerOpen = true;
				break;
			case 'install':
				notify(await installSelected());
				break;
			case 'quit':
				await quitGame();
				break;
			case 'executable':
				// La détection a pu se tromper : on choisit le bon fichier soi-même.
				filePickerOpen = true;
				break;
			case 'update':
				if (selected.appid) notify(await updateGame(selected.appid));
				break;
			case 'verify':
				if (selected.appid) notify(await verifyGame(selected.appid));
				break;
			case 'uninstall':
				if (selected.appid) notify(await uninstallGame(selected.appid));
				break;
		}
		if (id !== 'favorite') menuOptionsOpen = false;
	}

	const keyboardOpen = $derived(
		nameKeyboardOpen ||
			(section === 'settings' && (settingsComponent?.isKeyboardActive?.() ?? false))
	);

	/** Aide du bas : ce que font les boutons sur l'écran ou la fenêtre du moment. */
	const help = $derived.by(() => {
		type Entry = { button: GlyphButton; label: string };
		const list = (...entries: [GlyphButton, string][]): Entry[] =>
			entries.map(([button, label]) => ({ button, label }));

		if (searchOpen) return list(['a', 'Taper / Ouvrir'], ['y', 'Espace'], ['b', 'Fermer']);
		if (keyboardOpen) return list(['a', 'Taper'], ['x', 'Effacer'], ['y', 'Espace'], ['b', 'Annuler']);
		// Le menu du jeu affiche ses propres touches.
		if (gameMenuOpen) return list();
		if (powerOpen) return list(['a', 'Valider'], ['b', 'Annuler']);
		if (avatarPickerOpen) return list(['a', 'Choisir'], ['b', 'Fermer']);
		if (artPickerOpen) return list(['a', 'Choisir cette image'], ['b', 'Fermer']);
		// L'explorateur affiche ses propres touches.
		if (filePickerOpen) return list();
		if (scanModalOpen) {
			return isScanning
				? list(['b', 'Annuler'])
				: list(['a', 'Cocher / Valider'], ['x', 'Tout cocher'], ['b', 'Fermer']);
		}
		if (menuOptionsOpen && !opened) return list(['a', 'Choisir'], ['b', 'Fermer']);
		if (opened) {
			if (viewerOpen) {
				// Le lecteur vidéo affiche ses propres touches.
				return detailMedia[mediaIndex]?.kind === 'video'
					? list()
					: list(['dpad', 'Média précédent / suivant'], ['b', 'Fermer']);
			}
			if (detailZone === 'media') return list(['a', 'Agrandir'], ['b', 'Retour']);
			if (menuOptionsOpen) return list(['a', 'Choisir'], ['b', 'Fermer']);
			const action = detailButton === 0 ? 'Jouer' : detailButton === 1 ? 'Détails du jeu' : 'Options';
			return list(['a', action], ['x', 'Options'], ['b', 'Retour']);
		}
		if (section === 'library') {
			if (libraryZone === 'header') {
				return list(['a', headerIndex === 0 ? 'Changer le tri' : 'Synchroniser'], ['b', 'Accueil']);
			}
			return list(
				['a', 'Ouvrir'],
				['x', 'Options'],
				['y', 'Recherche'],
				['b', 'Accueil']
			);
		}
		if (section === 'profile' && statsOpen) return list(['a', 'Ouvrir'], ['r2', 'Période'], ['b', 'Retour']);
		if (section === 'profile') return list(['a', 'Modifier'], ['y', 'Recherche'], ['b', 'Accueil']);
		if (section === 'settings') return list(['a', 'Valider'], ['b', 'Accueil']);
		if (homeZone === 'row' && homeGames.length === 0 && !resumeGame) {
			return list(['a', 'Détecter mes jeux'], ['y', 'Recherche']);
		}
		if (homeZone === 'panels') {
			const what = panelIndex === 0 ? 'Bibliothèque' : panelIndex === 1 ? 'Statistiques' : 'Voir le jeu';
			return list(['a', what], ['dpad', 'Jeux'], ['y', 'Recherche']);
		}
		return list(
			['a', homeIndex < 0 ? 'Reprendre' : 'Ouvrir'],
			['x', homeIndex < 0 && isRunning ? 'Quitter le jeu' : 'Options'],
			['y', 'Recherche']
		);
	});
</script>

<Backdrop
	src={backdropSrc}
	dimmed={opened !== null ? detailZone === 'media' : section !== 'home'}
	detail={opened !== null && detailZone === 'actions'}
/>

<TopBar
	{section}
	{clock}
	{pads}
	gamesCount={allGames.length}
	profileName={settings.profile_name}
	avatar={settings.avatar_path}
	onSelectSection={goToSection}
	searching={searchOpen}
	onOpenSearch={openSearch}
/>

<main>
	{#key section}
	<div class="screen">
	{#if opened}
		<Detail
			game={opened}
			favorite={isFavorite(opened.id)}
			selected={detailButton}
			playtime={playtimeText(opened.id)}
			zone={detailZone}
			{mediaIndex}
		/>
	{:else if section === 'home'}
		<Home
			games={homeGames}
			index={homeIndex}
			resume={resumeGame}
			running={isRunning}
			focused={homeZone === 'row'}
			installed={games}
			{sessions}
			downloads={downloads.list}
			focusedPanel={homeZone === 'panels' ? panelIndex : -1}
			steamSyncedAt={steamLibrary.fetchedAt}
		/>
	{:else if section === 'library'}
		<Library
			games={libraryGames}
			index={libraryIndex}
			{syncing}
			zone={libraryZone}
			{headerIndex}
			{filter}
			{sort}
			columns={COLUMNS}
		/>
	{:else if section === 'profile'}
		<Profile
			bind:this={profileComponent}
			games={allGames}
			focused={!statsOpen}
			profileName={settings.profile_name}
			avatar={settings.avatar_path}
			steamPersona={steamAccount.persona}
			steamAvatar={steamAccount.avatar}
			epicName={epicAccount.displayName}
			epicPending={epicAccount.pending}
			epicError={epicAccount.error}
			epicGamesCount={Object.keys(epicAccount.playtime).length}
			steamLibraryCount={Object.keys(steamAccount.owned).length}
			steamLibraryDate={steamLibrary.fetchedAt}
			steamLibraryPending={steamLibrary.pending}
			onSteamLibraryLogin={() =>
				loginSteamLibrary().catch((e) => notify(`Connexion Steam impossible : ${e}`, false))}
			onSteamLibraryForget={async () => {
				await forgetSteamLibrary();
				notify('Compte Steam déconnecté : seuls les jeux installés restent.');
			}}
			onEditName={() => (nameKeyboardOpen = true)}
			onChangeAvatar={() => (avatarPickerOpen = true)}
			onEpicLogin={() => loginEpic().catch((e) => notify(`Connexion Epic impossible : ${e}`, false))}
			onEpicRefresh={async () => {
				await refreshEpicAccount();
				notify(epicAccount.error ? `Epic : ${epicAccount.error}` : 'Temps de jeu Epic actualisé.', !epicAccount.error);
			}}
			onEpicLogout={async () => {
				await logoutEpic();
				notify('Compte Epic Games déconnecté.');
			}}
			onOpenStats={() => transition(() => (statsOpen = true))}
			onBack={() => goToSection('home')}
		/>
		{#if statsOpen}
			<div class="subpage">
				<Stats
					bind:this={statsComponent}
					games={allGames}
					profileName={settings.profile_name}
					initialPeriod={(params.get('period') as Period) ?? 'month'}
					onOpenGame={openDetail}
					onBack={() => transition(() => (statsOpen = false))}
				/>
			</div>
		{/if}
	{:else if section === 'settings'}
		<Settings
			bind:this={settingsComponent}
			gameFolders={settings.game_folders}
			buttonLayout={settings.button_layout}
			onBack={() => goToSection('home')}
			onReturnToHub={() => goToSection('home')}
			onOpenScan={runGameScan}
			onAddFolder={addGameFolder}
			onRemoveFolder={removeGameFolder}
			onChangeLayout={setButtonLayout}
			soundEnabled={settings.sound_enabled}
			volumes={{
				volume_master: settings.volume_master,
				volume_menu: settings.volume_menu,
				volume_alerts: settings.volume_alerts,
				volume_launch: settings.volume_launch,
				volume_video: settings.volume_video,
			}}
			onStepVolume={(key, delta) => {
				stepVolume(key, delta);
				// Aperçu du son réglé, au nouveau volume.
				const preview = { volume_master: 'move', volume_menu: 'move', volume_alerts: 'pad', volume_launch: 'launch' } as const;
				if (key in preview) playSound(preview[key as keyof typeof preview]);
			}}
			homeOrderLabel={HOME_ORDER_LABELS[settings.home_order]}
			onCycleHomeOrder={() => {
				const next = settings.home_order === 'recent' ? 'title' : 'recent';
				setHomeOrder(next);
				homeIndex = resumeGame ? -1 : 0;
				notify(`Accueil trié par ${HOME_ORDER_LABELS[next].toLowerCase()}.`);
			}}
			screensaverMinutes={settings.screensaver_minutes}
			steamGridKey={settings.steamgriddb_key}
			initialCategory={params.get('cat') ?? 'games'}
			{fullscreen}
			onToggleFullscreen={toggleFullscreen}
			initialKeyboard={params.get('modal') === 'keyboard'}
			onChangeSteamGridKey={async (key) => {
				setSteamGridKey(key);
				if (!key) return notify('Clé SteamGridDB retirée.');

				// La clé est essayée tout de suite : une faute de copie se voit
				// ici plutôt qu'au prochain jeu sans jaquette.
				const result = await settingsComponent?.checkSteamGridKey?.(key);
				if (result === 'ok') notify('Clé SteamGridDB valide.');
				else if (result === 'unauthorized') {
					notify('Clé refusée par SteamGridDB : vérifie la copie.', false);
				} else notify('Clé enregistrée, mais SteamGridDB est injoignable.', false);
			}}
			onCycleScreensaver={() => {
				const steps = [0, 5, 10, 20];
				const at = steps.indexOf(settings.screensaver_minutes);
				const next = steps[(at + 1) % steps.length];
				setScreensaverMinutes(next);
				lastInput = Date.now();
				notify(next ? `Veille après ${next} min.` : 'Veille désactivée.');
			}}
			onToggleSound={() => {
				const next = !settings.sound_enabled;
				saveSoundEnabled(next);
				applySound(next);
				// Le contexte audio est refermé quand on coupe le son : en le
				// rallumant, il faut redécoder les fichiers.
				if (next) preloadSounds();
				notify(next ? 'Sons activés.' : 'Sons coupés.');
			}}
		/>
	{/if}
	</div>
	{/key}
</main>

{#if saverOn}
	<ScreenSaver images={saverImages} />
{/if}

<SearchModal
	bind:this={searchComponent}
	open={searchOpen}
	games={allGames}
	onOpenGame={(game) => {
		searchOpen = false;
		openDetail(game);
	}}
	onClose={() => (searchOpen = false)}
/>

<VirtualKeyboard
	bind:this={nameKeyboard}
	open={nameKeyboardOpen}
	title="Modifier le pseudo"
	subtitle="Saisis ton nom avec la manette ou le clavier"
	initialValue={settings.profile_name}
	maxLength={24}
	onConfirm={(name) => {
		setProfileName(name);
		nameKeyboardOpen = false;
		notify(`Pseudo mis à jour : ${name}`);
	}}
	onClose={() => (nameKeyboardOpen = false)}
/>

{#if opened && viewerOpen && detailMedia.length > 0}
	<MediaViewer
		bind:this={viewerComponent}
		items={detailMedia}
		index={mediaIndex}
		title={opened.title}
		volume={videoVolume}
	/>
{/if}

{#if powerOpen}
	<PowerMenu index={powerIndex} pending={powerPending} />
{/if}

<AvatarPicker
	bind:this={avatarPickerComponent}
	open={avatarPickerOpen}
	current={settings.avatar_path}
	profileName={settings.profile_name}
	onSelect={setAvatar}
	onClose={() => (avatarPickerOpen = false)}
/>

<OptionsMenu actions={tileActions} index={optionsIndex} open={menuOptionsOpen} game={selected} />

<OptionsMenu
	actions={GAME_MENU}
	index={gameMenuIndex}
	open={gameMenuOpen}
	game={runningGame ?? resumeGame}
	subtitle="En cours"
	backLabel="Revenir au jeu"
/>

<ArtPicker
	bind:this={artPickerComponent}
	open={artPickerOpen}
	game={selected}
	target={artPickerTarget}
	onClose={() => (artPickerOpen = false)}
	onPicked={(message, ok) => notify(message, ok)}
/>

<FilePicker
	bind:this={filePickerComponent}
	open={filePickerOpen}
	game={selected}
	onClose={() => (filePickerOpen = false)}
	onPick={(path) => {
		if (!selected) return;
		setGameExecutable(selected.id, path);
		filePickerOpen = false;
		notify(`${selected.title} se lancera avec ${path.split(/[\\/]/).pop()}.`);
	}}
/>

<ScanResultsModal
	bind:this={scanModalComponent}
	open={scanModalOpen}
	candidates={scannedCandidates}
	alreadyKnownIds={alreadyKnownGameIds}
	scanning={isScanning}
	onConfirm={handleScanConfirm}
	onClose={closeScan}
/>

{#if notice}
	<div class="notice" class:failed={!noticeOk}>
		{#if !noticeOk}<span class="mark">!</span>{/if}
		{notice}
	</div>
{/if}

<!-- Sur l'accueil, le panneau « Mises à jour » montre déjà les téléchargements. -->
{#if section !== 'home' || opened}
	<DownloadBar />
{/if}

<PadToast />

{#if launching}
	<LaunchOverlay game={launching} slow={launchSlow} />
{/if}

<HelpBar entries={help} />

<style>
	/* Entrée d'un écran : fondu court et léger glissement, sans rien
	   photographier. Le dock au-dessus ne bouge pas. */
	.screen {
		position: relative;
		height: 100%;
		/* `backwards` seulement : un `transform` laissé en place après coup
		   ferait de l'écran le repère des éléments en `position: fixed`. */
		animation: screen-in var(--normal) var(--ease) backwards;
	}

	@keyframes screen-in {
		from {
			opacity: 0;
			transform: translateY(12px);
		}
	}

	main {
		position: relative;
		z-index: 1;
		height: calc(100% - var(--topbar-height));
	}

	/* Sous-page des réglages : elle couvre tout le contenu, fond plein, sous la
	   barre du haut qui reste visible. */
	.subpage {
		position: absolute;
		inset: 0;
		z-index: 2;
		background: linear-gradient(180deg, var(--bg-top) 0%, var(--bg) 40%);
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

	/* Une erreur se distingue au premier coup d'œil : liseré rouge et pastille,
	   sans pour autant changer de place ni de forme. */
	.notice.failed {
		box-shadow: inset 0 0 0 2px var(--danger);
	}

	.mark {
		display: inline-grid;
		place-items: center;
		width: 24px;
		height: 24px;
		margin-right: 10px;
		border-radius: 50%;
		background: var(--danger);
		color: #17060a;
		font-weight: 700;
		vertical-align: -5px;
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
