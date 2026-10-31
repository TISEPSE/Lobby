<script lang="ts">
	import type { Game } from './types';
	import Cover from './Cover.svelte';
	import Glyph from './Glyph.svelte';
	import type { Action } from './gamepad';
	import { sessions, playtimeOf } from './library.svelte.js';
	import { details, ensureDetails } from './steam.svelte.js';
	import { activity, formatMinutes, platformOf, rankByPlaytime } from './stats';

	/**
	 * Profil, à la manière de celui d'une Xbox, sur sa propre page : la carte
	 * d'identité à gauche, ce que dit le temps de jeu à droite.
	 *
	 * Pas de bouton « Modifier » : la **photo** et le **pseudo** se
	 * sélectionnent eux-mêmes au joystick, A les modifie. Suivent les comptes
	 * (Steam, Epic Games) et les statistiques détaillées. Tout se parcourt en
	 * haut / bas ; le reste de la page se lit.
	 */
	let {
		games,
		profileName,
		avatar = '',
		steamPersona = '',
		steamAvatar = '',
		epicName = '',
		epicPending = false,
		epicError = '',
		epicGamesCount = 0,
		epicConnected = false,
		steamLibraryCount = 0,
		steamLibraryDate = 0,
		steamLibraryPending = false,
		onSteamLibraryLogin,
		onSteamLibraryForget,
		focused = true,
		onEditName,
		onChangeAvatar,
		onEpicLogin,
		onEpicRefresh,
		onEpicLogout,
		onOpenStats,
		onBack,
	}: {
		games: Game[];
		profileName: string;
		avatar?: string;
		/** Compte Steam de la machine ; vide s'il n'y en a pas. */
		steamPersona?: string;
		steamAvatar?: string;
		/** Une session Epic existe. */
		epicConnected?: boolean;
		/** Pseudo du compte Epic ; vide sans connexion, ou pour un compte sans pseudo. */
		epicName?: string;
		epicPending?: boolean;
		epicError?: string;
		epicGamesCount?: number;
		/** Bibliothèque Steam complète (connexion) : nombre de jeux et date (ms). */
		steamLibraryCount?: number;
		steamLibraryDate?: number;
		steamLibraryPending?: boolean;
		onSteamLibraryLogin?: () => void;
		onSteamLibraryForget?: () => void;
		focused?: boolean;
		onEditName?: () => void;
		onChangeAvatar?: () => void;
		onEpicLogin?: () => void;
		onEpicRefresh?: () => void;
		onEpicLogout?: () => void;
		onOpenStats?: () => void;
		onBack?: () => void;
	} = $props();

	type Entry = 'avatar' | 'name' | 'steam' | 'epic' | 'stats';

	/** Ordre de parcours, de haut en bas. */
	const entries = $derived<Entry[]>([
		'avatar',
		'name',
		'steam',
		'epic',
		'stats',
	]);

	let index = $state(0);

	const total = $derived(games.reduce((sum, game) => sum + playtimeOf(game.id), 0));
	const played = $derived(games.filter((game) => playtimeOf(game.id) > 0).length);
	const months = $derived(activity(sessions, 'all'));
	const monthPeak = $derived(Math.max(1, ...months.map((m) => m.minutes)));

	const genres = $derived(
		rankByPlaytime(
			games,
			(game) => playtimeOf(game.id),
			(game) => (game.appid ? (details[game.appid]?.genres ?? []) : [])
		)
	);
	const platforms = $derived(
		rankByPlaytime(games, (game) => playtimeOf(game.id), (game) => [platformOf(game)])
	);
	/** Les jeux qui ont le plus de temps de jeu, Steam compris. */
	const favorites = $derived(
		games
			.filter((game) => playtimeOf(game.id) > 0)
			.sort((a, b) => playtimeOf(b.id) - playtimeOf(a.id))
			.slice(0, 8)
	);
	const genreTotal = $derived(genres.reduce((sum, g) => sum + g.minutes, 0) || 1);
	const platformTotal = $derived(platforms.reduce((sum, p) => sum + p.minutes, 0) || 1);

	// Les genres viennent des fiches Steam : on les demande pour les jeux joués.
	$effect(() => {
		for (const game of games) {
			if (game.appid && playtimeOf(game.id) > 0) ensureDetails(game.appid);
		}
	});

	const current = $derived(entries[Math.min(index, entries.length - 1)]);
	const isOn = (entry: Entry) => focused && current === entry;

	const epicWho = $derived(epicName || 'Connecté');
	/** Epic refuse la session, ou ne répond pas : deux problèmes, deux messages. */
	const epicProblem = $derived(epicError.includes('refusé') ? 'session expirée' : 'Epic injoignable');
	const epicLabel = $derived(
		epicPending
			? 'Connexion…'
			: epicConnected
				? epicError
					? `${epicWho} · ${epicProblem}`
					: `${epicWho} · ${epicGamesCount} jeu${epicGamesCount > 1 ? 'x' : ''}`
				: 'Non connecté'
	);
	/**
	 * Une seule tuile Steam : le compte et sa bibliothèque. Connectée, elle dit
	 * combien de jeux. Rien à « synchroniser » à la main : les jeux installés
	 * sont rescannés et les comptes relus à chaque démarrage.
	 */
	const steamLabel = $derived(
		steamLibraryPending
			? 'Connexion…'
			: steamLibraryCount > 0
				? `${steamPersona ? steamPersona + ' · ' : ''}${steamLibraryCount} jeux`
				: steamPersona
					? `${steamPersona} · connecte-toi pour toute ta bibliothèque`
					: 'Non connecté'
	);

	/**
	 * Ce que fait A sur la tuile Epic : se connecter, ou se reconnecter si la
	 * session a expiré. Connectée, rien : le compte est relu au démarrage.
	 */
	const epicAction = $derived(
		epicPending ? '' : epicConnected ? (epicError ? 'Se reconnecter' : '') : 'Se connecter'
	);

	export function selectionKey(): string {
		return String(index);
	}

	export function handleAction(action: Action) {
		if (action === 'up') index = Math.max(0, index - 1);
		else if (action === 'down') index = Math.min(entries.length - 1, index + 1);
		else if (action === 'cancel') onBack?.();
		else if (action === 'options' && current === 'epic' && epicConnected && !epicPending) onEpicLogout?.();
		else if (action === 'options' && current === 'steam' && steamLibraryCount > 0) onSteamLibraryForget?.();
		else if (action === 'accept') {
			if (current === 'avatar') onChangeAvatar?.();
			else if (current === 'name') onEditName?.();
			// Connecté, A ne fait rien : comptes et jeux se mettent à jour au démarrage.
			else if (current === 'steam' && steamLibraryCount === 0) onSteamLibraryLogin?.();
			else if (current === 'epic' && epicAction) onEpicLogin?.();
			else if (current === 'stats') onOpenStats?.();
		}
	}

	function percent(minutes: number, sum: number): string {
		return `${Math.round((minutes / sum) * 100)} %`;
	}
