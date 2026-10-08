<script lang="ts">
	/**
	 * Menu du jeu posé **sur la partie**, façon guide Xbox : une fenêtre à part
	 * (`overlay`, transparente, au-dessus de tout — `open_game_overlay`), ouverte
	 * par View + Menu maintenus. On ne quitte pas le jeu pour l'ouvrir : il reste
	 * visible derrière le voile.
	 *
	 * Cette fenêtre ne fait que montrer et choisir ; c'est la fenêtre principale
	 * qui agit (elle connaît la partie en cours) : chaque choix lui est envoyé
	 * (`game-menu`), puis le menu se cache.
	 */
	import { onMount } from 'svelte';
	import OptionsMenu from './lib/OptionsMenu.svelte';
	import { listen, type Action } from './lib/gamepad';
	import { games, initLibrary } from './lib/library.svelte.js';
	import { heroFor, initArtStore } from './lib/steam.svelte.js';
	import { initSettings, settings } from './lib/settings.svelte.js';
	import { play as playSound, preloadSounds, setSoundEnabled, setVolumes } from './lib/sound';
	import type { TileAction } from './lib/types';

	const ACTIONS: TileAction[] = [
		{ id: 'resume', label: 'Revenir au jeu', icon: 'play' },
		{ id: 'quit', label: 'Quitter le jeu', icon: 'exit' },
		{ id: 'home', label: "Aller à l'accueil de Lobby", icon: 'home' },
	];

	let gameId = $state<string>((window as any).__LOBBY_OVERLAY__ ?? '');
	let index = $state(0);
	/** Remonte le menu à chaque ouverture, pour rejouer son entrée. */
	let opening = $state(0);
	/** Capture : `?overlay=demo` pose le menu sur l'artwork d'un jeu, comme sur une partie. */
	const DEMO = new URLSearchParams(location.search).get('overlay') === 'demo';
	const game = $derived(DEMO ? (games[1] ?? null) : (games.find((g) => g.id === gameId) ?? null));

	async function choose(id: string) {
		const { emitTo } = await import('@tauri-apps/api/event');
		const { invoke } = await import('@tauri-apps/api/core');
		await emitTo('main', 'game-menu', id);
		await invoke('close_game_overlay');
	}

	function handle(action: Action) {
		if (action === 'up' || action === 'down') {
			const next = Math.max(0, Math.min(ACTIONS.length - 1, index + (action === 'up' ? -1 : 1)));
			if (next !== index) playSound('move');
			index = next;
		} else if (action === 'accept') {
			playSound('accept');
			void choose(ACTIONS[index].id);
		} else if (action === 'cancel') {
			// B, comme sur le guide Xbox : retour au jeu.
			playSound('cancel');
			void choose('resume');
		}
	}

	onMount(() => {
		// Fenêtre transparente : on doit voir le jeu derrière le voile.
		document.documentElement.style.background = 'transparent';
		// `html`, `body` et `#app` ont tous le fond sombre de l'interface.
		document.body.style.background = 'transparent';
		const root = document.getElementById('app');
		if (root) root.style.background = 'transparent';
		if (DEMO && games[1]) document.body.style.background = `center / cover url(${heroFor(games[1])})`;
		void (async () => {
			await initSettings();
			setSoundEnabled(settings.sound_enabled);
			setVolumes({
				master: settings.volume_master / 100,
				menu: settings.volume_menu / 100,
				alerts: settings.volume_alerts / 100,
				launch: settings.volume_launch / 100,
			});
			if (settings.sound_enabled) preloadSounds();
			await Promise.all([initLibrary(), initArtStore()]);
		})();
		const stop = listen(handle);
		let unlisten: (() => void) | null = null;
		void import('@tauri-apps/api/event').then(({ listen: on }) =>
			on<string>('overlay-open', (event) => {
				gameId = event.payload;
				index = 0;
				opening += 1;
			}).then((fn) => (unlisten = fn))
		).catch(() => {});
		return () => {
			stop();
			unlisten?.();
		};
	});
</script>

{#key opening}
	<OptionsMenu
		actions={ACTIONS}
		{index}
		open={true}
		{game}
		subtitle="En cours"
		backLabel="Revenir au jeu"
		floating
	/>
{/key}
