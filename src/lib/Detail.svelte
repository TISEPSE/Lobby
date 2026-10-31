<script lang="ts">
	import type { Game } from './types';
	import { details, ensureDetails, mediaOf, DEMO_MEDIA } from './steam.svelte.js';
	import { lastPlayedText } from './library.svelte.js';
	import { platformOf } from './stats';
	import { downloadFor, phaseLabel, sizeText } from './downloads.svelte.js';

	/**
	 * Fiche d'un jeu, d'après la maquette de l'utilisateur : la boutique en
	 * petites capitales d'accent, le titre en très grand, un résumé court, trois
	 * chiffres (temps de jeu, dernière partie, note), puis JOUER · Détails du jeu
	 * · Options. Pas de jaquette : l'artwork du jeu occupe le fond.
	 *
	 * Deux pages l'une sous l'autre : la présentation, puis « Captures et
	 * vidéos » (grille de médias + panneau « Plus sur… »). Descendre depuis
	 * les boutons fait glisser la seconde à la place de la première.
	 */
	let {
		game,
		running = false,
		favorite = false,
		selected = 0,
		playtime = 'Jamais joué',
		zone = 'actions',
		mediaIndex = 0,
	}: {
		game: Game;
		/** Le jeu tourne : le bouton y revient au lieu d'en lancer un second. */
		running?: boolean;
		favorite?: boolean;
		selected?: number;
		playtime?: string;
		/** Boutons de la présentation, ou grille des médias. */
		zone?: 'actions' | 'media';
		mediaIndex?: number;
	} = $props();

	// La fiche se demande à l'ouverture ; elle arrive de Rust, puis s'affiche.
	$effect(() => {
		if (game.appid) ensureDetails(game.appid);
	});

	const sheet = $derived(game.appid ? details[game.appid] : undefined);
	/** Téléchargement en cours pour ce jeu, s'il y en a un. */
	const progress = $derived(downloadFor(game.appid));
	const rating = $derived(sheet?.rating ?? 0);
	const facts = $derived(
		[
			sheet?.genres?.join(', ') ?? '',
			sheet?.release_date ?? '',
			playtime,
		].filter((fact) => fact.trim() !== '')
	);
	/** Les trois chiffres sous le résumé ; la note, ou à défaut la sortie. */
	const stats = $derived(
		[
			['Temps de jeu', playtime],
			['Dernière partie', lastPlayedText(game.id) || 'Jamais'],
			rating > 0 ? ['Note', ''] : ['Sortie', sheet?.release_date ?? ''],
		].filter(([label, value]) => label === 'Note' || value.trim() !== '')
	);

	const media = $derived(
		new URLSearchParams(location.search).get('media') === 'demo' ? DEMO_MEDIA : mediaOf(sheet)
	);

	/**
	 * Images déjà décodées. Toutes sont préchargées en pleine taille dès
	 * l'ouverture de la fiche : en faisant défiler le slider, aucune ne se
	 * charge sous les yeux, et la visionneuse s'ouvre aussitôt.
	 */
	let ready = $state<Record<string, boolean>>({});

	/** Image affichée pour un média : la capture pleine, ou l'affiche d'une vidéo. */
	const pictureOf = (item: (typeof media)[number]) => (item.kind === 'image' ? item.src : item.thumb);

	$effect(() => {
		for (const item of media) {
			const src = pictureOf(item);
			if (ready[src]) continue;
			const image = new Image();
			image.src = src;
			image
				.decode()
				.then(() => (ready[src] = true))
				.catch(() => (ready[src] = true));
		}
	});
	/** Lignes du panneau « Plus sur… » ; seules celles qui ont une valeur. */
	const credits = $derived(
		[
			['Genres', sheet?.genres?.join(', ') ?? ''],
			['Sortie', sheet?.release_date ?? ''],
			['Développeur', sheet?.developers?.join(', ') ?? ''],
			['Éditeur', sheet?.publishers?.join(', ') ?? ''],
			['Temps de jeu', playtime],
		].filter(([, value]) => value.trim() !== '')
	);
	const summary = $derived(
		sheet?.summary ||
			(sheet ? 'Pas de résumé pour ce jeu.' : 'Récupération de la fiche auprès de Steam…')
	);
</script>

