<script lang="ts">
	/**
	 * Fenêtre d'alimentation. Deux niveaux : les actions, puis la confirmation
	 * de celle qu'on a choisie — éteindre le PC par erreur n'arrive pas.
	 */
	import { POWER_ENTRIES, type PowerAction } from './power';

	let {
		index,
		pending,
	}: { index: number; pending: PowerAction | null } = $props();

	const title = $derived(
		pending ? `${POWER_ENTRIES.find((e) => e.action === pending)?.label} ?` : 'Alimentation'
	);
	const items = $derived(
		pending ? ['Confirmer', 'Annuler'] : POWER_ENTRIES.map((entry) => entry.label)
	);
</script>

<div class="scrim">
	<div class="dialog">
		<h2>{title}</h2>
		<div class="entries">
			{#each items as label, i}
				<div class="entry" class:selected={i === index}>{label}</div>
			{/each}
		</div>
	</div>
</div>

<style>
	.scrim {
		position: fixed;
		inset: 0;
		z-index: 5;
		display: grid;
		place-items: center;
		background: rgba(7, 8, 11, 0.72);
		backdrop-filter: blur(6px);
		animation: fade 160ms var(--ease) both;
	}

	.dialog {
		width: min(560px, 80vw);
		padding: 36px;
		border-radius: var(--radius-lg);
		background: #11141b;
		box-shadow: 0 30px 80px rgba(0, 0, 0, 0.7);
		animation: pop 200ms var(--ease) both;
	}

	h2 {
		margin: 0 0 24px;
		font-size: 30px;
		font-weight: 600;
		text-align: center;
	}

	.entries {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}

	.entry {
		padding: 18px 24px;
		border-radius: var(--radius);
		background: var(--surface);
		font-size: 21px;
		transition:
			background var(--fast) var(--ease),
			transform var(--fast) var(--ease);
	}

	.entry.selected {
		background: var(--surface-strong);
		transform: translateX(4px);
		outline: 2px solid var(--accent);
		box-shadow: 0 0 24px 4px var(--accent-soft);
	}

	@keyframes fade {
		from {
			opacity: 0;
		}
	}

	@keyframes pop {
		from {
			opacity: 0;
			transform: scale(0.97);
		}
	}
</style>
