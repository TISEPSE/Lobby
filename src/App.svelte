<script lang="ts">
	import { onMount } from 'svelte';
	import Backdrop from './lib/Backdrop.svelte';
	import TopBar from './lib/TopBar.svelte';
	import Home from './lib/Home.svelte';
	import Library from './lib/Library.svelte';
	import Search from './lib/Search.svelte';
	import Detail from './lib/Detail.svelte';
	import HelpBar from './lib/HelpBar.svelte';
	import PowerMenu from './lib/PowerMenu.svelte';
	import BootVideo from './lib/BootVideo.svelte';
	import DownloadBar from './lib/DownloadBar.svelte';
	import ScreenSaver from './lib/ScreenSaver.svelte';
	import { watchDownloads } from './lib/downloads.svelte.js';
	import { play as playSound, setSoundEnabled as applySound, preloadSounds } from './lib/sound';
	import Settings from './lib/Settings.svelte';
	import AvatarPicker from './lib/AvatarPicker.svelte';
	import ScanResultsModal from './lib/ScanResultsModal.svelte';
	import ArtPicker from './lib/ArtPicker.svelte';
	import OptionsMenu from './lib/OptionsMenu.svelte';
	import { runPower, POWER_ENTRIES, type PowerAction } from './lib/power';
	import { updateGame, verifyGame, uninstallGame } from './lib/steamActions';
	import { artwork, details } from './lib/steam.svelte.js';
	import type { TileAction, Game, Section, Outcome } from './lib/types';
	import { SEARCH_ROWS, keyAt, rowLength, nearestColumn, normalizeForSearch } from './lib/searchKeys';
	import { listen, padCount, type Action } from './lib/gamepad';
	import { play } from './lib/launcher';
	import {
		games,
		view,
		toggleFavorite,
		isFavorite,
		playtimeText,
		initLibrary,
		addGames,
		stats,
		type Filter,
		type Sort,
	} from './lib/library.svelte.js';
	import {
		settings,
		initSettings,
		setProfileName,
		setAvatar,
		setButtonLayout,
		setBootVideo,
		setBootVideoEnabled,
		setSoundEnabled as saveSoundEnabled,
		setScreensaverMinutes,
		setSteamGridKey,
		addGameFolder,
		removeGameFolder,
	} from './lib/settings.svelte.js';

	const SECTIONS: Section[] = ['home', 'library', 'search', 'settings'];
	const FILTERS: Filter[] = ['all', 'favorites', 'recent'];
	const SORTS: Sort[] = ['title', 'recent', 'playtime'];
	const COLUMNS = 8;

	/* Outil de développement, comme le `--capture` de la version Godot :
	   `?screen=detail&index=3` ouvre directement un écran pour la capture. */
	const params = new URLSearchParams(location.search);

	const wanted = params.get('screen');
	const wantedIndex = Number(params.get('index') ?? 0);

	/** Section affichée, et si la sélection est montée sur la barre du haut. */
	let section = $state<Section>(
		wanted === 'library' || wanted === 'search' || wanted === 'settings' ? wanted : 'home'
	);
	let onTabs = $state(false);
	/** Jeu ouvert en fiche détaillée. Null : on est sur la section courante. */
	let opened = $state<Game | null>(wanted === 'detail' ? (games[wantedIndex] ?? null) : null);

	let homeIndex = $state(wantedIndex);
	let libraryIndex = $state(wanted === 'library' ? wantedIndex : 0);
	/** Recherche : texte saisi, zone active (clavier ou résultats), curseurs. */
	let query = $state('');
	let searchZone = $state<'keys' | 'results'>('keys');
	let searchKey = $state({ row: 0, col: 0 });
	let searchResult = $state(0);

	/**
	 * Vidéo d'introduction : jouée une fois au lancement, par-dessus l'interface
	 * déjà construite derrière. `?boot=0` la saute (outil de capture).
	 */
	let bootPlaying = $state(params.get('boot') !== '0');

	/**
	 * Écran de veille : on garde l'instant de la dernière action plutôt qu'un
	 * compte à rebours à annuler et relancer sans arrêt.
	 */
	let saverOn = $state(params.get('saver') === '1');
	let lastInput = $state(Date.now());

	/** Vidéos livrées avec l'interface ; la première entrée n'en joue aucune. */
	const BOOT_VIDEOS = [
		'',
		'/assets/boot/steamos_startup.webm',
		'/assets/boot/steamos_splash.webm',
		'/assets/boot/steam_frame_boot.webm',
		'/assets/boot/xbox_boot_2026.webm',
		'/assets/boot/sonic_advance.webm',
		'/assets/boot/radagon_elden_ring.webm',
	];
	const SEARCH_RESULT_COLUMNS = 8;

	let filter = $state<Filter>('all');
	let sort = $state<Sort>('title');

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
	let detailOptionsOpen = $state(params.get('options') === 'detail');
	let optionsIndex = $state(0);

	/** Modales et scan */
	let avatarPickerOpen = $state(params.get('modal') === 'avatars');
	let scanModalOpen = $state(params.get('modal') === 'scan');
	/** Choix de l'affiche d'un jeu, ouvert depuis le menu d'options d'une tuile. */
	let artPickerOpen = $state(params.get('modal') === 'art');
	let isScanning = $state(false);
	let scannedCandidates = $state<Game[]>([]);

	let settingsComponent: {
		handleAction: (action: Action) => void;
		isKeyboardActive?: () => boolean;
		focusProfile?: () => void;
		checkSteamGridKey?: (key: string) => Promise<string>;
	} | null = $state(null);
	let avatarPickerComponent: { handleAction: (action: string) => void } | null = $state(null);
	let scanModalComponent: { handleAction: (action: string) => void } | null = $state(null);
	let artPickerComponent: { handleAction: (action: Action) => void } | null = $state(null);

	const libraryGames = $derived(view(filter, sort));

	/**
	 * Résultats de la recherche : comparaison sans accents ni ponctuation, pour
	 * que « repo » trouve « R.E.P.O. » et « spiderman » « Spider-Man ».
	 */
	const searchResults = $derived.by(() => {
		const needle = normalizeForSearch(query);
		if (!needle) return games;
		return games.filter((game) => normalizeForSearch(game.title).includes(needle));
	});
	const selected = $derived(
		opened ??
			(section === 'library'
				? libraryGames[libraryIndex]
				: section === 'search'
					? searchResults[searchResult]
					: games[homeIndex])
	);

	/**
	 * Artwork de fond : celui de la fiche Steam, sinon celui téléchargé pour ce
	 * jeu, sinon celui du fichier de bibliothèque.
	 */
	const backdropSrc = $derived.by(() => {
		if (!selected) return '';
		const sheet = selected.appid ? details[selected.appid] : undefined;
		return sheet?.hero || artwork[selected.id]?.hero || selected.hero || '';
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
		Object.values(stats).reduce((acc, curr) => acc + (curr.playtimeMinutes || 0), 0)
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

	function transition(change: () => void) {
		if (!document.startViewTransition) {
			change();
			return;
		}
		document.startViewTransition(change);
	}

	function openDetail(game: Game | undefined) {
		if (!game) return;
		detailButton = 0;
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
		else if (action === 'down' || action === 'accept') {
			onTabs = false;
			if (section === 'settings') {
				settingsComponent?.focusProfile?.();
			}
		} else if (action === 'cancel') {
			if (section !== 'home') {
				goToSection('home');
			}
			onTabs = false;
		}
	}

	function handleHome(action: Action) {
		if (action === 'left') homeIndex = Math.max(0, homeIndex - 1);
		else if (action === 'right') homeIndex = Math.min(games.length - 1, homeIndex + 1);
		else if (action === 'up') onTabs = true;
		else if (action === 'accept') openDetail(games[homeIndex]);
		else if (action === 'options') {
			optionsOpen = true;
			optionsIndex = 0;
		}
	}

	function handleLibrary(action: Action) {
		const total = libraryGames.length;
		const row = Math.floor(libraryIndex / COLUMNS);
		if (action === 'left') libraryIndex = Math.max(0, libraryIndex - 1);
		else if (action === 'right') libraryIndex = Math.min(total - 1, libraryIndex + 1);
		else if (action === 'down') libraryIndex = Math.min(total - 1, libraryIndex + COLUMNS);
		else if (action === 'up') {
			if (row === 0) onTabs = true;
			else libraryIndex = Math.max(0, libraryIndex - COLUMNS);
		} else if (action === 'accept') openDetail(libraryGames[libraryIndex]);
		else if (action === 'search') {
			sort = SORTS[(SORTS.indexOf(sort) + 1) % SORTS.length];
			libraryIndex = 0;
		} else if (action === 'cancel') goToSection('home');
	}

	/** Clavier à gauche, résultats à droite : le passage se fait au bord. */
	function handleSearch(action: Action) {
		if (searchZone === 'keys') {
			const { row, col } = searchKey;
			const lastRow = SEARCH_ROWS.length - 1;

			if (action === 'left') searchKey = { row, col: Math.max(0, col - 1) };
			else if (action === 'right') {
				searchKey = { row, col: Math.min(rowLength(row) - 1, col + 1) };
			} else if (action === 'up') {
				if (row === 0) onTabs = true;
				else searchKey = { row: row - 1, col: nearestColumn(row, col, row - 1) };
			} else if (action === 'down') {
				// Sous la dernière rangée de touches, on tombe dans les résultats :
				// le clavier se replie et la grille prend la place.
				if (row === lastRow) searchZone = 'results';
				else searchKey = { row: row + 1, col: nearestColumn(row, col, row + 1) };
			} else if (action === 'accept') {
				pressKey();
			} else if (action === 'cancel') {
				// B efface une lettre ; à vide, il quitte l'écran.
				if (query) query = query.slice(0, -1);
				else goToSection('home');
			} else if (action === 'search') {
				query += ' ';
				searchResult = 0;
			}
			return;
		}

		const total = searchResults.length;
		const row = Math.floor(searchResult / SEARCH_RESULT_COLUMNS);
		if (action === 'left') searchResult = Math.max(0, searchResult - 1);
		else if (action === 'right') searchResult = Math.min(total - 1, searchResult + 1);
		else if (action === 'down') searchResult = Math.min(total - 1, searchResult + SEARCH_RESULT_COLUMNS);
		else if (action === 'up') {
			// La première rangée ramène au clavier, pas à la barre du haut : on
			// est encore en train de chercher.
			if (row === 0) searchZone = 'keys';
			else searchResult = Math.max(0, searchResult - SEARCH_RESULT_COLUMNS);
		} else if (action === 'accept') openDetail(searchResults[searchResult]);
		else if (action === 'cancel') searchZone = 'keys';
	}

	/** Une touche du clavier : elle écrit une lettre, ou fait son action. */
	function pressKey() {
		const key = keyAt(searchKey.row, searchKey.col);
		if (!key) return;
		if (key.action === 'space') query += ' ';
		else if (key.action === 'backspace') query = query.slice(0, -1);
		else if (key.action === 'clear') query = '';
		else query += key.value;
		searchResult = 0;
	}

	function handleDetail(action: Action) {
		if (!opened) return;
		if (detailOptionsOpen) return handleOptions(action);

		if (action === 'cancel') closeDetail();
		else if (action === 'left') detailButton = Math.max(0, detailButton - 1);
		else if (action === 'right') detailButton = Math.min(2, detailButton + 1);
		else if (action === 'accept') {
			if (detailButton === 0) launch();
			else if (detailButton === 1) switchFavorite();
			else openDetailOptions();
		} else if (action === 'options') openDetailOptions();
	}

	function openDetailOptions() {
		optionsIndex = 0;
		detailOptionsOpen = true;
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

	async function runGameScan() {
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
				scannedCandidates = results;
			} catch (e) {
				notify(`Erreur pendant le scan : ${e}`, false);
			} finally {
				isScanning = false;
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

		// N'importe quelle touche passe l'introduction.
		if (bootPlaying) {
			bootPlaying = false;
			return;
		}

		// Un seul endroit décide du son : les écrans n'ont pas à y penser.
		if (action === 'accept') playSound('accept');
		else if (action === 'cancel') playSound('cancel');
		else if (action === 'up' || action === 'down' || action === 'left' || action === 'right') {
			playSound('move');
		}
		if (powerOpen) return handlePower(action);
		if (avatarPickerOpen) return avatarPickerComponent?.handleAction(action);
		if (scanModalOpen) return scanModalComponent?.handleAction(action);
		if (artPickerOpen) return artPickerComponent?.handleAction(action);
		if (section === 'settings' && settingsComponent?.isKeyboardActive?.()) {
			return settingsComponent.handleAction(action);
		}
		if (action === 'menu') return openPower();
		// L1 / R1 ne changent plus de section : on passe d'un onglet à l'autre
		// par la barre du haut. Ils servent là où il y a des catégories à
		// parcourir, c'est-à-dire la bibliothèque.
		if (action === 'prev' || action === 'next') {
			if (section !== 'library' || opened || optionsOpen) return;
			const step = action === 'next' ? 1 : -1;
			const at = FILTERS.indexOf(filter);
			filter = FILTERS[(at + step + FILTERS.length) % FILTERS.length];
			libraryIndex = 0;
			return;
		}
		if (optionsOpen) return handleOptions(action);
		if (opened) return handleDetail(action);
		if (onTabs) return handleTabs(action);
		if (section === 'library') return handleLibrary(action);
		if (section === 'search') return handleSearch(action);
		if (section === 'home') return handleHome(action);
		if (section === 'settings') return settingsComponent?.handleAction(action);
		if (action === 'up') onTabs = true;
		else if (action === 'cancel') goToSection('home');
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
		if (!resolved.ok) playSound('error');
		if (noticeTimer) clearTimeout(noticeTimer);
		noticeTimer = setTimeout(() => (notice = ''), resolved.ok ? 3000 : 6000);
	}

	async function launch() {
		playSound('launch');
		if (!selected) return;
		notify(await play(selected));
	}

	onMount(() => {
		// Les téléchargements Steam sont relus régulièrement tant que
		// l'interface est ouverte.
		const stopDownloads = watchDownloads();
		applySound(settings.sound_enabled);
		// Les sons sont décodés d'avance : le premier appui doit déjà sonner
		// juste, pas retomber sur le bip de secours.
		if (settings.sound_enabled) preloadSounds();
		initSettings();
		initLibrary();
		const stop = listen(handle);
		// Filet de sécurité : sans cela, une erreur non rattrapée laissait une
		// interface figée sans rien dire. On préfère un bandeau explicite.
		const onError = (event: ErrorEvent) => notify(`Erreur : ${event.message}`, false);
		const onRejection = (event: PromiseRejectionEvent) =>
			notify(`Erreur : ${event.reason}`, false);
		window.addEventListener('error', onError);
		window.addEventListener('unhandledrejection', onRejection);
		const timer = setInterval(() => {
			clock = formatClock();
			pads = padCount();
			// Pas de veille pendant l'introduction, ni sans artwork à montrer.
			const delay = settings.screensaver_minutes * 60_000;
			if (delay > 0 && !bootPlaying && saverImages.length > 0) {
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
					{ id: 'art', label: "Changer l'affiche", icon: 'image' },
					{ id: 'update', label: 'Mettre à jour', icon: 'download' },
					{ id: 'verify', label: 'Vérifier les fichiers', icon: 'restart' },
					{ id: 'uninstall', label: 'Désinstaller', icon: 'trash' },
				]
			: []
	);

	async function handleOptions(action: Action) {
		if (action === 'up') optionsIndex = Math.max(0, optionsIndex - 1);
		else if (action === 'down') optionsIndex = Math.min(tileActions.length - 1, optionsIndex + 1);
		else if (action === 'cancel' || action === 'options') {
			optionsOpen = false;
			detailOptionsOpen = false;
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
				artPickerOpen = true;
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
			detailOptionsOpen = false;
		}
	}

	const keyboardOpen = $derived(
		section === 'settings' && (settingsComponent?.isKeyboardActive?.() ?? false)
	);

	const help = $derived(
		keyboardOpen
			? [
					{ button: 'a' as const, label: 'Taper' },
					{ button: 'x' as const, label: 'Effacer' },
					{ button: 'y' as const, label: 'Espace' },
					{ button: 'b' as const, label: 'Annuler' },
				]
			: powerOpen
			? [
					{ button: 'a' as const, label: 'Valider' },
					{ button: 'b' as const, label: 'Annuler' },
				]
			: avatarPickerOpen
				? [
						{ button: 'a' as const, label: 'Choisir' },
						{ button: 'b' as const, label: 'Fermer' },
					]
				: artPickerOpen
					? [
							{ button: 'a' as const, label: 'Choisir cette affiche' },
							{ button: 'b' as const, label: 'Fermer' },
						]
					: scanModalOpen
					? [
							{ button: 'a' as const, label: 'Cocher / Valider' },
							{ button: 'x' as const, label: 'Tout cocher' },
							{ button: 'b' as const, label: 'Fermer' },
						]
					: optionsOpen
						? [
								{ button: 'a' as const, label: 'Choisir' },
								{ button: 'b' as const, label: 'Fermer' },
							]
						: opened
							? detailOptionsOpen
								? [
										{ button: 'a' as const, label: 'Choisir' },
										{ button: 'b' as const, label: 'Fermer' },
									]
								: [
										{
											button: 'a' as const,
											label:
												detailButton === 0 ? 'Jouer' : detailButton === 1 ? 'Favori' : 'Options',
										},
										{ button: 'x' as const, label: 'Options' },
										{ button: 'b' as const, label: 'Retour' },
									]
							: section === 'library'
								? [
										{ button: 'a' as const, label: 'Ouvrir' },
										{ button: 'r1' as const, label: 'Catégorie' },
										{ button: 'y' as const, label: 'Tri' },
										{ button: 'b' as const, label: 'Accueil' },
									]
								: section === 'search'
									? searchZone === 'keys'
										? [
												{ button: 'a' as const, label: 'Taper' },
												{ button: 'y' as const, label: 'Espace' },
												{ button: 'b' as const, label: query ? 'Effacer' : 'Retour' },
											]
										: [
												{ button: 'a' as const, label: 'Ouvrir' },
												{ button: 'b' as const, label: 'Clavier' },
											]
									: section === 'settings'
										? [
												{ button: 'a' as const, label: 'Valider' },
												{ button: 'b' as const, label: 'Retour' },
											]
									: [
											{ button: 'a' as const, label: 'Ouvrir' },
											{ button: 'x' as const, label: 'Options' },
											{ button: 'y' as const, label: 'Recherche' },
										]
	);
</script>

<Backdrop src={backdropSrc} dimmed={opened !== null || section !== 'home'} />

<TopBar
	{section}
	focused={onTabs}
	{clock}
	{pads}
	gamesCount={games.length}
	profileName={settings.profile_name}
	avatar={settings.avatar_path}
	onSelectSection={(sec) => {
		goToSection(sec);
		onTabs = false;
		if (sec === 'settings') {
			settingsComponent?.focusProfile?.();
		}
	}}
/>

<main>
	{#if opened}
		<Detail
			game={opened}
			favorite={isFavorite(opened.id)}
			selected={detailButton}
			playtime={playtimeText(opened.id)}
		/>
	{:else if section === 'home'}
		<Home
			{games}
			index={homeIndex}
			actions={tileActions}
			{optionsOpen}
			{optionsIndex}
		/>
	{:else if section === 'library'}
		<Library games={libraryGames} index={libraryIndex} {filter} {sort} columns={COLUMNS} />
	{:else if section === 'settings'}
		<Settings
			bind:this={settingsComponent}
			focused={!onTabs}
			profileName={settings.profile_name}
			avatar={settings.avatar_path}
			gamesCount={games.length}
			favoriteCount={favoriteCount}
			totalPlaytime={totalPlaytimeFormatted}
			gameFolders={settings.game_folders}
			buttonLayout={settings.button_layout}
			onBack={() => {
				onTabs = true;
			}}
			onReturnToHub={() => {
				onTabs = true;
			}}
			onOpenAvatarPicker={() => (avatarPickerOpen = true)}
			onOpenScan={runGameScan}
			onChangeName={(name) => {
				setProfileName(name);
				notify(`Pseudo mis à jour : ${name}`);
			}}
			onAddFolder={addGameFolder}
			onRemoveFolder={removeGameFolder}
			onChangeLayout={setButtonLayout}
			bootVideo={settings.boot_video}
			bootVideoEnabled={settings.boot_video_enabled}
			onCycleBootVideo={() => {
				const next =
					BOOT_VIDEOS[(BOOT_VIDEOS.indexOf(settings.boot_video) + 1) % BOOT_VIDEOS.length];
				setBootVideo(next);
				notify(next ? "Vidéo d'introduction changée." : "Plus de vidéo au démarrage.");
			}}
			soundEnabled={settings.sound_enabled}
			screensaverMinutes={settings.screensaver_minutes}
			steamGridKey={settings.steamgriddb_key}
			initialCategory={params.get('cat') ?? 'profile'}
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
			onToggleBootVideo={() => {
				setBootVideoEnabled(!settings.boot_video_enabled);
				notify(settings.boot_video_enabled ? 'Vidéo activée.' : 'Vidéo désactivée.');
			}}
		/>
	{:else}
		<Search
			games={searchResults}
			{query}
			zone={searchZone}
			keyRow={searchKey.row}
			keyCol={searchKey.col}
			resultIndex={searchResult}
			columns={SEARCH_RESULT_COLUMNS}
		/>
	{/if}
</main>

{#if bootPlaying && settings.boot_video_enabled && settings.boot_video}
	<BootVideo src={settings.boot_video} onFinished={() => (bootPlaying = false)} />
{/if}

{#if saverOn}
	<ScreenSaver images={saverImages} />
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

<OptionsMenu actions={tileActions} index={optionsIndex} open={detailOptionsOpen} />

<ArtPicker
	bind:this={artPickerComponent}
	open={artPickerOpen}
	game={selected}
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
	onClose={() => (scanModalOpen = false)}
/>

{#if notice}
	<div class="notice" class:failed={!noticeOk}>
		{#if !noticeOk}<span class="mark">!</span>{/if}
		{notice}
	</div>
{/if}

<DownloadBar />

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
