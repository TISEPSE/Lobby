<script lang="ts">
	/**
	 * Menu d'options d'un jeu, en fenêtre.
	 *
	 * Sur l'accueil, les options sortent de la tuile (`TileOptions`). Sur une
	 * fiche ou dans la grille de la bibliothèque, il n'y a pas de tuile à
	 * prolonger (une grille ne peut pas pousser ses voisines) : le menu se pose
	 * au-dessus, avec le nom du jeu concerné.
	 */
	import type { TileAction } from './types';

	let {
		actions,
		index = 0,
		open = false,
		title = '',
	}: { actions: TileAction[]; index?: number; open?: boolean; title?: string } = $props();
</script>

{#if open}
	<div class="veil">
		<section class="menu">
			<h2>Options</h2>
			{#if title}<p class="game">{title}</p>{/if}
			{#each actions as action, i}
				<div class="row" class:selected={i === index}>
					<span class="mark">
						<img src="/assets/icons/{action.icon}.svg" alt="" />
					</span>
					<span class="label">{action.label}</span>
				</div>
			{/each}
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
		background: rgba(0, 0, 0, 0.6);
		backdrop-filter: blur(8px);
		animation: fade-in var(--fast) var(--ease) both;
	}

	.menu {
		display: flex;
		flex-direction: column;
		gap: 10px;
		width: min(460px, 80vw);
		padding: 26px;
		border-radius: var(--radius);
		background: var(--surface-strong);
		box-shadow: 0 30px 80px rgba(0, 0, 0, 0.7);
		animation: rise var(--normal) var(--ease) both;
	}

	.game {
		margin: -8px 0 8px;
		font-size: 18px;
		color: var(--text-dim);
	}

	h2 {
		margin: 0 0 6px;
		font-size: 24px;
		font-weight: 700;
	}

	/* Mêmes lignes que le tiroir de l'accueil : une option se lit pareil
	   partout. */
	.row {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: 12px 14px;
		border-radius: var(--radius);
		background: rgba(255, 255, 255, 0.05);
		transition:
			background var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	.row.selected {
		background: rgba(255, 255, 255, 0.12);
		box-shadow:
			0 0 0 2px var(--accent),
			0 0 22px 4px var(--accent-soft);
	}

	.mark {
		display: grid;
		place-items: center;
		flex: 0 0 auto;
		width: 40px;
		height: 40px;
		border-radius: 50%;
		background: rgba(255, 255, 255, 0.07);
	}

	.row.selected .mark {
		background: var(--accent-soft);
	}

	.mark img {
		width: 20px;
		height: 20px;
		opacity: 0.9;
	}

	.label {
		font-size: 18px;
		font-weight: 600;
	}

	@keyframes fade-in {
		from {
			opacity: 0;
		}
	}

	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(12px);
		}
	}
</style>
