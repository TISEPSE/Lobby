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
	/* La largeur est animée : ce sont les tuiles suivantes qui s'écartent. */
	.panel {
		flex: 0 0 auto;
		width: 0;
		overflow: hidden;
		align-self: stretch;
		transition: width var(--normal) var(--ease);
	}

	.panel.open {
		width: 320px;
	}

	.inner {
		display: flex;
		flex-direction: column;
		justify-content: center;
		gap: 8px;
		width: 320px;
		height: 100%;
		padding: 14px 14px 14px 20px;
	}

	.row {
		display: flex;
		align-items: center;
		gap: 14px;
		padding: 12px 14px;
		border-radius: var(--radius);
		background: rgba(255, 255, 255, 0.05);
		transition:
			background var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease),
			transform var(--fast) var(--ease);
	}

	.row.selected {
		background: rgba(255, 255, 255, 0.12);
		transform: translateX(3px);
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
