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
	import { artwork, details, heroFor, coverFor, mediaOf, initArtStore, DEMO_MEDIA } from './lib/steam.svelte.js';
	import MediaViewer from './lib/MediaViewer.svelte';
	import PadToast from './lib/PadToast.svelte';
	import BootIntro from './lib/BootIntro.svelte';
	import { remember } from './lib/notices.svelte.js';
	import type { TileAction, Game, Section, Outcome } from './lib/types';
	import { listen, padCount, type Action } from './lib/gamepad';
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
		setIntroEnabled,
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

	/**
	 * Animation de démarrage (`BootIntro`) : jouée à chaque lancement, sauf si
	 * elle est désactivée dans Apparence (`?intro=0` la saute, pour les
	 * captures). Sa jauge suit le vrai chargement : réglages, bibliothèque,
	 * puis les images des premiers jeux de l'accueil, préchargées.
	 */
	let introPlaying = $state(params.get('intro') !== '0' && params.get('boot') !== '0');

	/** Trace dans le journal de l'application (diagnostic du démarrage). */
	function trace(message: string) {
		if (!(window as any).__TAURI_INTERNALS__) return;
		void import('@tauri-apps/api/core').then(({ invoke }) => invoke('ui_log', { message }).catch(() => {}));
	}
	trace(`démarrage, animation ${introPlaying ? 'prévue' : 'désactivée'}`);
	let introComponent = $state<{ skip: () => void } | null>(null);
	/** La sortie de l'animation a commencé : l'interface peut se montrer. */
	let introRevealed = $state(false);

	// Pendant toute l'animation, l'interface derrière elle est masquée : elle
	// ne se montre qu'à la sortie, quand le fond s'efface.
	$effect(() => {
		document.body.classList.toggle('booting', introPlaying && !introRevealed);
	});
	/**
	 * Chargement réel pendant l'animation (`bootLoad`) : étape affichée, comptes
	 * arrivés, et jeux dont les images sont décodées.
	 */
	let boot = $state({
		step: 'Lecture des réglages…',
		settings: false,
		library: false,
		steam: false,
		epic: false,
		imagesDone: 0,
		imagesTotal: 0,
		/** Tout est chargé, jaquettes comprises. */
		done: false,
	});
	/** Jeux installés prêts : leurs images (jaquette et fond) décodées. */
	let bootReadyIds = $state<Record<string, true>>({});
	/** Jeux prêts, pour le compteur « N / total » : installés décodés + possédés arrivés. */
	const bootReady = $derived(
		Object.keys(bootReadyIds).length +
			(boot.steam ? uninstalledSteamGames(steamAccount.owned).length : 0) +
			(boot.epic ? uninstalledEpicGames(epicAccount.library).length : 0)
	);
	/** Avancement de la jauge, étape par étape. */
	const bootProgress = $derived(
		(boot.settings ? 0.05 : 0) +
			(boot.library ? 0.15 : 0) +
			(boot.steam ? 0.15 : 0) +
			(boot.epic ? 0.15 : 0) +
			// La dernière part ne se remplit qu'avec les jaquettes réellement
			// chargées : entre les comptes et les jaquettes, le total d'images
			// valait 0 et la jauge passait à 100 % — l'accueil arrivait trop tôt.
			(boot.done ? 0.5 : boot.imagesTotal > 0 ? 0.5 * (boot.imagesDone / boot.imagesTotal) : 0)
	);
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

	/** Volume des vidéos (intro, bandes-annonces) : le leur, multiplié par le général. */
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
	let powerIndex = $state(0);
	let powerPending = $state<PowerAction | null>((params.get('confirm') as PowerAction) ?? null);

	/** Menu d'options de la tuile sélectionnée, sur l'accueil. */
	let optionsOpen = $state(params.get('options') === '1');
	/** Même menu, ouvert depuis une fiche : il n'y a pas de tuile à prolonger. */
	/**
	 * Menu d'options en fenêtre : sur une fiche, ou dans la bibliothèque (X sur
	 * une jaquette). `?options=detail` ou `?options=library` l'ouvrent (capture).
	 */
	let menuOptionsOpen = $state(params.get('options') === 'detail' || params.get('options') === 'library');
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
	/** Dernier jeu lancé. `?resume=demo` en invente un, pour juger la carte dans un navigateur. */
	const resumeGame = $derived(
		params.get('resume') === 'demo' ? (games[1] ?? null) : lastPlayedGame()
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
		optionsOpen = false;
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
		else if (action === 'options') {
			optionsOpen = true;
			optionsIndex = 0;
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

		// N'importe quelle touche passe l'animation de démarrage.
		if (introPlaying) {
			trace(`touche pendant l'animation : ${action}`);
			introComponent?.skip();
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
			opened?.id,
			section === 'profile' ? (profileComponent?.selectionKey?.() ?? null) : '',
			statsOpen ? (statsComponent?.selectionKey?.() ?? null) : '',
			settingsKey,
		]);
	}

	function dispatch(action: Action) {
		if (powerOpen) return handlePower(action);
		if (avatarPickerOpen) return avatarPickerComponent?.handleAction(action);
		if (scanModalOpen) return scanModalComponent?.handleAction(action);
		if (artPickerOpen) return artPickerComponent?.handleAction(action);
		if (searchOpen) return searchComponent?.handleAction(action);
		if (nameKeyboardOpen) return nameKeyboard?.handleAction(action);
		if (section === 'settings' && settingsComponent?.isKeyboardActive?.()) {
			return settingsComponent.handleAction(action);
		}
		if (action === 'menu') return openPower();
		// Y : la recherche, depuis n'importe quel écran (hors fenêtres).
		if (action === 'search' && !optionsOpen && !menuOptionsOpen && !viewerOpen) {
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
			if (section !== 'library' || opened || optionsOpen) return;
			const step = action === 'pageNext' ? 1 : -1;
			const at = FILTERS.indexOf(filter);
			setLibraryView(FILTERS[(at + step + FILTERS.length) % FILTERS.length], sort);
			libraryIndex = 0;
			return;
		}
		if (optionsOpen) return handleOptions(action);
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
		// Un jeu possédé mais pas installé : on confie l'installation à son launcher.
		if (selected.installed === false) {
			playSound('accept');
			return notify(await installSelected());
		}
		playSound('launch');
		notify(await play(selected));
	}

	/** Installation par Steam ou par le launcher Epic, selon la boutique du jeu. */
	async function installSelected(): Promise<Outcome> {
		if (selected?.source === 'epic' && selected.id.startsWith('epic-')) {
			return installEpicGame(selected.id.slice('epic-'.length));
		}
		if (selected?.appid) return installGame(selected.appid);
		return { ok: false, message: 'Installation impossible : boutique inconnue.' };
	}

	/** Promesse qui abandonne après `ms` : on n'attend jamais indéfiniment. */
	function within<T>(promise: Promise<T>, ms: number): Promise<T | void> {
		return Promise.race([promise, new Promise<void>((resolve) => setTimeout(resolve, ms))]);
	}

	/** Décode une image ; résout aussi en cas d'échec ou après `IMAGE_WAIT`. */
	function decodeImage(url: string): Promise<void> {
		if (!url) return Promise.resolve();
		const image = new Image();
		image.src = url;
		return within(image.decode().catch(() => {}), IMAGE_WAIT).then(() => {});
	}

	/** Attente maximale d'Epic (réseau) et d'une image, au démarrage. */
	const EPIC_WAIT = 8000;
	/** Attente maximale de la recherche des jeux installés. */
	const SCAN_WAIT = 15000;
	const IMAGE_WAIT = 4000;

	/**
	 * Tout ce qui est chargé pendant l'animation de démarrage, dans l'ordre, et
	 * dit tel quel sous le compteur. Le total (`allGames`) grandit au fil des
	 * comptes qui arrivent ; le compteur suit les jeux réellement prêts.
	 */
	async function bootLoad() {
		await initSettings();
		boot.settings = true;
		// Désactivée dans Apparence : on va droit à l'accueil (le chargement
		// continue de la même façon, sans être montré).
		trace(`réglages lus, animation ${settings.intro_enabled ? 'activée' : 'désactivée'}`);
		if (!settings.intro_enabled) introPlaying = false;

		boot.step = 'Lecture de la bibliothèque…';
		await Promise.all([initLibrary(), initArtStore()]);

		// Les jeux installés sont rescannés à chaque démarrage : un jeu installé,
		// désinstallé ou déplacé depuis un autre launcher est à jour d'office.
		if ((window as any).__TAURI_INTERNALS__) {
			boot.step = 'Recherche des jeux installés…';
			const sync = scanAndSync()
				.then((changes) => {
					if (changes) notify(`Bibliothèque mise à jour : ${changes}.`);
				})
				.catch((e) => notify(`Recherche des jeux impossible : ${e}`, false));
			// Un scan très long finit en arrière-plan : le démarrage n'attend pas.
			await within(sync, SCAN_WAIT);
		}
		libraryReady = true;
		boot.library = true;
		boot.step = games.length
			? `Bibliothèque : ${games.length} jeu${games.length > 1 ? 'x' : ''} installé${games.length > 1 ? 's' : ''}`
			: 'Aucun jeu installé — détection dans Réglages';

		// Comptes : Steam (fichiers locaux + liste chiffrée) et Epic (réseau).
		const steam = initSteamAccount()
			.then(() =>
				initSteamLibrary((ok, message) => {
					if (ok) {
						// Première connexion, profil encore par défaut : on reprend
						// le pseudo et la photo du compte Steam.
						if (settings.profile_name === 'Joueur') useSteamProfile();
						notify(`Bibliothèque Steam synchronisée : ${message} jeux.`);
					} else if (message === 'connexion annulée') notify('Connexion Steam annulée.');
					else notify(`Bibliothèque Steam impossible : ${message}`, false);
				})
			)
			.then(() => {
				boot.steam = true;
				const owned = Object.keys(steamAccount.owned).length;
				if (owned) boot.step = `Compte Steam : ${owned} jeux`;
			});
		const epic = initEpicAccount((ok, message) => {
			if (ok) notify(`Epic Games connecté : ${message}.`);
			// Fenêtre fermée à la main : ce n'est pas une erreur.
			else if (message === 'connexion annulée') notify('Connexion Epic annulée.');
			else notify(`Connexion Epic impossible : ${message}`, false);
		}).then(async () => {
			// La lecture du compte part en tâche de fond : on attend sa fin.
			while (!epicAccount.ready) await new Promise((resolve) => setTimeout(resolve, 100));
			const owned = epicAccount.library.length;
			if (owned) boot.step = `Compte Epic : ${owned} jeux`;
		});
		await Promise.all([steam, within(epic, EPIC_WAIT)]);
		boot.steam = true;
		boot.epic = true;

		// Jaquettes : celles de chaque jeu installé (jaquette et fond), puis le
		// premier lot de la bibliothèque, avec le filtre et le tri mémorisés.
		const installed = games.slice();
		const firstBatch = libraryGames.filter((game) => game.installed === false).slice(0, 48);
		boot.imagesTotal = installed.length + firstBatch.length;
		boot.imagesDone = 0;
		const tick = () => {
			boot.imagesDone += 1;
			boot.step = `Jaquettes : ${boot.imagesDone} / ${boot.imagesTotal}`;
		};
		await Promise.all([
			...installed.map((game) =>
				Promise.all([decodeImage(coverFor(game)), decodeImage(heroFor(game))]).then(() => {
					bootReadyIds[game.id] = true;
					tick();
				})
			),
			...firstBatch.map((game) => decodeImage(coverFor(game)).then(tick)),
		]);
		boot.step = 'Prêt';
		trace(`chargement fini : ${games.length} installés, ${allGames.length} au total`);
		boot.done = true;
	}

	onMount(() => {
		// Les téléchargements Steam sont relus régulièrement tant que
		// l'interface est ouverte.
		const stopDownloads = watchDownloads();
		applySound(settings.sound_enabled);
		// Les sons sont décodés d'avance : le premier appui doit déjà sonner
		// juste, pas retomber sur le bip de secours.
		if (settings.sound_enabled) preloadSounds();
		void bootLoad();
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
		window.addEventListener('error', onError);
		window.addEventListener('unhandledrejection', onRejection);
		const timer = setInterval(() => {
			clock = formatClock();
			pads = padCount();
			// Pas de veille pendant l'introduction, ni sans artwork à montrer.
			const delay = settings.screensaver_minutes * 60_000;
			if (delay > 0 && !introPlaying && saverImages.length > 0) {
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
					{ id: 'art', label: 'Changer la jaquette', icon: 'image' },
					{ id: 'art-bg', label: "Changer l'image de fond", icon: 'video' },
					// Pas installé : rien à mettre à jour ni à désinstaller.
					...(selected.installed === false
						? [{ id: 'install', label: 'Installer', icon: 'download' }]
						: [
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
		else if (action === 'cancel' || action === 'options') {
			optionsOpen = false;
			menuOptionsOpen = false;
		}
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
		if (id !== 'favorite') {
			optionsOpen = false;
			menuOptionsOpen = false;
		}
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
		if (powerOpen) return list(['a', 'Valider'], ['b', 'Annuler']);
		if (avatarPickerOpen) return list(['a', 'Choisir'], ['b', 'Fermer']);
		if (artPickerOpen) return list(['a', 'Choisir cette image'], ['b', 'Fermer']);
		if (scanModalOpen) {
			return isScanning
				? list(['b', 'Annuler'])
				: list(['a', 'Cocher / Valider'], ['x', 'Tout cocher'], ['b', 'Fermer']);
		}
		if (optionsOpen || (menuOptionsOpen && !opened)) return list(['a', 'Choisir'], ['b', 'Fermer']);
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
			return list(['a', 'Détecter mes jeux'], ['dpad', 'Lanceurs et activité'], ['y', 'Recherche']);
		}
		if (homeZone === 'panels') {
			const what = panelIndex === 0 ? 'Bibliothèque' : panelIndex === 1 ? 'Statistiques' : 'Voir le jeu';
			return list(['a', what], ['dpad', 'Jeux'], ['y', 'Recherche']);
		}
		return list(
			['a', homeIndex < 0 ? 'Reprendre' : 'Ouvrir'],
			['x', 'Options'],
			['y', 'Recherche'],
			['dpad', 'Lanceurs et activité']
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
			focused={homeZone === 'row'}
			installed={games}
			{sessions}
			downloads={downloads.list}
			focusedPanel={homeZone === 'panels' ? panelIndex : -1}
			steamSyncedAt={steamLibrary.fetchedAt}
			actions={tileActions}
			{optionsOpen}
			{optionsIndex}
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
			introEnabled={settings.intro_enabled}
			onToggleIntro={() => {
				setIntroEnabled(!settings.intro_enabled);
				notify(settings.intro_enabled ? 'Animation de démarrage activée.' : 'Animation de démarrage désactivée.');
			}}
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

{#if introPlaying}
	<BootIntro
		bind:this={introComponent}
		name={settings.profile_name}
		avatar={settings.avatar_path}
		total={allGames.length}
		ready={bootReady}
		step={boot.step}
		progress={bootProgress}
		onPhase={(phase) => trace(`animation : ${phase}`)}
		onReveal={() => (introRevealed = true)}
		onDone={() => {
			trace('animation terminée');
			introPlaying = false;
		}}
	/>
{/if}

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

<OptionsMenu
	actions={tileActions}
	index={optionsIndex}
	open={menuOptionsOpen}
	title={opened ? '' : (selected?.title ?? '')}
/>

<ArtPicker
	bind:this={artPickerComponent}
	open={artPickerOpen}
	game={selected}
	target={artPickerTarget}
	onClose={() => (artPickerOpen = false)}
	onPicked={(message, ok) => notify(message, ok)}
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