</script>

<section class="profile">
	<aside class="card identity">
		<!-- La photo est elle-même la commande : sélectionnée, A la change. Son
		     contour de sélection est rond, comme elle. -->
		<div class="avatar" class:selected={isOn('avatar')}>
			{#if avatar}
				<img src={avatar} alt="" />
			{:else}
				<span>{profileName.charAt(0).toUpperCase()}</span>
			{/if}
			<span class="presence"></span>
		</div>

		<p class="status">
			<span class="online">En ligne</span>
			{#if steamPersona || epicConnected}
				<span class="network"> · {[steamPersona && 'Steam', epicConnected && 'Epic Games'].filter(Boolean).join(' · ')}</span>
			{/if}
		</p>

		<div class="pseudo" class:selected={isOn('name')}>
			<h1>{profileName}</h1>
			{#if isOn('name')}
				<!-- Le bouton se lit sur l'élément : son glyphe, pas la lettre écrite. -->
				<span class="edit"><Glyph button="a" size="28px" />Modifier</span>
			{/if}
		</div>

		<span class="caption accounts-title">Comptes</span>
		<ul class="tiles">
			<!-- Steam : le compte et toute sa bibliothèque, une seule tuile. La
			     connexion (QR code ou identifiants) sert une fois à lire la liste
			     des jeux ; la session est ensuite effacée. -->
			<li class:selected={isOn('steam')}>
				<span class="brand">
					<img class="logo" src="/assets/icons/steam.svg" alt="Steam" />
					{#if steamAvatar}<img class="badge-avatar" src={steamAvatar} alt="" />{/if}
				</span>
				<span class="text">
					<span class="label">Steam</span>
					<span class="hint">{steamLabel}</span>
				</span>
				{#if isOn('steam')}
					<span class="do">
						{#if steamLibraryCount > 0}
							<Glyph button="x" size="26px" />Déconnecter
						{:else}
							<Glyph button="a" size="26px" />Se connecter
						{/if}
					</span>
				{/if}
			</li>
			<li class:selected={isOn('epic')}>
				<span class="brand"><img class="logo" src="/assets/icons/epic.svg" alt="Epic Games" /></span>
				<span class="text">
					<span class="label">Epic Games</span>
					<span class="hint">{epicLabel}</span>
				</span>
				{#if isOn('epic')}
					<span class="do">
						{#if epicAction}<Glyph button="a" size="26px" />{epicAction}{/if}
						{#if epicConnected && !epicPending}<Glyph button="x" size="26px" />Déconnecter{/if}
					</span>
				{/if}
			</li>
			<li class:selected={isOn('stats')}>
				<img class="icon" src="/assets/icons/chart.svg" alt="" />
				<span class="text">
					<span class="label">Statistiques détaillées</span>
					<span class="hint">Calendrier d'activité, périodes, jeux les plus joués</span>
				</span>
				{#if isOn('stats')}
					<span class="do"><Glyph button="a" size="26px" />Ouvrir</span>
				{/if}
			</li>
		</ul>
	</aside>

	<div class="content">
		<div class="card summary">
			<div class="total">
				<span class="caption">Temps de jeu total</span>
				<span class="big">{formatMinutes(total)}</span>
				<span class="sub">{played} jeu{played > 1 ? 'x' : ''} joué{played > 1 ? 's' : ''}</span>
			</div>
			<div class="months">
				<span class="caption">Activité</span>
				<div class="bars">
					{#each months as month}
						<div class="month">
							<div class="track">
								<div
									class="bar"
									class:zero={month.minutes === 0}
									style="--h: {month.minutes / monthPeak}"
								></div>
							</div>
							<span>{month.label.charAt(0).toUpperCase()}</span>
						</div>
					{/each}
				</div>
			</div>
		</div>

		<div class="card">
			<span class="caption">Les plus joués</span>
			{#if favorites.length === 0}
				<p class="none">Lance un jeu : il apparaîtra ici.</p>
			{:else}
				<div class="covers">
					{#each favorites as game (game.id)}
						<div class="cover">
							<div class="art"><Cover {game} /></div>
							<span class="title">{game.title}</span>
							<span class="time">{formatMinutes(playtimeOf(game.id))}</span>
						</div>
					{/each}
				</div>
			{/if}
		</div>

		<div class="split">
			<div class="card">
				<span class="caption">Genres favoris</span>
				{#if genres.length === 0}
					<p class="none">Aucun genre connu pour l'instant.</p>
				{/if}
				{#each genres as entry (entry.item)}
					<div class="row">
						<span class="name">{entry.item}</span>
						<span class="meter"><span style="--w: {entry.minutes / genres[0].minutes}"></span></span>
						<span class="amount">{percent(entry.minutes, genreTotal)}</span>
					</div>
				{/each}
			</div>
			<div class="card">
				<span class="caption">Boutiques</span>
				{#if platforms.length === 0}
					<p class="none">Aucun temps de jeu pour l'instant.</p>
				{/if}
				{#each platforms as entry (entry.item)}
					<div class="row">
						<span class="name">{entry.item}</span>
						<span class="meter"><span style="--w: {entry.minutes / platforms[0].minutes}"></span></span>
						<span class="amount">{percent(entry.minutes, platformTotal)}</span>
					</div>
				{/each}
			</div>
		</div>
	</div>
</section>

<style>
	.profile {
		display: grid;
		grid-template-columns: var(--profile-card) 1fr;
		gap: var(--card-gap);
		height: 100%;
		padding: 1.5vh var(--safe-x) calc(var(--safe-y) + 30px);
	}

	.card {
		border-radius: var(--radius-lg);
		background: var(--dock-bg);
		border: 1px solid var(--dock-border);
		backdrop-filter: blur(18px);
		padding: 26px 28px;
	}

	.identity {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 10px;
		overflow: hidden;
	}

	/* Photo ronde, anneau d'accent, pastille de présence : le repère
	   « connecté » d'une Xbox. Sélectionnée, l'anneau s'épaissit et rayonne —
	   un contour **rond**, jamais un carré autour d'un rond. */
	.avatar {
		position: relative;
		flex: none;
		display: grid;
		place-items: center;
		width: var(--profile-avatar);
		height: var(--profile-avatar);
		margin: 6px 0 4px 6px;
		border-radius: 50%;
		background: var(--accent);
		color: var(--on-accent);
		font-size: 72px;
		font-weight: 700;
		box-shadow: 0 0 0 4px var(--accent-soft);
		transition:
			box-shadow var(--fast) var(--ease),
			transform var(--fast) var(--ease);
	}

	.avatar.selected {
		transform: scale(1.04);
		box-shadow:
			0 0 0 5px var(--accent),
			0 0 40px 10px var(--accent-soft);
	}

	.avatar img {
		width: 100%;
		height: 100%;
		border-radius: 50%;
		object-fit: cover;
	}

	.presence {
		position: absolute;
		right: 10px;
		bottom: 10px;
		width: 30px;
		height: 30px;
		border-radius: 50%;
		background: var(--accent);
		border: 5px solid var(--bg);
	}

	.status {
		margin: 8px 0 0;
		font-size: 19px;
	}

	.online {
		font-weight: 600;
	}

	.network {
		color: var(--text-dim);
	}

	/* Le pseudo, en grand ; sélectionné, il passe dans une pilule d'accent. */
	.pseudo {
		display: flex;
		align-items: baseline;
		gap: 16px;
		max-width: 100%;
		margin-left: -14px;
		padding: 4px 14px 8px;
		border-radius: var(--radius-lg);
		outline: 3px solid transparent;
		transition:
			outline-color var(--fast) var(--ease),
			background var(--fast) var(--ease);
	}

	.pseudo.selected {
		background: var(--surface-strong);
		outline-color: var(--accent);
		box-shadow: 0 0 30px 4px var(--accent-soft);
	}

	h1 {
		margin: 0;
		font-size: clamp(40px, 3.4vw, 60px);
		font-weight: 700;
		letter-spacing: -0.02em;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	/* Glyphe du bouton + action, à droite de l'élément sélectionné. */
	.edit,
	.do {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		flex: none;
		font-size: 17px;
		color: var(--text-dim);
	}

	.do {
		margin-left: auto;
	}

	.do :global(img + img) {
		margin-left: 10px;
	}

	.caption {
		font-size: 17px;
		font-weight: 600;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--text-dim);
	}

	.accounts-title {
		margin-top: auto;
		padding-top: 18px;
	}

	.tiles {
		display: flex;
		flex-direction: column;
		gap: 8px;
		width: 100%;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.tiles li {
		display: flex;
		align-items: center;
		gap: 16px;
		padding: 12px 16px;
		border-radius: var(--radius);
		background: var(--surface);
		outline: 3px solid transparent;
		transition:
			outline-color var(--fast) var(--ease),
			background var(--fast) var(--ease);
	}

	.tiles li.selected {
		background: var(--surface-strong);
		outline-color: var(--accent);
		box-shadow: 0 0 26px 2px var(--accent-soft);
	}

	/* Logo de la boutique dans une pastille ronde ; pour Steam, la photo du
	   compte s'y accroche en médaillon. */
	.brand {
		position: relative;
		display: grid;
		place-items: center;
		flex: none;
		width: 44px;
		height: 44px;
		border-radius: 50%;
		background: var(--surface-strong);
	}

	.brand .logo {
		width: 24px;
		height: 24px;
	}

	.badge-avatar {
		position: absolute;
		right: -4px;
		bottom: -4px;
		width: 22px;
		height: 22px;
		border-radius: 50%;
		object-fit: cover;
		box-shadow: 0 0 0 2px var(--bg);
	}

	.tiles .icon {
		width: 26px;
		height: 26px;
		margin: 0 9px;
		opacity: 0.85;
	}

	.text {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}

	.label {
		font-size: 19px;
		font-weight: 600;
	}

	.hint {
		font-size: 17px;
		color: var(--text-dim);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.content {
		display: flex;
		flex-direction: column;
		gap: var(--card-gap);
		min-height: 0;
	}

	.summary {
		display: grid;
		grid-template-columns: auto 1fr;
		gap: 48px;
		align-items: stretch;
	}

	.total {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	.big {
		font-size: clamp(44px, 3.6vw, 64px);
		font-weight: 700;
		letter-spacing: -0.02em;
		font-variant-numeric: tabular-nums;
	}

	.sub {
		font-size: 18px;
		color: var(--text-dim);
	}

	.months {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}

	.bars {
		flex: 1;
		display: grid;
		grid-template-columns: repeat(12, 1fr);
		gap: var(--bar-gap);
		min-height: 120px;
	}

	.month {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		font-size: 17px;
		color: var(--text-dim);
	}

	.track {
		flex: 1;
		width: 100%;
		display: flex;
		align-items: flex-end;
		justify-content: center;
	}

	.bar {
		width: min(100%, 26px);
		height: calc(var(--h) * 100%);
		border-radius: 4px 4px 0 0;
		background: var(--accent-dim);
	}

	.bar.zero {
		height: 2px;
		background: var(--grid-line);
	}

	.covers {
		display: grid;
		grid-template-columns: repeat(8, 1fr);
		gap: 16px;
		margin-top: 16px;
	}

	.cover {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}

	/* `Cover` se cale en absolu sur son conteneur : il lui faut un repère. */
	.art {
		position: relative;
		aspect-ratio: 2 / 3;
		border-radius: var(--radius);
		overflow: hidden;
		background: var(--surface);
		margin-bottom: 6px;
	}

	.cover .title {
		font-size: 17px;
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.cover .time {
		font-size: 17px;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	.split {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--card-gap);
		min-height: 0;
	}

	.split .caption {
		display: block;
		margin-bottom: 16px;
	}

	.row {
		display: grid;
		grid-template-columns: 9em 1fr 3.5em;
		align-items: center;
		gap: 14px;
		margin-bottom: 12px;
		font-size: 18px;
	}

	.name {
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.meter {
		display: block;
		height: 6px;
		border-radius: 3px;
		background: var(--grid-line);
		overflow: hidden;
	}

	.meter span {
		display: block;
		width: calc(var(--w) * 100%);
		height: 100%;
		border-radius: 3px;
		background: var(--accent);
	}

	.amount {
		text-align: right;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	.none {
		margin: 0;
		font-size: 17px;
		color: var(--text-dim);
	}
</style>