<div class="detail" class:down={zone === 'media'}>
<div class="pages">
<section class="hero">
	<div class="info">
		<span class="store">{platformOf(game)}</span>
		<h1>{game.title}</h1>
		<p class="synopsis">{summary}</p>

		<div class="stats">
			{#each stats as [label, value] (label)}
				<div>
					<span class="stat-label">{label}</span>
					<span class="stat-value">
						{#if label === 'Note'}
							<span class="stars" aria-label="Note {rating} sur 5">
								{#each [0, 1, 2, 3, 4] as i}
									<svg viewBox="0 0 640 640" class:on={rating >= i + 0.5}>
										<path
											d="M341.5 45.1C337.4 37.1 329.1 32 320.1 32C311.1 32 302.8 37.1 298.7 45.1L225.1 189.3L65.2 214.7C56.3 216.1 48.9 222.4 46.1 231C43.3 239.6 45.6 249 51.9 255.4L166.3 369.9L141.1 529.8C139.7 538.7 143.4 547.7 150.7 553C158 558.3 167.6 559.1 175.7 555L320.1 481.6L464.4 555C472.4 559.1 482.1 558.3 489.4 553C496.7 547.7 500.4 538.8 499 529.8L473.7 369.9L588.1 255.4C594.5 249 596.7 239.6 593.9 231C591.1 222.4 583.8 216.1 574.8 214.7L415 189.3L341.5 45.1z"
										/>
									</svg>
								{/each}
								<span class="value">{rating.toFixed(1)}</span>
							</span>
						{:else}
							{value}
						{/if}
					</span>
				</div>
			{/each}
		</div>

		{#if progress}
			<div class="progress">
				<div class="track"><div class="fill" style="width: {Math.max(2, progress.percent)}%"></div></div>
				<span class="state">
					{phaseLabel(progress)} · {Math.round(progress.percent)} %
					{#if sizeText(progress)}· {sizeText(progress)}{/if}
				</span>
			</div>
		{/if}

		<div class="actions">
			<button class="action cta" class:focus-ring={selected === 0}>
				<img src="/assets/icons/{game.installed === false ? 'download' : 'play'}.svg" alt="" />
				{game.installed === false ? 'Installer' : running ? 'Reprendre' : 'Jouer'}
			</button>
			<!-- Descend vers « Captures et vidéos » et le panneau « Plus sur… ». -->
			<button class="action" class:focus-ring={selected === 1}>Détails du jeu</button>
			<!-- Favori, affiche, mise à jour, fichiers : tout passe par ici. -->
			<button class="action icon" class:focus-ring={selected === 2} title="Options">
				<img src="/assets/icons/settings.svg" alt="" />
				Options
			</button>
		</div>
	</div>

	{#if media.length > 0}
		<!-- Ce qui attend plus bas : on le dit, sinon personne ne descend. -->
		<p class="more">Captures et vidéos <span>▾</span></p>
	{/if}
</section>

{#if media.length > 0 || sheet}
	<section class="media">
		<header class="media-head">
			<span class="caption">Captures et vidéos</span>
			{#if media.length > 0}
				<span class="count">{mediaIndex + 1} / {media.length}</span>
			{/if}
		</header>

		{#if media.length === 0}
			<p class="none">Aucune capture pour ce jeu.</p>
		{:else}
			<!-- Ruban centré sur la sélection : il glisse d'un bloc, la sélection
			     grandit au centre, ses voisines s'estompent sur les côtés. -->
			<div class="slider">
				<div class="reel" style="--i: {mediaIndex}">
					{#each media as item, i}
						{@const src = pictureOf(item)}
						<div
							class="slide"
							class:selected={i === mediaIndex}
							class:focused={zone === 'media' && i === mediaIndex}
						>
							<img {src} alt="" class:ready={ready[src]} />
							{#if item.kind === 'video'}
								<span class="play"><img src="/assets/icons/play.svg" alt="" /></span>
							{/if}
						</div>
					{/each}
				</div>
			</div>
			<div class="dots">
				{#each media as item, i}
					<span class="dot" class:on={i === mediaIndex} class:video={item.kind === 'video'}></span>
				{/each}
			</div>
		{/if}

		<aside class="about">
			<span class="caption">Plus sur</span>
			<h2>{game.title}</h2>
			{#if sheet?.about || sheet?.summary}
				<span class="caption">Description</span>
				<p class="text">{sheet?.about || sheet?.summary}</p>
			{/if}
			<dl>
				{#each credits as [label, value]}
					<div>
						<dt class="caption">{label}</dt>
						<dd>{value}</dd>
					</div>
				{/each}
			</dl>
		</aside>
	</section>
{/if}
</div>
</div>

<style>
	.detail {
		position: relative;
		z-index: 1;
		height: 100%;
		overflow: hidden;
	}

	/* Les deux pages glissent ensemble : la seconde prend la place de la
	   première, comme un défilement d'une page entière. */
	.pages {
		height: 100%;
		transition: transform var(--normal) var(--ease);
	}

	.detail.down .pages {
		transform: translateY(-100%);
	}

	/* Colonne de gauche, centrée en hauteur : l'artwork respire à droite. */
	.hero {
		position: relative;
		display: flex;
		align-items: center;
		height: 100%;
		padding: var(--safe-y) var(--safe-x);
		animation: enter var(--normal) var(--ease) both;
	}

	@keyframes enter {
		from {
			opacity: 0;
			transform: translateY(18px);
		}
	}

	.info {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		max-width: var(--detail-width);
	}

	.store {
		font-size: 19px;
		font-weight: 800;
		letter-spacing: 0.12em;
		text-transform: uppercase;
		color: var(--accent);
	}

	h1 {
		margin: 10px 0 0;
		font-size: clamp(48px, 5.6vw, 104px);
		font-weight: 800;
		line-height: 1;
		letter-spacing: -0.03em;
		text-wrap: balance;
		text-shadow: 0 4px 30px rgba(0, 0, 0, 0.4);
	}

	/* Un résumé court : trois lignes, à largeur de lecture. */
	.synopsis {
		display: -webkit-box;
		-webkit-line-clamp: 3;
		line-clamp: 3;
		-webkit-box-orient: vertical;
		overflow: hidden;
		margin: 22px 0 0;
		max-width: 60ch;
		font-size: 22px;
		line-height: 1.45;
		color: rgba(255, 255, 255, 0.88);
	}

	.stats {
		display: flex;
		gap: clamp(40px, 6vw, 110px);
		margin: 30px 0 0;
	}

	.stat-label {
		display: block;
		font-size: 17px;
		color: var(--text-dim);
	}

	.stat-value {
		display: block;
		margin-top: 6px;
		font-size: 30px;
		font-weight: 700;
	}

	.stars {
		display: flex;
		align-items: center;
		gap: 6px;
	}

	.stars svg {
		width: 26px;
		height: 26px;
		fill: rgba(255, 255, 255, 0.24);
	}

	.stars svg.on {
		fill: var(--accent);
	}

	.value {
		margin-left: 6px;
		font-size: 22px;
		color: var(--text-dim);
	}

	/* Un jeu en cours de téléchargement le dit ici, sous ses informations. */
	.progress {
		display: flex;
		align-items: center;
		gap: 16px;
		width: 100%;
		margin-top: 24px;
		max-width: 52ch;
	}

	.track {
		flex: 1;
		height: 8px;
		border-radius: 4px;
		background: rgba(255, 255, 255, 0.12);
		overflow: hidden;
	}

	.fill {
		height: 100%;
		border-radius: 4px;
		background: var(--accent);
		transition: width var(--normal) var(--ease);
	}

	.state {
		font-size: 17px;
		color: var(--text-dim);
		white-space: nowrap;
	}

	.actions {
		display: flex;
		gap: 16px;
		margin-top: 36px;
	}

	/* Pilules : JOUER pleine d'accent, les autres en verre. */
	button {
		display: inline-flex;
		align-items: center;
		gap: 12px;
		padding: 18px 34px;
		border-radius: 999px;
		font-size: 22px;
		font-weight: 700;
		transition:
			transform var(--fast) var(--ease),
			background var(--fast) var(--ease);
	}

	.action {
		background: var(--surface-strong);
		backdrop-filter: blur(12px);
	}

	.action.cta {
		padding: 18px 40px;
		background: var(--accent);
		color: var(--on-accent);
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}

	.action img {
		width: 22px;
		height: 22px;
	}

	/* Icônes blanches : foncées sur l'aplat d'accent. */
	.action.cta img {
		filter: brightness(0);
		opacity: 0.85;
	}

	.action.icon img {
		opacity: 0.85;
	}

	.more {
		position: absolute;
		left: 50%;
		bottom: calc(var(--safe-y) + 34px);
		margin: 0;
		transform: translateX(-50%);
		font-size: 18px;
		color: var(--text-dim);
	}

	.more span {
		display: inline-block;
		margin-left: 6px;
		color: var(--accent);
	}

	.media {
		display: flex;
		flex-direction: column;
		gap: 16px;
		height: 100%;
		padding: var(--safe-y) 0 calc(var(--safe-y) + 40px);
		overflow: hidden;
	}

	.media-head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		padding: 0 var(--safe-x);
	}

	.count {
		font-size: 18px;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	/* Toute la largeur de l'écran : les voisines débordent sur les bords, on
	   comprend qu'il y a une suite. */
	.slider {
		flex: none;
		width: 100vw;
		overflow: hidden;
		padding: 18px 0;
	}

	/* Le ruban se décale pour que la diapositive `--i` tombe pile au centre :
	   centre de la diapositive = i × (largeur + écart) + largeur / 2. (Pas
	   `.track` : c'est déjà la barre de progression d'un téléchargement, et
	   ses 8 px de haut écrasaient le ruban.) */
	.reel {
		display: flex;
		gap: var(--slide-gap);
		transform: translateX(
			calc(50vw - var(--i) * (var(--slide-width) + var(--slide-gap)) - var(--slide-width) / 2)
		);
		transition: transform var(--slide-duration) var(--ease);
		will-change: transform;
	}

	.slide {
		position: relative;
		/* Taille explicite : en flex, `aspect-ratio` ne suit pas `flex-basis`
		   et la diapositive retombait à une hauteur nulle. */
		flex: none;
		width: var(--slide-width);
		height: calc(var(--slide-width) * 9 / 16);
		border-radius: var(--radius-lg);
		overflow: hidden;
		background: var(--surface);
		transform: scale(0.84);
		opacity: 0.45;
		filter: brightness(0.7);
		box-shadow: 0 20px 50px rgba(0, 0, 0, 0.5);
		transition:
			transform var(--slide-duration) var(--ease),
			opacity var(--slide-duration) var(--ease),
			filter var(--slide-duration) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	.slide.selected {
		transform: scale(1);
		opacity: 1;
		filter: none;
	}

	/* Contour d'accent seulement quand la sélection est dans le slider. */
	.slide.focused {
		outline: 4px solid var(--accent);
		box-shadow:
			0 0 40px 8px var(--accent-soft),
			0 30px 70px rgba(0, 0, 0, 0.6);
	}

	/* L'image apparaît en fondu une fois décodée : jamais de chargement à vue. */
	.slide > img {
		width: 100%;
		height: 100%;
		object-fit: cover;
		opacity: 0;
		transition: opacity var(--normal) var(--ease);
	}

	.slide > img.ready {
		opacity: 1;
	}

	.dots {
		display: flex;
		justify-content: center;
		gap: 8px;
	}

	.dot {
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--grid-line);
		transition:
			background var(--fast) var(--ease),
			width var(--fast) var(--ease);
	}

	.dot.video {
		background: var(--surface-strong);
	}

	.dot.on {
		width: 24px;
		border-radius: 4px;
		background: var(--accent);
	}

	/* Une vidéo se reconnaît à son bouton de lecture, au centre. */
	.play {
		position: absolute;
		inset: 0;
		display: grid;
		place-items: center;
	}

	.play img {
		width: 72px;
		height: 72px;
		padding: 22px;
		border-radius: 50%;
		background: var(--dock-bg);
		backdrop-filter: blur(10px);
	}

	/* Panneau « Plus sur… » : verre dépoli, comme le dock, sous le slider —
	   description à gauche, fiche technique à droite. */
	.about {
		flex: 1;
		display: grid;
		grid-template-columns: 1.4fr 1fr;
		grid-template-rows: auto auto 1fr;
		column-gap: 36px;
		row-gap: 6px;
		min-height: 0;
		margin: 0 var(--safe-x);
		padding: 26px 28px;
		border-radius: var(--radius-lg);
		background: var(--dock-bg);
		border: 1px solid var(--dock-border);
		backdrop-filter: blur(18px);
		overflow: hidden;
	}

	.caption {
		font-size: 17px;
		font-weight: 600;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--text-dim);
	}

	.about h2 {
		margin: 0 0 6px;
		font-size: 30px;
		font-weight: 700;
	}

	.about > .caption,
	.about h2,
	.text {
		grid-column: 1;
	}

	.text {
		display: -webkit-box;
		-webkit-line-clamp: 4;
		line-clamp: 4;
		-webkit-box-orient: vertical;
		overflow: hidden;
		margin: 0 0 16px;
		font-size: 18px;
		line-height: 1.5;
		color: rgba(255, 255, 255, 0.86);
	}

	dl {
		grid-column: 2;
		grid-row: 1 / -1;
		align-self: start;
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 16px 20px;
		margin: 0;
		padding-left: 28px;
		border-left: 1px solid var(--dock-border);
	}

	dd {
		margin: 4px 0 0;
		font-size: 18px;
	}

	.none {
		grid-column: 1 / -1;
		font-size: 18px;
		color: var(--text-dim);
	}

	/* Le halo suit la sélection : un seul bouton actif à la fois. JOUER garde
	   son aplat d'accent ; les autres s'éclaircissent. */
	.action.focus-ring {
		transform: scale(1.05);
	}

	.action:not(.cta).focus-ring {
		background: var(--detail-button-focus);
		color: var(--text);
	}
</style>
