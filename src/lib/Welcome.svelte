<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import { fade, fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import Cover from './Cover.svelte';
	import Glyph from './Glyph.svelte';
	import { currentPadName, type Action } from './gamepad';
	import type { GlyphButton } from './glyphs';
	import { games, homeView } from './library.svelte.js';
	import { LAYOUT_LABELS, settings } from './settings.svelte.js';
	import { platformOf } from './stats';
	import { steamAccount, steamStatus } from './steamAccount.svelte.js';
	import { epicAccount, epicAction, epicStatus } from './epicAccount.svelte.js';
	import { steamGridStatus } from './steamGrid.svelte.js';

	/**
	 * Écrans de bienvenue : au premier lancement, tout se configure ici, à la
	 * manette, avant d'arriver sur l'accueil. Profil, boutiques, jeux, habitudes.
	 *
	 * Comme le menu rapide, ils ne montrent que du réel : chaque ligne agit
	 * vraiment, et tout reste facultatif (« Continuer » passe à la suite). Tout
	 * découle de `rows` : le rendu, la navigation, l'action de A et la barre d'aide.
	 */
	let {
		initialStep = 0,
		pads = 0,
		scanning = false,
		totalGames = 0,
		autostart = null,
		onEditName,
		onChangeAvatar,
		onUseSteamProfile,
		onSteamLogin,
		onEpicLogin,
		onSteamGridLogin,
		onEditSteamGridKey,
		onScan,
		onPickFolder,
		onToggleSound,
		onPickLayout,
		onToggleAutostart,
		onDone,
	}: {
		/** Étape au premier affichage (outil de capture). */
		initialStep?: number;
		/** Nombre de manettes : l'étape d'accueil dit si la sienne est vue. */
		pads?: number;
		scanning?: boolean;
		/** Jeux installés, plus ceux possédés sur les comptes reliés. */
		totalGames?: number;
		/** Démarrage avec la session ; `null` : sans objet sur ce système. */
		autostart?: boolean | null;
		onEditName?: () => void;
		onChangeAvatar?: () => void;
		onUseSteamProfile?: () => void;
		onSteamLogin?: () => void;
		onEpicLogin?: () => void;
		onSteamGridLogin?: () => void;
		/** Saisie de la clé à la main, si la connexion ne la trouve pas. */
		onEditSteamGridKey?: () => void;
		onScan?: () => void;
		onPickFolder?: () => void;
		onToggleSound?: () => void;
		/** Ouvre la liste des packs de touches, accrochée à sa ligne. */
		onPickLayout?: (anchor: HTMLElement | null) => void;
		onToggleAutostart?: () => void;
		onDone?: () => void;
	} = $props();

	type Step = 'hello' | 'profile' | 'accounts' | 'games' | 'habits' | 'ready';

	const STEPS: Step[] = ['hello', 'profile', 'accounts', 'games', 'habits', 'ready'];
	/** Étapes comptées dans la progression : ni l'accueil, ni l'arrivée. */
	const COUNTED: Step[] = ['profile', 'accounts', 'games', 'habits'];
	/** Jaquettes montrées quand la recherche a trouvé des jeux. */
	const SHELF = 6;
	/** Entrée d'une étape : `--normal` et `--fast`, et le chemin parcouru en pixels. */
	const SLIDE = 260;
	const FADE = 180;
	const SHIFT = 56;
	/** Décalage d'une jaquette à la suivante, pour qu'elles arrivent en vague. */
	const STAGGER = 60;

	interface Row {
		id: string;
		label: string;
		/** Sous le libellé : ce que ça fait, ou l'état du compte. */
		hint?: string;
		/** À droite : la valeur du réglage. */
		value?: string;
		/** Icône de `public/assets/icons/`. */
		icon?: string;
		/** Image ronde à la place de l'icône (photo). */
		image?: string;
		/** Une zone de saisie : `value` y est écrite, A ouvre le clavier. */
		field?: boolean;
		/** Le bouton de l'étape, en accent. */
		primary?: boolean;
		/** Ce que fait A, pour la barre d'aide. Sans action : ligne d'information. */
		accept?: string;
		run?: () => void;
		/** Seconde action, sur X. */
		alternate?: { label: string; run: () => void };
	}

	let stepIndex = $state(Math.min(STEPS.length - 1, Math.max(0, initialStep)));
	let row = $state(0);
	/** Sens du dernier changement d'étape : le contenu entre du côté où l'on va. */
	let direction = $state<1 | -1>(1);
	/** La recherche ne part qu'une fois : revenir sur l'étape ne la relance pas. */
	let scanned = false;
	let list = $state<HTMLElement | null>(null);

	const step = $derived(STEPS[stepIndex]);
	const profileName = $derived(settings.profile_name);
	const steamOwned = $derived(Object.keys(steamAccount.owned).length);
	const accounts = $derived(
		[steamOwned > 0 && 'Steam', epicAccount.connected && 'Epic Games'].filter((name) => !!name) as string[]
	);

	/** Jeux trouvés, par boutique, les plus fournies d'abord. */
	const stores = $derived.by(() => {
		const counts = new Map<string, number>();
		for (const game of games) counts.set(platformOf(game), (counts.get(platformOf(game)) ?? 0) + 1);
		return [...counts].sort((a, b) => b[1] - a[1]);
	});
	const shelf = $derived(step === 'games' ? homeView('recent').slice(0, SHELF) : []);
	const found = $derived(`${games.length} jeu${games.length > 1 ? 'x' : ''}`);

	function goTo(next: number) {
		if (next < 0 || next >= STEPS.length) return;
		direction = next > stepIndex ? 1 : -1;
		stepIndex = next;
		// La recherche se fait seule : c'est le bouton qu'on veut sous la main.
		row = STEPS[next] === 'games' ? rowsOf('games').length - 1 : 0;
	}

	const forward = () => goTo(stepIndex + 1);

	/** Le bouton qui passe à l'étape suivante, dernière ligne de chaque étape. */
	function next(label = 'Continuer'): Row {
		return { id: 'next', label, primary: true, accept: label, run: forward };
	}

	function rowsOf(current: Step): Row[] {
		switch (current) {
			case 'hello':
				return [
					next('Commencer'),
					{
						id: 'skip',
						label: 'Passer la configuration',
						hint: 'Tes jeux seront cherchés quand même. Tout se règle ensuite dans le menu.',
						accept: 'Passer',
						run: () => onDone?.(),
					},
				];
			case 'profile':
				return [
					// Le compte Steam de ce PC, tant qu'il n'est pas déjà repris.
					...(steamAccount.persona && steamAccount.persona !== profileName
						? [
								{
									id: 'steam-profile',
									label: 'Reprendre mon profil Steam',
									value: steamAccount.persona,
									image: steamAccount.avatar || undefined,
									icon: 'steam',
									accept: 'Reprendre',
									run: () => onUseSteamProfile?.(),
								},
							]
						: []),
					{
						id: 'avatar',
						label: 'Photo de profil',
						hint: 'Importe la tienne ou choisis une illustration',
						image: settings.avatar_path,
						accept: 'Changer',
						run: () => onChangeAvatar?.(),
					},
					{
						id: 'name',
						label: 'Pseudo',
						value: profileName,
						field: true,
						accept: 'Saisir',
						run: () => onEditName?.(),
					},
					next(),
				];
			case 'accounts': {
				const verb = epicAction();
				return [
					{
						id: 'steam',
						label: 'Steam',
						hint: steamStatus(),
						icon: 'steam',
						...(steamOwned === 0 ? { accept: 'Se connecter', run: () => onSteamLogin?.() } : {}),
					},
					{
						id: 'epic',
						label: 'Epic Games',
						hint: epicStatus(),
						icon: 'epic',
						...(verb ? { accept: verb, run: () => onEpicLogin?.() } : {}),
					},
					{
						id: 'steamgriddb',
						label: 'SteamGridDB',
						hint: steamGridStatus(),
						icon: 'image',
						accept: 'Se connecter',
						run: () => onSteamGridLogin?.(),
						alternate: { label: 'Saisir la clé', run: () => onEditSteamGridKey?.() },
					},
					next(accounts.length || settings.steamgriddb_key ? 'Continuer' : 'Plus tard'),
				];
			}
			case 'games':
				return [
					{
						id: 'folder',
						label: 'Ajouter un dossier de jeux',
						hint: settings.game_folders.length
							? settings.game_folders.join(' · ')
							: 'Pour un jeu rangé ailleurs que dans une boutique',
						icon: 'folder',
						accept: 'Parcourir',
						run: () => onPickFolder?.(),
					},
					next(),
				];
			case 'habits':
				return [
					{
						id: 'sound',
						label: 'Sons de l’interface',
						value: settings.sound_enabled ? 'Activés' : 'Désactivés',
						icon: 'volume',
						accept: 'Changer',
						run: () => onToggleSound?.(),
					},
					{
						id: 'layout',
						label: 'Touches affichées',
						value: LAYOUT_LABELS[settings.button_layout] ?? LAYOUT_LABELS.auto,
						icon: 'controller',
						accept: 'Choisir',
						run: () => onPickLayout?.(list?.querySelector<HTMLElement>('.row.selected') ?? null),
					},
					...(autostart === null
						? []
						: [
								{
									id: 'autostart',
									label: 'Ouvrir Lobby au démarrage',
									hint: 'Dès ta session Windows, comme une console',
									value: autostart ? 'Oui' : 'Non',
									icon: 'power',
									accept: 'Changer',
									run: () => onToggleAutostart?.(),
								},
							]),
					next(),
				];
			default:
				return [
					{ id: 'done', label: 'Entrer dans Lobby', primary: true, accept: 'Entrer', run: () => onDone?.() },
				];
		}
	}

	const rows = $derived(rowsOf(step));
	/** Une ligne peut disparaître sous la sélection (profil Steam repris). */
	const current = $derived(Math.min(row, rows.length - 1));

	const text = $derived.by((): { caption: string; title: string; body: string } => {
		switch (step) {
			case 'hello':
				return {
					caption: 'Bienvenue',
					title: 'Ton PC devient une console',
					body: 'Quelques réglages à la manette, et tous tes jeux sont réunis ici.',
				};
			case 'profile':
				return {
					caption: 'Profil',
					title: 'Qui joue ?',
					body: 'Ton pseudo et ta photo t’accueillent à chaque démarrage. Ils se changent quand tu veux.',
				};
			case 'accounts':
				return {
					caption: 'Comptes',
					title: 'Relie tes comptes',
					body: 'Tes jeux non installés, ton temps de jeu et les jaquettes qui manquent arrivent avec. Tout se fait sur leurs pages officielles : Lobby ne voit jamais ton mot de passe.',
				};
			case 'games':
				return {
					caption: 'Bibliothèque',
					title: scanning ? 'Recherche de tes jeux…' : games.length ? `${found} sur ce PC` : 'Aucun jeu trouvé',
					body: scanning
						? 'Steam, Epic Games, les raccourcis du Bureau et les dossiers de jeux de chaque disque.'
						: stores.length
							? stores.map(([store, count]) => `${store} ${count}`).join(' · ')
							: 'Indique le dossier où sont tes jeux, ou continue : la recherche recommencera à chaque démarrage.',
				};
			case 'habits':
				return {
					caption: 'Habitudes',
					title: 'À ta façon',
					body: 'Quelques choix rapides. Tout se retrouve ensuite dans le menu.',
				};
			default:
				return {
					caption: 'C’est prêt',
					title: `Bon jeu, ${profileName}`,
					body: [
						`${found} installé${games.length > 1 ? 's' : ''}`,
						totalGames > games.length ? `${totalGames} dans tes bibliothèques` : '',
						accounts.length ? `Comptes : ${accounts.join(' et ')}` : '',
					]
						.filter(Boolean)
						.join(' · '),
				};
		}
	});

	/** Le geste à retenir, sur la dernière étape. */
	const CONTROLS: { button: GlyphButton; label: string }[] = [
		{ button: 'a', label: 'Valider' },
		{ button: 'b', label: 'Retour' },
		{ button: 'x', label: 'Options d’un jeu' },
		{ button: 'y', label: 'Recherche' },
		{ button: 'view', label: 'Menu rapide' },
		{ button: 'menu', label: 'Panneau' },
	];

	/** Relue à chaque manette branchée ou retirée. */
	const pad = $derived(pads >= 0 ? currentPadName() : '');

	// La recherche démarre seule en arrivant sur l'étape.
	$effect(() => {
		if (step !== 'games' || scanned) return;
		scanned = true;
		untrack(() => onScan?.());
	});

	// `?step=` peut ouvrir directement sur la bonne ligne.
	onMount(() => {
		if (step === 'games') row = rows.length - 1;
	});

	/** Empreinte de la sélection, pour ne sonner que si elle bouge. */
	export function selectionKey(): string {
		return `${stepIndex}|${current}`;
	}

	/** Touches de la barre d'aide pour la sélection du moment. */
	export function hints(): [GlyphButton, string][] {
		const { accept, alternate } = rows[current] ?? {};
		return [
			...(accept ? ([['a', accept]] as [GlyphButton, string][]) : []),
			...(alternate ? ([['x', alternate.label]] as [GlyphButton, string][]) : []),
			...(stepIndex > 0 ? ([['b', 'Retour']] as [GlyphButton, string][]) : []),
		];
	}

	export function handleAction(action: Action) {
		if (action === 'up') row = Math.max(0, current - 1);
		else if (action === 'down') row = Math.min(rows.length - 1, current + 1);
		else if (action === 'accept') rows[current]?.run?.();
		else if (action === 'options') rows[current]?.alternate?.run();
		else if (action === 'cancel') goTo(stepIndex - 1);
	}
</script>

<section class="welcome" class:centered={step === 'hello' || step === 'ready'} out:fade={{ duration: SLIDE }}>
	<span class="aura"></span>

	<header>
		<img class="mark" src="/assets/logo.png" alt="" />
		<span class="brand">Lobby</span>
		{#if COUNTED.includes(step)}
			<div class="progress" in:fade={{ duration: FADE }}>
				<span class="count">Étape {COUNTED.indexOf(step) + 1} sur {COUNTED.length}</span>
				<ol>
					{#each COUNTED as entry, i (entry)}
						<li class:done={i <= COUNTED.indexOf(step)}></li>
					{/each}
				</ol>
			</div>
		{/if}
	</header>

	{#key step}
		<div class="stage" in:fly={{ x: SHIFT * direction, duration: SLIDE, easing: cubicOut, opacity: 0 }}>
			<div class="copy">
				{#if step === 'hello'}
					<img class="logo" src="/assets/logo.png" alt="" />
				{/if}
				<span class="caption">{text.caption}</span>
				{#key text.title}
					<h1 in:fade={{ duration: FADE }}>{text.title}</h1>
				{/key}
				{#key text.body}
					<p in:fade={{ duration: FADE }}>{text.body}</p>
				{/key}

				{#if step === 'hello'}
					<span class="pad" class:on={!!pad}>
						<img src="/assets/icons/controller.svg" alt="" />
						{pad ? `${pad} prête` : 'Appuie sur une touche de ta manette pour la réveiller'}
					</span>
				{:else if step === 'games'}
					{#if scanning}
						<span class="searching" role="progressbar" aria-label="Recherche en cours"></span>
					{/if}
					{#if shelf.length > 0}
						<div class="shelf">
							{#each shelf as game, i (game.id)}
								<span class="tile" in:fly={{ y: SHIFT / 2, duration: SLIDE, delay: i * STAGGER, easing: cubicOut }}>
									<Cover {game} />
								</span>
							{/each}
						</div>
					{/if}
				{:else if step === 'ready'}
					<ul class="controls">
						{#each CONTROLS as control (control.button)}
							<li><Glyph button={control.button} size="var(--welcome-glyph)" />{control.label}</li>
						{/each}
					</ul>
				{/if}
			</div>

			<div class="rows" bind:this={list} style="--row: {current}">
				<span class="glider focus-ring"></span>
				{#each rows as entry, i (entry.id)}
					<button
						type="button"
						class="row"
						class:primary={entry.primary}
						class:selected={current === i}
						onclick={() => {
							row = i;
							entry.run?.();
						}}
					>
						{#if entry.field}
							<!-- Une vraie zone de saisie à l'œil : son libellé au-dessus, la
							     valeur dedans, le curseur quand elle est sélectionnée. -->
							<span class="text">
								<span class="hint">{entry.label}</span>
								<span class="input">
									{entry.value}
									{#if current === i}<span class="caret"></span>{/if}
								</span>
							</span>
						{:else}
							{#if entry.image}
								<img class="face" src={entry.image} alt="" />
							{:else if entry.icon}
								<span class="badge"><img src="/assets/icons/{entry.icon}.svg" alt="" /></span>
							{/if}
							<span class="text">
								<span class="label">{entry.label}</span>
								{#if entry.hint}<span class="hint">{entry.hint}</span>{/if}
							</span>
							{#if entry.value}<span class="value">{entry.value}</span>{/if}
						{/if}
					</button>
				{/each}
			</div>
		</div>
	{/key}
</section>

<style>
	/* Pleine page, sous le bandeau et les fenêtres (pseudo, photo, explorateur) :
	   la barre d'aide, peinte après, reste au-dessus d'elle. */
	.welcome {
		position: fixed;
		inset: 0;
		z-index: 3;
		display: flex;
		flex-direction: column;
		overflow: hidden;
		padding: var(--safe-y) var(--safe-x);
		background: linear-gradient(180deg, var(--bg-top) 0%, var(--bg) 60%);
	}

	/* Deux lueurs d'accent qui dérivent lentement : de simples dégradés déplacés,
	   jamais de flou, pour rester fluide sans carte graphique. */
	.aura {
		position: absolute;
		inset: -25%;
		pointer-events: none;
		background:
			radial-gradient(38% 38% at 26% 30%, var(--welcome-glow), transparent 100%),
			radial-gradient(32% 32% at 78% 74%, var(--welcome-glow-soft), transparent 100%);
		animation: drift var(--welcome-drift) ease-in-out infinite alternate;
	}

	@keyframes drift {
		to {
			transform: translate3d(6%, -5%, 0) rotate(6deg);
		}
	}

	header {
		position: relative;
		flex: none;
		display: flex;
		align-items: center;
		gap: 14px;
		height: var(--welcome-header);
	}

	.mark {
		width: var(--welcome-mark);
		height: var(--welcome-mark);
	}

	.brand {
		font-size: var(--welcome-label);
		font-weight: 600;
	}

	.progress {
		display: flex;
		align-items: center;
		gap: 20px;
		margin-left: auto;
		font-size: 17px;
		color: var(--text-dim);
	}

	.count {
		font-variant-numeric: tabular-nums;
	}

	ol {
		display: flex;
		gap: 8px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	ol li {
		width: var(--welcome-segment);
		height: 6px;
		border-radius: 3px;
		background: var(--surface-strong);
		transition: background var(--normal) var(--ease);
	}

	ol li.done {
		background: var(--accent);
	}

	.stage {
		position: relative;
		flex: 1;
		min-height: 0;
		display: grid;
		grid-template-columns: minmax(0, 1fr) var(--welcome-rows);
		gap: var(--welcome-gap);
		align-items: center;
		/* La barre d'aide vit dans ce bas de page. */
		padding-bottom: var(--welcome-bottom);
	}

	.copy {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 16px;
		min-width: 0;
	}

	.caption {
		font-size: 18px;
		font-weight: 700;
		letter-spacing: 0.14em;
		text-transform: uppercase;
		color: var(--accent);
	}

	h1 {
		margin: 0;
		font-size: var(--welcome-title);
		font-weight: 700;
		line-height: 1.08;
		text-wrap: balance;
	}

	p {
		max-width: var(--welcome-measure);
		margin: 0;
		font-size: var(--welcome-text);
		line-height: 1.45;
		color: var(--text-dim);
	}

	/* Étapes d'accueil et d'arrivée : tout au centre, une seule colonne. */
	.centered .stage {
		grid-template-columns: minmax(0, 1fr);
		grid-template-rows: auto auto;
		gap: var(--welcome-center-gap);
		align-content: center;
		justify-items: center;
		text-align: center;
	}

	.centered .copy {
		align-items: center;
	}

	.centered .rows {
		width: var(--welcome-rows);
	}

	.logo {
		width: var(--welcome-logo);
		height: var(--welcome-logo);
		margin-bottom: 8px;
		filter: drop-shadow(0 0 48px var(--accent-soft));
		animation: breathe var(--welcome-breath) ease-in-out infinite alternate;
	}

	@keyframes breathe {
		to {
			transform: scale(1.035);
		}
	}

	.pad {
		display: inline-flex;
		align-items: center;
		gap: 10px;
		font-size: 18px;
		color: var(--text-dim);
	}

	.pad img {
		width: var(--welcome-icon);
		height: var(--welcome-icon);
		opacity: 0.6;
	}

	.pad.on {
		color: var(--text);
	}

	.pad.on img {
		opacity: 1;
	}

	/* Une barre qui parcourt la largeur : le temps de recherche n'est pas connu. */
	.searching {
		position: relative;
		width: var(--welcome-measure);
		max-width: 100%;
		height: 6px;
		overflow: hidden;
		border-radius: 3px;
		background: var(--surface-strong);
	}

	.searching::after {
		content: '';
		position: absolute;
		inset: 0 auto 0 0;
		width: 35%;
		border-radius: 3px;
		background: var(--accent);
		animation: sweep var(--welcome-sweep) ease-in-out infinite;
	}

	@keyframes sweep {
		from {
			transform: translateX(-100%);
		}
		to {
			transform: translateX(290%);
		}
	}

	.shelf {
		display: flex;
		gap: var(--welcome-shelf-gap);
		margin-top: 12px;
	}

	.tile {
		position: relative;
		flex: none;
		display: block;
		width: var(--welcome-cover);
		aspect-ratio: 2 / 3;
		overflow: hidden;
		border-radius: var(--welcome-radius);
		box-shadow: 0 16px 40px rgba(0, 0, 0, 0.5);
	}

	.controls {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: 14px 32px;
		margin: 12px 0 0;
		padding: 0;
		list-style: none;
		font-size: 18px;
		color: var(--text-dim);
	}

	.controls li {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	.rows {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--welcome-row-gap);
		isolation: isolate;
	}

	.row > * {
		position: relative;
		z-index: 1;
	}

	.glider {
		top: 0;
		left: 0;
		right: 0;
		height: var(--welcome-row);
		--glide-y: calc(var(--row) * (var(--welcome-row) + var(--welcome-row-gap)));
		border-radius: var(--welcome-radius);
	}

	/* Le cadre ne glisse qu'avec son contour, sans fond : il passe au-dessus des
	   lignes, et un voile clair aurait éclairci le vert du bouton. Chaque ligne se
	   colore elle-même, sur place. */
	.row {
		flex: none;
		display: flex;
		align-items: center;
		gap: 18px;
		width: 100%;
		height: var(--welcome-row);
		padding: 0 var(--welcome-row-pad);
		border-radius: var(--welcome-radius);
		background: var(--settings-row-bg);
		text-align: left;
		/* À la vitesse du cadre : la couleur arrive avec lui, ni avant ni après. */
		transition:
			background var(--normal) var(--ease),
			color var(--normal) var(--ease);
	}

	.row:hover {
		background: var(--settings-row-hover);
	}

	.row.selected {
		background: var(--settings-row-hover);
	}

	/* Le bouton de l'étape porte l'accent, sélectionné ou non : c'est la suite. */
	.row.primary {
		justify-content: center;
		background: var(--accent-soft);
	}

	/* Le vert reste sur le bouton et se fond sur place : posé sur le cadre, un bloc
	   plein traversait les lignes et le texte virait au sombre avant son arrivée. */
	.row.primary.selected {
		background: var(--accent);
		color: var(--on-accent);
	}

	.row.primary .label {
		font-weight: 700;
	}

	.badge,
	.face {
		flex: none;
		width: var(--welcome-badge);
		height: var(--welcome-badge);
		border-radius: 50%;
	}

	.badge {
		display: grid;
		place-items: center;
		background: var(--surface-strong);
	}

	.badge img {
		width: var(--welcome-icon);
		height: var(--welcome-icon);
	}

	/* Ronde, jamais carrée : la photo remplit son cercle. */
	.face {
		object-fit: cover;
		box-shadow: 0 0 0 2px var(--accent);
	}

	.text {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}

	.row.primary .text {
		flex: none;
	}

	.label {
		font-size: var(--welcome-label);
		font-weight: 600;
	}

	.hint {
		font-size: 17px;
		color: var(--text-dim);
		overflow: hidden;
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	.input {
		display: flex;
		align-items: center;
		height: var(--welcome-field);
		padding: 0 14px;
		border: 1px solid var(--welcome-field-line);
		border-radius: 8px;
		background: var(--welcome-field-bg);
		font-size: 20px;
		font-weight: 600;
		transition: border-color var(--fast) var(--ease);
	}

	.row.selected .input {
		border-color: var(--accent);
	}

	.caret {
		width: 2px;
		height: 24px;
		margin-left: 2px;
		background: var(--accent);
		animation: caret 1s steps(2) infinite;
	}

	@keyframes caret {
		to {
			opacity: 0;
		}
	}

	.value {
		flex: none;
		max-width: 50%;
		font-size: 19px;
		color: var(--text-dim);
		overflow: hidden;
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	.row.selected .value {
		color: var(--text);
	}
</style>
