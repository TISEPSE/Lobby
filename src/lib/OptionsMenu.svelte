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
	}: { actions: TileAction[]; index?: number; open?: boolean; game?: Game | null } = $props();
</script>

{#if open}
	<div class="veil">
		<section class="menu">
			{#if game}
				<header>
					<div class="cover"><Cover {game} /></div>
					<div class="titles">
						<span class="store">{platformOf(game)}</span>
						<h2>{game.title}</h2>
						<span class="sub">Options du jeu</span>
					</div>
				</header>
			{/if}

			<div class="rows">
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
				<span class="hint"><Glyph button="b" size="28px" />Fermer</span>
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
		background: var(--xbox-veil);
		backdrop-filter: blur(6px);
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
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 20px 20px;
	}

	.row {
		position: relative;
		display: flex;
		align-items: center;
		gap: 16px;
		height: var(--options-row);
		padding: 0 18px;
		border-radius: var(--xbox-radius);
		background: var(--xbox-row);
		animation: row-in var(--normal) var(--ease) backwards;
		animation-delay: calc(var(--i) * 30ms);
		transition:
			transform var(--fast) var(--ease),
			background var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	/* Sélection : contour vert et halo, comme tous les autres boutons ; la
	   ligne s'éclaircit et grossit à peine. */
	.row.selected {
		background: var(--surface-strong);
		box-shadow:
			0 0 0 3px var(--accent),
			0 0 28px 4px var(--accent-soft);
		transform: scale(1.02);
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
