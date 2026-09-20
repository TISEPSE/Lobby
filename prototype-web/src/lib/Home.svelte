<script lang="ts">
	import type { Game } from './types';

	/**
	 * Accueil : artwork plein écran, rangée horizontale de jaquettes. La tuile
	 * sélectionnée s'agrandit et **pousse** ses voisines plutôt que de les
	 * recouvrir — c'est le `gap` qui s'élargit autour d'elle.
	 */
	let {
		games,
		index,
		clock,
	}: { games: Game[]; index: number; clock: string } = $props();

	const selected = $derived(games[index]);

	/** Toutes les jaquettes Steam n'existent pas en format vertical : on retombe
	 *  sur la bannière horizontale plutôt que d'afficher une case vide. */
	function fallback(event: Event, game: Game) {
		const img = event.currentTarget as HTMLImageElement;
		const header = `https://cdn.cloudflare.steamstatic.com/steam/apps/${game.appid}/header.jpg`;
		if (img.src !== header) img.src = header;
	}
</script>

<header class="top">
	<div class="profile">
		<div class="avatar">J</div>
		<div>
			<div class="name">Joueur</div>
			<div class="stat">{games.length} jeux installés</div>
		</div>
	</div>
	<nav class="sections">
		<span class="section active">Accueil</span>
		<span class="section">Bibliothèque</span>
		<span class="section">Recherche</span>
		<span class="section">Réglages</span>
	</nav>
	<div class="clock">{clock}</div>
</header>

<section class="stage">
	{#if selected}
		<div class="headline">
			<h1>{selected.title}</h1>
			<p class="facts">Installé · Prêt à jouer</p>
		</div>
	{/if}

	<div class="rail" style="--index: {index}">
		{#each games as game, i (game.id)}
			<button
				class="tile"
				class:selected={i === index}
				style="--i: {i}"
				aria-current={i === index}
			>
				<img src={game.cover} alt={game.title} onerror={(e) => fallback(e, game)} />
				<span class="caption">{game.title}</span>
			</button>
		{/each}
	</div>
</section>

<style>
	.top {
		position: relative;
		z-index: 2;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 32px;
		padding: var(--safe-y) var(--safe-x) 0;
	}

	.profile {
		display: flex;
		align-items: center;
		gap: 14px;
	}

	.avatar {
		display: grid;
		place-items: center;
		width: 46px;
		height: 46px;
		border-radius: 50%;
		background: var(--accent);
		color: #06210f;
		font-size: 24px;
		font-weight: 700;
	}

	.name {
		font-size: 22px;
		font-weight: 600;
	}

	.stat {
		font-size: 15px;
		color: var(--text-dim);
	}

	.sections {
		display: flex;
		gap: 28px;
	}

	.section {
		font-size: 17px;
		color: var(--text-dim);
		padding-bottom: 6px;
		border-bottom: 2px solid transparent;
	}

	.section.active {
		color: var(--text);
		border-color: var(--accent);
	}

	.clock {
		font-size: 22px;
		font-variant-numeric: tabular-nums;
	}

	.stage {
		position: relative;
		z-index: 1;
		display: flex;
		flex-direction: column;
		justify-content: flex-end;
		height: calc(100% - 120px);
		padding: 0 0 var(--safe-y);
	}

	.headline {
		padding: 0 var(--safe-x);
		margin-bottom: 4vh;
	}

	h1 {
		margin: 0;
		font-size: clamp(38px, 4.4vw, 76px);
		font-weight: 700;
		letter-spacing: -0.02em;
		/* Le titre suit la sélection sans clignoter : il glisse. */
		animation: rise var(--normal) var(--ease) both;
	}

	.facts {
		margin: 8px 0 0;
		font-size: 19px;
		color: var(--text-dim);
	}

	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(14px);
		}
	}

	.rail {
		display: flex;
		align-items: flex-end;
		gap: 18px;
		padding: 40px 0 0;
		/* La sélection reste au centre de l'écran : la rangée glisse sous elle. */
		transform: translateX(calc(50vw - (var(--index) + 0.5) * (var(--tile) + 18px)));
		transition: transform var(--normal) var(--ease);
		will-change: transform;
	}

	.tile {
		position: relative;
		flex: 0 0 var(--tile);
		width: var(--tile);
		aspect-ratio: 2 / 3;
		padding: 0;
		border-radius: var(--radius);
		overflow: hidden;
		background: var(--surface);
		transform-origin: center bottom;
		transition:
			transform var(--normal) var(--ease),
			box-shadow var(--normal) var(--ease),
			margin var(--normal) var(--ease);
		box-shadow: 0 12px 30px rgba(0, 0, 0, 0.45);
	}

	/* La tuile agrandie écarte ses voisines au lieu de passer par-dessus. */
	.tile.selected {
		transform: scale(var(--tile-focus-scale));
		margin: 0 calc(var(--tile) * (var(--tile-focus-scale) - 1) / 2);
		outline: 3px solid var(--accent);
		box-shadow:
			0 0 34px 6px var(--accent-soft),
			0 26px 60px rgba(0, 0, 0, 0.6);
	}

	.tile img {
		width: 100%;
		height: 100%;
		object-fit: cover;
		display: block;
	}

	.caption {
		position: absolute;
		inset: auto 0 0;
		padding: 26px 10px 10px;
		font-size: 14px;
		font-weight: 600;
		text-align: center;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.88), transparent);
	}
</style>
