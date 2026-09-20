<script lang="ts">
	/**
	 * Fenêtre d'alimentation. Trois cartes côte à côte, avec leur icône, puis
	 * une confirmation pour l'action choisie — éteindre le PC par erreur
	 * n'arrive pas.
	 */
	import { POWER_ENTRIES, type PowerAction } from './power';

	let {
		index,
		pending,
	}: { index: number; pending: PowerAction | null } = $props();

	const chosen = $derived(POWER_ENTRIES.find((entry) => entry.action === pending));
</script>

<div class="scrim">
	<div class="dialog" class:confirming={pending !== null}>
		{#if pending && chosen}
			<div class="head">
				<span class="mark {chosen.action}">
					<img src="/assets/icons/{chosen.icon}.svg" alt="" />
				</span>
				<h2>{chosen.label} ?</h2>
				<p>{chosen.confirmHint}</p>
			</div>
			<div class="choices">
				{#each ['Confirmer', 'Annuler'] as label, i}
					<div class="choice" class:selected={i === index} class:danger={i === 0}>{label}</div>
				{/each}
			</div>
		{:else}
			<h2>Alimentation</h2>
			<div class="cards">
				{#each POWER_ENTRIES as entry, i}
					<div class="card" class:selected={i === index}>
						<span class="mark {entry.action}">
							<img src="/assets/icons/{entry.icon}.svg" alt="" />
						</span>
						<span class="label">{entry.label}</span>
						<span class="hint">{entry.hint}</span>
					</div>
				{/each}
			</div>
		{/if}
	</div>
</div>

<style>
	.scrim {
		position: fixed;
		inset: 0;
		z-index: 5;
		display: grid;
		place-items: center;
		background: rgba(5, 6, 9, 0.78);
		backdrop-filter: blur(10px);
		animation: fade 160ms var(--ease) both;
	}

	.dialog {
		padding: 44px 48px 48px;
		border-radius: var(--radius-lg);
		background: linear-gradient(180deg, #161b24 0%, #0e1118 100%);
		box-shadow:
			0 0 0 1px rgba(255, 255, 255, 0.06),
			0 40px 90px rgba(0, 0, 0, 0.75);
		animation: pop 220ms var(--ease) both;
	}

	h2 {
		margin: 0 0 28px;
		font-size: 30px;
		font-weight: 600;
		text-align: center;
		letter-spacing: -0.01em;
	}

	.cards {
		display: flex;
		gap: 18px;
	}

	.card {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 12px;
		width: 210px;
		padding: 30px 18px 26px;
		border-radius: var(--radius);
		background: rgba(255, 255, 255, 0.045);
		text-align: center;
		transition:
			background var(--fast) var(--ease),
			transform var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	.card.selected {
		background: rgba(255, 255, 255, 0.1);
		transform: translateY(-4px);
		box-shadow:
			0 0 0 2px var(--accent),
			0 0 34px 6px var(--accent-soft);
	}

	/* Pastille d'icône : chaque action a sa teinte, l'extinction se distingue. */
	.mark {
		display: grid;
		place-items: center;
		width: 68px;
		height: 68px;
		border-radius: 50%;
		background: rgba(255, 255, 255, 0.08);
	}

	.mark img {
		width: 32px;
		height: 32px;
		opacity: 0.9;
	}

	.mark.shutdown {
		background: rgba(239, 68, 68, 0.18);
	}

	.mark.reboot {
		background: rgba(59, 130, 246, 0.18);
	}

	.mark.quit {
		background: rgba(34, 211, 102, 0.18);
	}

	.label {
		font-size: 20px;
		font-weight: 600;
	}

	.hint {
		font-size: 14px;
		line-height: 1.35;
		color: var(--text-dim);
	}

	/* --- Confirmation --- */

	.confirming {
		width: min(560px, 82vw);
	}

	.head {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 14px;
		margin-bottom: 30px;
		text-align: center;
	}

	.head h2 {
		margin: 0;
	}

	.head p {
		margin: 0;
		font-size: 16px;
		color: var(--text-dim);
	}

	.choices {
		display: flex;
		gap: 14px;
	}

	.choice {
		flex: 1;
		padding: 18px;
		border-radius: var(--radius);
		background: rgba(255, 255, 255, 0.05);
		font-size: 20px;
		font-weight: 600;
		text-align: center;
		transition:
			background var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	.choice.selected {
		background: rgba(255, 255, 255, 0.12);
		box-shadow:
			0 0 0 2px var(--accent),
			0 0 28px 5px var(--accent-soft);
	}

	/* La confirmation d'une action irréversible ne se déguise pas en bouton doux. */
	.choice.danger.selected {
		box-shadow:
			0 0 0 2px #ef4444,
			0 0 28px 5px rgba(239, 68, 68, 0.28);
	}

	@keyframes fade {
		from {
			opacity: 0;
		}
	}

	@keyframes pop {
		from {
			opacity: 0;
			transform: scale(0.96) translateY(8px);
		}
	}
</style>
