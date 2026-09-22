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
				<!-- Tuiles fantômes au format d'une jaquette : on voit tout de
				     suite ce qui va arriver, et où. -->
				<div class="viewport">
					<div class="grid" style="--columns: {COLUMNS}; --row: 0">
						{#each Array(COLUMNS) as _, i}
							<div class="ghost" style="--delay: {i * 110}ms"></div>
						{/each}
					</div>
				</div>
				<p class="state">Recherche des affiches…</p>
			{:else if error}
				<p class="state">{error}</p>
			{:else}
				<div class="viewport">
					<div class="grid" style="--columns: {COLUMNS}; --row: {selectedRow}">
						{#each candidates as candidate, i}
							<!-- L'aperçu est rendu **comme la vraie tuile** : même format, même
							     cadrage, même légende. Ce qu'on voit ici est exactement ce
							     qu'on verra dans la bibliothèque. -->
							<figure class="item" class:selected={i === index}>
								<img src={candidate.thumb} alt="" loading="lazy" />
								<span class="caption">{game?.title ?? ''}</span>
								<span class="tag">
									{KIND_LABELS[candidate.kind] ?? candidate.kind} · {candidate.source}
								</span>
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
		   resserre au lieu de garder une moitié vide. La gouttière laisse
		   l'agrandissement de la sélection déborder sans être rogné. */
		max-height: calc(2 * var(--row-height) + var(--gap) + 2 * var(--hover-room));
		overflow: hidden;
		margin: calc(-1 * var(--hover-room));
		padding: var(--hover-room);
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
		border-radius: var(--radius);
		overflow: hidden;
		background: var(--surface);
		box-shadow: 0 12px 30px rgba(0, 0, 0, 0.45);
		transition:
			transform var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	/* Exactement le cadrage d'une tuile (`Cover.svelte`) : une bannière choisie
	   sera recadrée ici comme elle le sera dans la bibliothèque, sans surprise
	   au moment de valider. */
	.item img {
		width: 100%;
		height: 100%;
		object-fit: cover;
		background: #0c0e13;
	}

	.item.selected {
		transform: scale(1.05);
		outline: 3px solid var(--accent);
		box-shadow: 0 0 30px 6px var(--accent-soft);
	}

	/* Le titre se pose comme sur une tuile de la bibliothèque. */
	.caption {
		position: absolute;
		inset: auto 0 0;
		padding: 28px 8px 10px;
		font-size: 14px;
		font-weight: 600;
		text-align: center;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.9), transparent);
	}

	/* La provenance est une étiquette de la fenêtre, pas un élément de la
	   jaquette : elle se tient en haut, discrète. */
	.tag {
		position: absolute;
		top: 8px;
		left: 8px;
		padding: 3px 8px;
		border-radius: 6px;
		background: rgba(0, 0, 0, 0.65);
		font-size: 11px;
		font-weight: 600;
		color: var(--text-dim);
	}

	.ghost {
		height: var(--row-height);
		border-radius: var(--radius);
		background: rgba(255, 255, 255, 0.06);
		animation: breathe 1.4s var(--ease) infinite;
		animation-delay: var(--delay);
	}

	/* Respiration lente : on voit que ça travaille sans que ça clignote. */
	@keyframes breathe {
		0%,
		100% {
			opacity: 0.35;
		}
		50% {
			opacity: 0.75;
		}
	}

	@keyframes fade-in {
		from {
			opacity: 0;
		}
	}
</style>
