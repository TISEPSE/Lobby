<script lang="ts">
	import type { Game } from './types';
	import { details, ensureDetails, coverOf } from './steam.svelte.js';
	import { downloadFor, phaseLabel, sizeText } from './downloads.svelte.js';
	import { generateProceduralCover } from './art';

	/**
	 * Fiche d'un jeu. La jaquette arrive depuis sa place sur l'accueil : le
	 * navigateur anime lui-même le changement de position via `view-transition`,
	 * on n'a pas à mesurer le rectangle de départ comme en Godot.
	 */
	let {
		game,
		favorite = false,
		selected = 0,
		playtime = 'Jamais joué',
	}: { game: Game; favorite?: boolean; selected?: number; playtime?: string } = $props();

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
	const summary = $derived(
		sheet?.summary ||
			(sheet ? 'Pas de résumé pour ce jeu.' : 'Récupération de la fiche auprès de Steam…')
	);
</script>

<div class="detail">
	<img
		class="cover"
		src={(game.appid ? coverOf(game.appid, game.cover) : '') || game.cover || generateProceduralCover(game.title, game.source)}
		alt={game.title}
		style="view-transition-name: cover-{game.id}"
		onerror={(e) => {
			(e.currentTarget as HTMLImageElement).src = generateProceduralCover(game.title, game.source);
		}}
	/>

	<div class="info">
		<h1>{game.title}</h1>
		<p class="facts">{facts.join('  ·  ')}</p>

		{#if rating > 0}
		<div class="stars" aria-label="Note {rating} sur 5">
			{#each [0, 1, 2, 3, 4] as i}
				<svg viewBox="0 0 640 640" class:on={rating >= i + 0.5}>
					<path
						d="M341.5 45.1C337.4 37.1 329.1 32 320.1 32C311.1 32 302.8 37.1 298.7 45.1L225.1 189.3L65.2 214.7C56.3 216.1 48.9 222.4 46.1 231C43.3 239.6 45.6 249 51.9 255.4L166.3 369.9L141.1 529.8C139.7 538.7 143.4 547.7 150.7 553C158 558.3 167.6 559.1 175.7 555L320.1 481.6L464.4 555C472.4 559.1 482.1 558.3 489.4 553C496.7 547.7 500.4 538.8 499 529.8L473.7 369.9L588.1 255.4C594.5 249 596.7 239.6 593.9 231C591.1 222.4 583.8 216.1 574.8 214.7L415 189.3L341.5 45.1z"
					/>
				</svg>
			{/each}
			<span class="value">{rating.toFixed(1)}</span>
		</div>
		{/if}

		<p class="synopsis">{summary}</p>

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
			<button class="action" class:focus-ring={selected === 0}>Jouer</button>
			<button class="action ghost" class:focus-ring={selected === 1}>
				{favorite ? 'Retirer des favoris' : 'Ajouter aux favoris'}
			</button>
			<!-- Tout ce qui modifie le jeu (affiche, mise à jour, fichiers) passe
			     par ici : la fiche n'a pas à porter cinq boutons. -->
			<button class="action ghost square" class:focus-ring={selected === 2} title="Options">
				<img src="/assets/icons/settings.svg" alt="" />
				Options
			</button>
		</div>
	</div>
</div>

<style>
	.detail {
		position: relative;
		z-index: 1;
		display: grid;
		grid-template-columns: clamp(220px, 19vw, 330px) 1fr;
		gap: clamp(32px, 4vw, 72px);
		align-content: center;
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

	.cover {
		width: 100%;
		aspect-ratio: 2 / 3;
		object-fit: cover;
		border-radius: var(--radius-lg);
		box-shadow: 0 30px 70px rgba(0, 0, 0, 0.65);
		align-self: center;
	}

	.info {
		align-self: center;
		/* Le titre prend toute la largeur disponible : le brider le cassait en
		   trois lignes alors que la moitié droite de l'écran était vide. */
		max-width: none;
		padding-right: 4vw;
	}

	h1 {
		margin: 0;
		font-size: clamp(42px, 4.6vw, 80px);
		font-weight: 700;
		line-height: 1.04;
		letter-spacing: -0.025em;
		text-wrap: balance;
	}

	.facts {
		margin: 10px 0 0;
		font-size: 21px;
		color: var(--text-dim);
	}

	.stars {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-top: 14px;
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
		font-size: 20px;
		color: var(--text-dim);
	}

	/* Le résumé, lui, garde une largeur de lecture : une ligne trop longue se
	   lit mal, même sur grand écran. */
	.synopsis {
		margin: 22px 0 0;
		max-width: 68ch;
		font-size: 22px;
		line-height: 1.5;
		color: rgba(255, 255, 255, 0.86);
	}

	/* Un jeu en cours de téléchargement le dit ici, sous ses informations. */
	.progress {
		display: flex;
		align-items: center;
		gap: 16px;
		margin-top: 22px;
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
		font-size: 16px;
		color: var(--text-dim);
		white-space: nowrap;
	}

	.actions {
		display: flex;
		gap: 16px;
		margin-top: 34px;
	}

	button {
		padding: 18px 42px;
		border-radius: var(--radius);
		font-size: 22px;
		font-weight: 600;
		transition: transform var(--fast) var(--ease), background var(--fast) var(--ease);
	}

	.action {
		background: var(--surface-strong);
	}

	.ghost {
		background: var(--surface);
		color: var(--text-dim);
	}

	.square {
		display: inline-flex;
		align-items: center;
		gap: 10px;
		padding: 18px 28px;
	}

	.square img {
		width: 22px;
		height: 22px;
		opacity: 0.85;
	}

	/* Le halo suit la sélection : un seul bouton actif à la fois. */
	.action.focus-ring {
		background: var(--surface-strong);
		color: var(--text);
	}
</style>
