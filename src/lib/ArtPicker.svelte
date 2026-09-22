<script lang="ts">
	/**
	 * Choix de l'affiche d'un jeu.
	 *
	 * La détection automatique se trompe parfois de jeu, et même quand elle
	 * tombe juste, SteamGridDB propose souvent plusieurs jaquettes. Cette
	 * fenêtre montre tout ce qui existe pour ce jeu et laisse choisir : c'est
	 * l'utilisateur qui décide de ce qu'il voit dans sa bibliothèque.
	 */
	import type { Game } from './types';
	import type { Action } from './gamepad';
	import { artCandidates, chooseArt, type ArtCandidate } from './steam.svelte.js';

	let {
		open = false,
		game,
		onClose,
		onPicked,
	}: {
		open?: boolean;
		game?: Game;
		onClose: () => void;
		onPicked?: (message: string, ok: boolean) => void;
	} = $props();

	const COLUMNS = 6;

	let loading = $state(false);
	let candidates = $state<ArtCandidate[]>([]);
	let index = $state(0);
	let error = $state('');
	let saving = $state(false);

	/** Jeu en cours de consultation : rouvrir sur un autre relance la recherche. */
	let loadedFor = $state('');

	$effect(() => {
		if (!open || !game) return;
		if (loadedFor === game.id) return;
		loadedFor = game.id;
		index = 0;
		error = '';
		candidates = [];
		loading = true;
		const wanted = game;
		void (async () => {
			try {
				candidates = await artCandidates(wanted);
				if (candidates.length === 0) {
					error = "Aucune affiche trouvée pour ce jeu. Une clé SteamGridDB en apporterait davantage (Réglages → Jeux).";
				}
			} catch (e) {
				error = `Recherche impossible : ${e}`;
			} finally {
				loading = false;
			}
		})();
	});

	const KIND_LABELS: Record<string, string> = {
		cover: 'Jaquette',
		hero: 'Artwork',
		banner: 'Bannière',
	};

	export function handleAction(action: Action) {
		if (!open) return;
		if (action === 'cancel') return close();
		if (candidates.length === 0) return;

		if (action === 'left') index = Math.max(0, index - 1);
		else if (action === 'right') index = Math.min(candidates.length - 1, index + 1);
		else if (action === 'up') index = Math.max(0, index - COLUMNS);
		else if (action === 'down') index = Math.min(candidates.length - 1, index + COLUMNS);
		else if (action === 'accept') void pick();
	}

	async function pick() {
		if (!game || saving) return;
		const candidate = candidates[index];
		if (!candidate) return;
		saving = true;
		try {
			await chooseArt(game.id, candidate);
			onPicked?.(`Affiche de ${game.title} mise à jour.`, true);
			close();
		} catch (e) {
			onPicked?.(`Cette affiche n'a pas pu être enregistrée : ${e}`, false);
		} finally {
			saving = false;
		}
	}

	function close() {
		loadedFor = '';
		onClose();
	}

	const selectedRow = $derived(Math.floor(index / COLUMNS));
</script>

{#if open}
	<div class="veil">
		<section class="picker">
			<header>
				<h2>Changer l'affiche</h2>
				<p class="sub">
					{game?.title ?? ''}
					{#if candidates.length}· {candidates.length} affiches{/if}
				</p>
			</header>

			{#if loading}
				<p class="state">Recherche des affiches…</p>
			{:else if error}
				<p class="state">{error}</p>
			{:else}
				<div class="viewport">
					<div class="grid" style="--columns: {COLUMNS}; --row: {selectedRow}">
						{#each candidates as candidate, i}
							<figure class="item" class:selected={i === index}>
								<img src={candidate.thumb} alt="" loading="lazy" />
								<figcaption>
									{KIND_LABELS[candidate.kind] ?? candidate.kind} · {candidate.source}
								</figcaption>
							</figure>
						{/each}
					</div>
				</div>
			{/if}
		</section>
	</div>
{/if}

<style>
	.veil {
		position: fixed;
		inset: 0;
		z-index: 8;
		display: grid;
		place-items: center;
		background: rgba(0, 0, 0, 0.75);
		backdrop-filter: blur(10px);
		animation: fade-in var(--fast) var(--ease) both;
	}

	.picker {
		display: flex;
		flex-direction: column;
		gap: 18px;
		width: min(1400px, 86vw);
		max-height: 80vh;
		padding: 30px 34px;
		border-radius: var(--radius);
		background: var(--surface-strong);
		box-shadow: 0 30px 80px rgba(0, 0, 0, 0.7);
	}

	h2 {
		margin: 0;
		font-size: 30px;
		font-weight: 700;
	}

	.sub {
		margin: 4px 0 0;
		font-size: 17px;
		color: var(--text-dim);
	}

	.state {
		margin: 40px 0;
		font-size: 20px;
		color: var(--text-dim);
		text-align: center;
	}

	/* Deux rangées visibles ; au-delà, la grille glisse sous la fenêtre —
	   comme la bibliothèque, pas de barre de défilement à viser à la manette. */
	.viewport {
		--gap: 16px;
		--row-height: 26vh;

		/* Deux rangées au maximum ; avec moins d'affiches, la fenêtre se
		   resserre au lieu de garder une moitié vide. */
		max-height: calc(2 * var(--row-height) + var(--gap));
		overflow: hidden;
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(var(--columns), 1fr);
		gap: var(--gap);
		transform: translateY(calc(var(--row) * -1 * (var(--row-height) + var(--gap))));
		transition: transform var(--normal) var(--ease);
	}

	.item {
		position: relative;
		height: var(--row-height);
		margin: 0;
		border-radius: 12px;
		overflow: hidden;
		background: rgba(0, 0, 0, 0.4);
		transition:
			transform var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	.item img {
		width: 100%;
		height: 100%;
		/* Une jaquette verticale se montre entière ; une bannière serait
		   déformée si on la recadrait en 2/3. */
		object-fit: contain;
		background: rgba(0, 0, 0, 0.5);
	}

	.item.selected {
		transform: scale(1.05);
		outline: 3px solid var(--accent);
		box-shadow: 0 0 30px 6px var(--accent-soft);
	}

	figcaption {
		position: absolute;
		inset: auto 0 0;
		padding: 18px 8px 8px;
		font-size: 13px;
		font-weight: 600;
		text-align: center;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.92), transparent);
	}

	@keyframes fade-in {
		from {
			opacity: 0;
		}
	}
</style>
