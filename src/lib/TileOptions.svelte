<script lang="ts">
	/**
	 * Menu d'options d'un jeu, qui sort à droite de sa tuile et **pousse** les
	 * suivantes. Il vit dans la rangée, pas au-dessus : rien n'est recouvert, on
	 * voit toujours quelle tuile est concernée.
	 */
	import type { TileAction } from './types';

	let {
		actions,
		index,
		open,
	}: { actions: TileAction[]; index: number; open: boolean } = $props();
</script>

<div class="panel" class:open>
	<div class="inner">
		{#each actions as action, i}
			<div class="row" class:selected={i === index}>
				<span class="mark">
					<img src="/assets/icons/{action.icon}.svg" alt="" />
				</span>
				<span class="text">
					<span class="label">{action.label}</span>
					{#if action.hint}<span class="hint">{action.hint}</span>{/if}
				</span>
			</div>
		{/each}
	</div>
</div>

<style>
	/* Le panneau est un tiroir qui sort de la tuile : il se colle à son bord
	   droit, reprend sa hauteur, son contour et ses coins, et pousse les tuiles
	   suivantes en animant sa largeur. Tuile et panneau forment un seul bloc. */
	.panel {
		flex: 0 0 auto;
		width: 0;
		overflow: hidden;
		/* Annule l'espacement de la rangée, la marge d'écartement de la tuile
		   sélectionnée, et le contour : la jonction devient invisible. */
		margin-left: calc(
			-18px - var(--tile) * (var(--tile-focus-scale) - 1) / 2 - 3px
		);
		height: calc(var(--tile) * 1.5 * var(--tile-focus-scale));
		align-self: flex-end;
		border-radius: 0 var(--radius) var(--radius) 0;
		background: linear-gradient(100deg, #10141a 0%, #0c0f14 100%);
		box-shadow:
			inset 3px 0 0 rgba(34, 211, 102, 0.25),
			0 0 0 3px var(--accent),
			0 0 34px 6px var(--accent-soft),
			0 26px 60px rgba(0, 0, 0, 0.6);
		transition: width var(--normal) var(--ease);
	}

	.panel.open {
		width: 330px;
	}

	.inner {
		display: flex;
		flex-direction: column;
		justify-content: center;
		gap: 10px;
		width: 330px;
		height: 100%;
		/* Décalé de la largeur du raccord : le contenu commence après la tuile. */
		padding: 16px 16px 16px 26px;
	}

	.row {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: 11px 14px;
		border-radius: var(--radius);
		background: rgba(255, 255, 255, 0.04);
		transition:
			background var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease),
			transform var(--fast) var(--ease);
	}

	.row.selected {
		background: rgba(255, 255, 255, 0.12);
		transform: translateX(3px);
		box-shadow: inset 0 0 0 2px var(--accent);
	}

	.mark {
		display: grid;
		place-items: center;
		flex: 0 0 auto;
		width: 38px;
		height: 38px;
		border-radius: 50%;
		background: rgba(255, 255, 255, 0.07);
	}

	.row.selected .mark {
		background: var(--accent-soft);
	}

	.mark img {
		width: 19px;
		height: 19px;
		opacity: 0.9;
	}

	.text {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}

	.label {
		font-size: 17px;
		font-weight: 600;
		white-space: nowrap;
	}

	.hint {
		font-size: 13px;
		color: var(--text-dim);
		white-space: nowrap;
	}
</style>
