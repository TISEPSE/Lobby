<script lang="ts">
	import { downloads, phaseLabel, sizeText } from './downloads.svelte.js';

	/**
	 * Bandeau des téléchargements en cours, au-dessus de la barre d'aide.
	 * Il n'apparaît que lorsqu'il se passe quelque chose : une console ne montre
	 * pas une barre vide en permanence.
	 */
	const first = $derived(downloads.list[0]);
	const others = $derived(Math.max(0, downloads.list.length - 1));
</script>

{#if first}
	<aside class="download">
		<img class="icon" src="/assets/icons/download.svg" alt="" />
		<div class="text">
			<span class="title">{first.title}</span>
			<span class="detail">
				{phaseLabel(first)}
				{#if sizeText(first)}· {sizeText(first)}{/if}
				{#if others > 0}· et {others} autre{others > 1 ? 's' : ''}{/if}
			</span>
		</div>
		<div class="track">
			<div class="fill" style="width: {Math.max(2, first.percent)}%"></div>
		</div>
		<span class="percent">{Math.round(first.percent)} %</span>
	</aside>
{/if}

<style>
	.download {
		position: fixed;
		z-index: 4;
		right: var(--safe-x);
		bottom: calc(var(--safe-y) * 0.45);
		display: flex;
		align-items: center;
		gap: 16px;
		width: min(520px, 38vw);
		padding: 12px 18px;
		border-radius: var(--radius);
		background: rgba(255, 255, 255, 0.07);
		backdrop-filter: blur(14px);
		box-shadow: 0 18px 40px rgba(0, 0, 0, 0.5);
		animation: rise var(--normal) var(--ease) both;
	}

	.icon {
		width: 24px;
		height: 24px;
		opacity: 0.8;
		flex: 0 0 auto;
	}

	.text {
		display: flex;
		flex-direction: column;
		min-width: 0;
		flex: 1;
	}

	.title {
		font-size: 17px;
		font-weight: 600;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.detail {
		font-size: 13px;
		color: var(--text-dim);
		white-space: nowrap;
	}

	.track {
		flex: 0 0 120px;
		height: 6px;
		border-radius: 3px;
		background: rgba(255, 255, 255, 0.12);
		overflow: hidden;
	}

	.fill {
		height: 100%;
		border-radius: 3px;
		background: var(--accent);
		transition: width var(--normal) var(--ease);
	}

	.percent {
		font-size: 15px;
		font-variant-numeric: tabular-nums;
		color: var(--text-dim);
	}

	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(10px);
		}
	}
</style>
