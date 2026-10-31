<script lang="ts">
	/**
	 * Options d'un jeu, en fenêtre façon Xbox — la même partout (accueil,
	 * bibliothèque, fiche). En tête, la jaquette et le nom du jeu : on sait
	 * toujours de quel jeu il s'agit. Les lignes entrent l'une après l'autre ;
	 * la ligne sélectionnée porte le contour vert des autres boutons (palette `--xbox-*`).
	 */
	import type { Game, TileAction } from './types';
	import Cover from './Cover.svelte';
	import Glyph from './Glyph.svelte';
	import { platformOf } from './stats';

	let {
		actions,
		index = 0,
		open = false,
		game = null,
		subtitle = 'Options du jeu',
		backLabel = 'Fermer',
		floating = false,
	}: {
		actions: TileAction[];
		index?: number;
		open?: boolean;
		game?: Game | null;
		/** Sous le nom du jeu (« En cours » pour le menu du jeu). */
		subtitle?: string;
		/** Ce que fait B (« Revenir au jeu » pour le menu du jeu). */
		backLabel?: string;
		/**
		 * Posé sur une partie (fenêtre transparente) : voile léger et panneau
		 * translucide, le jeu reste visible derrière.
		 */
		floating?: boolean;
	} = $props();
</script>

{#if open}
	<div class="veil" class:floating>
		<section class="menu">
			{#if game}
				<header>
					<div class="cover"><Cover {game} /></div>
					<div class="titles">
						<span class="store">{platformOf(game)}</span>
						<h2>{game.title}</h2>
						<span class="sub">{subtitle}</span>
					</div>
				</header>
			{/if}

			<div class="rows" style="--index: {index}">
				<span class="glider"></span>
				{#each actions as action, i (action.id)}
					<div class="row" class:selected={i === index} style="--i: {i}">
						<span class="mark">
							<img src="/assets/icons/{action.icon}.svg" alt="" />
						</span>
						<span class="label">{action.label}</span>
					</div>
				{/each}
			</div>

			<footer class="hints">
				<span class="hint"><Glyph button="a" size="28px" />Choisir</span>
				<span class="hint"><Glyph button="b" size="28px" />{backLabel}</span>
			</footer>
		</section>
	</div>
{/if}

<style>
	.veil {
		position: fixed;
		inset: 0;
		z-index: 7;
		display: grid;
		place-items: center;
		/* Pas de flou derrière une liste animée : sans carte graphique, il divise
		   par quatre le nombre d'images de chaque déplacement. */
		background: var(--xbox-veil);
		animation: fade-in var(--fast) var(--ease) both;
	}

	/* Panneau plein, gris presque noir, coins à peine arrondis : pas de verre
	   dépoli, c'est le sombre mat des menus Xbox. */
	.menu {
		display: flex;
		flex-direction: column;
		width: var(--options-width);
		border: 1px solid var(--xbox-line);
		border-radius: var(--xbox-radius);
		background: var(--xbox-panel);
		box-shadow: 0 30px 90px rgba(0, 0, 0, 0.8);
		overflow: hidden;
		animation: rise var(--normal) var(--ease) both;
	}

	header {
		display: flex;
		align-items: center;
		gap: 20px;
		padding: 28px 30px 24px;
		border-bottom: 1px solid var(--xbox-line);
	}

	/* `Cover` remplit son parent (position absolue) : ce cadre le contient. */
	.cover {
		position: relative;
		flex: none;
		width: var(--options-cover);
		aspect-ratio: 2 / 3;
		border-radius: var(--xbox-radius);
		overflow: hidden;
	}

	.titles {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}

	.store {
		font-size: 17px;
		font-weight: 700;
		letter-spacing: 0.06em;
		text-transform: uppercase;
		color: var(--accent);
	}

	h2 {
		margin: 0;
		font-size: 28px;
		font-weight: 600;
		line-height: 1.15;
		overflow: hidden;
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
	}

	.sub {
		font-size: 17px;
		color: var(--text-dim);
	}

	.rows {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--options-gap);
		padding: var(--options-pad);
		isolation: isolate;
	}

	/* Sélection : contour vert et halo, comme tous les autres boutons ; le
	   cadre glisse d'une ligne à l'autre, plus clair, et grossit à peine. */
	.glider {
		top: var(--options-pad);
		left: var(--options-pad);
		right: var(--options-pad);
		height: var(--options-row);
		--glide-y: calc(var(--index) * (var(--options-row) + var(--options-gap)));
		--glide-scale: 1.02;
		border-radius: var(--xbox-radius);
		background: var(--surface-strong);
		box-shadow:
			0 0 0 3px var(--accent),
			0 0 28px 4px var(--accent-soft);
	}

	.row {
		display: flex;
		align-items: center;
		gap: 16px;
		height: var(--options-row);
		padding: 0 18px;
		border-radius: var(--xbox-radius);
		background: var(--xbox-row);
		animation: row-in var(--normal) var(--ease) backwards;
		animation-delay: calc(var(--i) * 30ms);
		transition: background var(--fast) var(--ease);
	}

	.row.selected {
		background: transparent;
	}

	.mark,
	.label {
		position: relative;
		z-index: 1;
	}

	.mark {
		display: grid;
		place-items: center;
		flex: none;
		width: 28px;
		height: 28px;
	}

	.mark img {
		width: 22px;
		height: 22px;
		opacity: 0.85;
	}

	.row.selected .mark img {
		opacity: 1;
	}

	.label {
		font-size: 19px;
		font-weight: 600;
	}

	.hints {
		display: flex;
		justify-content: flex-end;
		gap: 28px;
		padding: 18px 30px;
		border-top: 1px solid var(--xbox-line);
		font-size: 17px;
		color: var(--text-dim);
	}

	.hint {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	/* Sur le jeu : on le devine derrière un voile léger, à travers un panneau
	   translucide au liseré clair, qui entre en glissant un peu plus. */
	.veil.floating {
		background: var(--overlay-veil);
	}

	.floating .menu {
		background: linear-gradient(160deg, var(--overlay-panel-top), var(--overlay-panel-bottom));
		border-color: var(--overlay-line);
		box-shadow:
			0 30px 90px rgba(0, 0, 0, 0.6),
			inset 0 1px 0 var(--overlay-line);
		animation: float-in var(--normal) var(--ease) both;
	}

	.floating header,
	.floating .hints {
		border-color: var(--overlay-line);
	}

	.floating .row {
		background: var(--overlay-row);
	}

	.floating .row.selected {
		background: transparent;
	}

	.floating .glider {
		background: var(--overlay-row-selected);
	}

	@keyframes float-in {
		from {
			opacity: 0;
			transform: translateY(24px) scale(0.96);
		}
	}

	@keyframes fade-in {
		from {
			opacity: 0;
		}
	}

	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(18px) scale(0.98);
		}
	}

	@keyframes row-in {
		from {
			opacity: 0;
			transform: translateX(-12px);
		}
	}
</style>
