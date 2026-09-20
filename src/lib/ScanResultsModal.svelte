<script lang="ts">
	import type { Game } from './types';
	import HelpBar from './HelpBar.svelte';

	let {
		open = false,
		candidates = [],
		alreadyKnownIds = new Set<string>(),
		scanning = false,
		onConfirm,
		onClose,
	}: {
		open: boolean;
		candidates: Game[];
		alreadyKnownIds: Set<string>;
		scanning: boolean;
		onConfirm: (chosen: Game[]) => void;
		onClose: () => void;
	} = $props();

	let selected = $state<Record<string, boolean>>({});
	let focusedIndex = $state(0);
	let listContainer: HTMLDivElement | null = $state(null);

	$effect(() => {
		if (open && candidates.length > 0) {
			const map: Record<string, boolean> = {};
			for (const c of candidates) {
				if (!alreadyKnownIds.has(c.id)) {
					// Steam et Epic sont cochés d'office car sûrs
					map[c.id] = c.source === 'steam' || c.source === 'epic';
				}
			}
			selected = map;
			focusedIndex = 0;
		}
	});

	const selectedCount = $derived(
		Object.values(selected).filter(Boolean).length
	);

	const totalItems = $derived(candidates.length + 1); // +1 pour le bouton d'ajout

	export function handleAction(action: string) {
		if (!open || scanning) return;

		if (action === 'up') {
			focusedIndex = Math.max(0, focusedIndex - 1);
			scrollIntoView(focusedIndex);
		} else if (action === 'down') {
			focusedIndex = Math.min(totalItems - 1, focusedIndex + 1);
			scrollIntoView(focusedIndex);
		} else if (action === 'accept') {
			if (focusedIndex === candidates.length) {
				// Bouton Ajouter
				confirmSelection();
			} else {
				const game = candidates[focusedIndex];
				if (game && !alreadyKnownIds.has(game.id)) {
					selected[game.id] = !selected[game.id];
				}
			}
		} else if (action === 'options') {
			// X = Tout cocher / Décocher
			toggleAll();
		} else if (action === 'cancel') {
			onClose();
		}
	}

	function toggleAll() {
		const unadded = candidates.filter((c) => !alreadyKnownIds.has(c.id));
		const allChecked = unadded.every((c) => selected[c.id]);
		for (const c of unadded) {
			selected[c.id] = !allChecked;
		}
	}

	function confirmSelection() {
		const chosen = candidates.filter((c) => selected[c.id]);
		if (chosen.length === 0) return;
		onConfirm(chosen);
		onClose();
	}

	function scrollIntoView(index: number) {
		if (!listContainer) return;
		const el = listContainer.querySelector(`[data-index="${index}"]`) as HTMLElement | null;
		if (el) {
			el.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
		}
	}

	function sourceBadge(source: string | undefined): { label: string; color: string } {
		switch (source) {
			case 'steam':
				return { label: 'Steam', color: '#1a9fff' };
			case 'epic':
				return { label: 'Epic Games', color: '#f7f7f7' };
			case 'folder':
				return { label: 'Dossier', color: '#90cdf4' };
			case 'shortcut':
				return { label: 'Raccourci', color: '#ffd13b' };
			default:
				return { label: 'PC', color: '#8d9bb0' };
		}
	}
</script>

{#if open}
	<div class="overlay" role="dialog" aria-modal="true">
		<div class="dialog">
			<header>
				<div class="title-row">
					<h2>Jeux détectés ({candidates.length})</h2>
					{#if scanning}
						<span class="scanning-badge">Recherche en cours…</span>
					{/if}
				</div>
				<p>
					{candidates.length === 0 && !scanning
						? 'Aucun jeu détecté. Vérifie les dossiers configurés ou tes installations.'
						: 'Coche les jeux à ajouter à ta bibliothèque. Steam et Epic Games sont cochés d’office.'}
				</p>
			</header>

			{#if scanning}
				<div class="loading-box">
					<div class="spinner"></div>
					<p>Scan des répertoires Steam, Epic Games, raccourcis et dossiers de jeux…</p>
				</div>
			{:else}
				<div class="list" bind:this={listContainer}>
					{#each candidates as game, i}
						{@const isKnown = alreadyKnownIds.has(game.id)}
						{@const isChecked = selected[game.id]}
						{@const badge = sourceBadge(game.source)}
						<button
							type="button"
							class="row"
							data-index={i}
							class:focused={focusedIndex === i}
							class:disabled={isKnown}
							onclick={() => {
								if (!isKnown) {
									focusedIndex = i;
									selected[game.id] = !selected[game.id];
								}
							}}
						>
							<div class="checkbox" class:checked={isChecked} class:known={isKnown}>
								{#if isKnown}
									✓
								{:else if isChecked}
									■
								{/if}
							</div>

							<div class="info">
								<span class="game-title">{game.title}</span>
								{#if game.executable}
									<span class="game-path">{game.executable}</span>
								{/if}
							</div>

							<div class="badges">
								{#if isKnown}
									<span class="badge known-badge">Déjà ajouté</span>
								{:else}
									<span class="badge" style:color={badge.color} style:border-color={badge.color}>
										{badge.label}
									</span>
								{/if}
							</div>
						</button>
					{/each}
				</div>

				<div class="actions">
					<button
						type="button"
						class="btn-confirm"
						data-index={candidates.length}
						class:focused={focusedIndex === candidates.length}
						disabled={selectedCount === 0}
						onclick={confirmSelection}
					>
						Ajouter à la bibliothèque ({selectedCount})
					</button>
				</div>
			{/if}

			<div class="footer">
				<HelpBar
					entries={[
						{ button: 'a', label: focusedIndex === candidates.length ? 'Valider' : 'Cocher' },
						{ button: 'x', label: 'Tout cocher' },
						{ button: 'b', label: 'Fermer' },
					]}
				/>
			</div>
		</div>
	</div>
{/if}

<style>
	.overlay {
		position: fixed;
		inset: 0;
		z-index: 10;
		display: grid;
		place-items: center;
		background: rgba(3, 5, 8, 0.82);
		backdrop-filter: blur(18px);
		animation: fade-in 180ms var(--ease);
	}

	.dialog {
		display: flex;
		flex-direction: column;
		gap: 20px;
		width: min(840px, 92vw);
		max-height: 86vh;
		padding: 36px 44px 28px;
		border-radius: calc(var(--radius) * 1.5);
		background: var(--surface-strong);
		border: 1px solid var(--border);
		box-shadow: 0 24px 60px rgba(0, 0, 0, 0.7);
		animation: scale-in 220ms var(--ease);
	}

	header h2 {
		margin: 0;
		font-size: 28px;
		font-weight: 700;
	}

	.title-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 16px;
	}

	.scanning-badge {
		padding: 4px 12px;
		border-radius: 999px;
		background: rgba(255, 255, 255, 0.1);
		color: #ffffff;
		border: 1px solid rgba(255, 255, 255, 0.15);
		font-size: 13px;
		font-weight: 600;
	}

	header p {
		margin: 6px 0 0;
		font-size: 16px;
		color: var(--text-dim);
	}

	.loading-box {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 20px;
		padding: 60px 0;
	}

	.spinner {
		width: 44px;
		height: 44px;
		border-radius: 50%;
		border: 3px solid rgba(255, 255, 255, 0.1);
		border-top-color: #ffffff;
		animation: spin 800ms linear infinite;
	}

	.list {
		display: flex;
		flex-direction: column;
		gap: 10px;
		max-height: 48vh;
		overflow-y: auto;
		padding-right: 8px;
	}

	.row {
		display: flex;
		align-items: center;
		gap: 18px;
		padding: 14px 20px;
		border-radius: var(--radius);
		background: var(--surface);
		border: 2px solid transparent;
		cursor: pointer;
		transition: all 180ms var(--ease);
	}

	.row.focused {
		border-color: rgba(255, 255, 255, 0.7);
		background: rgba(255, 255, 255, 0.1);
		transform: translateX(4px);
		box-shadow: 0 0 16px rgba(255, 255, 255, 0.15);
	}

	.row.disabled {
		opacity: 0.45;
		cursor: not-allowed;
	}

	.checkbox {
		display: grid;
		place-items: center;
		width: 26px;
		height: 26px;
		border-radius: 6px;
		border: 2px solid rgba(255, 255, 255, 0.3);
		color: #ffffff;
		font-size: 16px;
		font-weight: 700;
		background: rgba(0, 0, 0, 0.2);
		flex-shrink: 0;
	}

	.checkbox.checked {
		border-color: #ffffff;
		background: rgba(255, 255, 255, 0.25);
		color: #ffffff;
	}

	.checkbox.known {
		border-color: var(--text-dim);
		color: var(--text-dim);
	}

	.info {
		display: flex;
		flex-direction: column;
		gap: 3px;
		flex: 1;
		min-width: 0;
	}

	.game-title {
		font-size: 18px;
		font-weight: 600;
		color: var(--text);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.game-path {
		font-size: 12px;
		color: var(--text-dim);
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}

	.badge {
		padding: 4px 10px;
		border-radius: 6px;
		border: 1px solid currentColor;
		font-size: 12px;
		font-weight: 600;
		background: rgba(0, 0, 0, 0.25);
		text-transform: uppercase;
		letter-spacing: 0.5px;
	}

	.known-badge {
		border-color: rgba(255, 255, 255, 0.2);
		color: var(--text-dim);
	}

	.actions {
		display: flex;
		justify-content: flex-end;
		margin-top: 4px;
	}

	.btn-confirm {
		padding: 14px 28px;
		border-radius: var(--radius);
		border: 1px solid rgba(255, 255, 255, 0.25);
		background: rgba(255, 255, 255, 0.12);
		color: #ffffff;
		font-size: 17px;
		font-weight: 700;
		cursor: pointer;
		transition: all 180ms var(--ease);
	}

	.btn-confirm:disabled {
		opacity: 0.4;
		cursor: not-allowed;
		background: var(--surface);
		color: var(--text-dim);
		border-color: transparent;
	}

	.btn-confirm.focused {
		transform: scale(1.04);
		border-color: #ffffff;
		background: #ffffff;
		color: #0b0f19;
		box-shadow: 0 0 24px rgba(255, 255, 255, 0.35);
	}

	.footer {
		display: flex;
		justify-content: center;
		margin-top: 6px;
	}

	@keyframes spin {
		to { transform: rotate(360deg); }
	}

	@keyframes fade-in {
		from { opacity: 0; }
		to { opacity: 1; }
	}

	@keyframes scale-in {
		from { opacity: 0; transform: scale(0.97); }
		to { opacity: 1; transform: scale(1); }
	}
</style>
