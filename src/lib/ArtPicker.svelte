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
	import Cover from './Cover.svelte';
	import { artCandidates, chooseArt, type ArtCandidate, type ArtTarget } from './steam.svelte.js';

	let {
		open = false,
		game,
		target = 'cover',
		onClose,
		onPicked,
	}: {
		open?: boolean;
		game?: Game;
		/** « cover » choisit la jaquette de la tuile, « background » l'artwork de fond. */
		target?: ArtTarget;
		onClose: () => void;
		onPicked?: (message: string, ok: boolean) => void;
	} = $props();

	/** Un fond se juge en grand : moins de colonnes, au format d'un écran. */
	const COLUMNS = $derived(target === 'background' ? 3 : 6);

	let loading = $state(false);
	let candidates = $state<ArtCandidate[]>([]);
	let index = $state(0);
	let error = $state('');
	let saving = $state(false);

	/** Jeu en cours de consultation : rouvrir sur un autre relance la recherche. */
	let loadedFor = $state('');

	$effect(() => {
		if (!open || !game) return;
		// Rouvrir pour le même jeu mais sur l'autre cible relance la recherche.
		const key = `${game.id}|${target}`;
		if (loadedFor === key) return;
		loadedFor = key;
		index = 0;
		error = '';
		candidates = [];
		loading = true;
		const wanted = game;
		void (async () => {
			try {
				const found = await artCandidates(wanted);
				if (target === 'background') {
					// Un fond est large : une jaquette verticale n'a rien à y faire.
					candidates = found.filter((item) => item.kind !== 'cover');
				} else {
					// Pour la tuile, les vraies jaquettes d'abord — mais on montre
					// aussi les images larges : beaucoup de jeux n'ont **aucune**
					// jaquette verticale chez Steam, et une fenêtre vide ne laisse
					// alors aucun choix. L'aperçu montre le recadrage réel, donc
					// personne n'est surpris.
					const rank = { cover: 0, banner: 1, hero: 2 } as const;
					candidates = [...found].sort((a, b) => rank[a.kind] - rank[b.kind]);
				}
				if (candidates.length === 0) {
					error =
						target === 'background'
							? "Aucune image de fond trouvée pour ce jeu. Une clé SteamGridDB en apporterait davantage (Réglages → Jeux)."
							: "Aucune jaquette trouvée pour ce jeu. Une clé SteamGridDB en apporterait davantage (Réglages → Jeux).";
				}
			} catch (e) {
				error = `Recherche impossible : ${e}`;
			} finally {
				loading = false;
			}
		})();
	});

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
			await chooseArt(game.id, candidate, target);
			onPicked?.(
				target === 'background'
					? `Image de fond de ${game.title} mise à jour.`
					: `Jaquette de ${game.title} mise à jour.`,
				true
			);
			close();
		} catch (e) {
			onPicked?.(`Cette image n'a pas pu être enregistrée : ${e}`, false);
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
				<h2>{target === 'background' ? "Changer l'image de fond" : 'Changer la jaquette'}</h2>
				<p class="sub">
					{game?.title ?? ''}
					{#if candidates.length}· {candidates.length} image{candidates.length > 1 ? 's' : ''}{/if}
				</p>
			</header>

			{#if loading}
				<!-- Tuiles fantômes au format d'une jaquette : on voit tout de
				     suite ce qui va arriver, et où. -->
				<div class="viewport" class:wide={target === 'background'} style="--columns: {COLUMNS}">
					<div class="grid" style="--row: 0">
						{#each Array(COLUMNS) as _, i}
							<div class="ghost" style="--delay: {i * 110}ms"></div>
						{/each}
					</div>
				</div>
				<p class="state">Recherche des images…</p>
			{:else if error}
				<p class="state">{error}</p>
			{:else}
				<div class="viewport" class:wide={target === 'background'} style="--columns: {COLUMNS}">
					<div class="grid" style="--row: {selectedRow}">
						{#each candidates as candidate, i}
							<!-- L'aperçu passe par `Cover`, le composant des vraies tuiles, avec
							     l'image pleine (pas la miniature) : cadrage, format et légende
							     sont ceux de l'accueil, sans rien reproduire à la main. -->
							<figure class="item" class:selected={i === index}>
								{#if target === 'background'}
									<!-- Un fond se regarde tel qu'il couvrira l'écran. -->
									<img class="wide" src={candidate.url} alt="" loading="lazy" />
								{:else if game}
									<Cover {game} override={candidate.url} />
								{/if}
								<span class="caption">{game?.title ?? ''}</span>
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
		/* Largeur de la fenêtre : elle sert aussi à déduire la taille exacte
		   d'une tuile, donc le format 2/3 des aperçus. */
		--picker-width: min(1400px, 86vw);
		--picker-padding: 34px;

		display: flex;
		flex-direction: column;
		gap: 18px;
		width: var(--picker-width);
		max-height: 80vh;
		padding: 30px var(--picker-padding);
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
		/* Un fond est au format d'un écran, une jaquette au format d'une tuile. */
		--ratio: 1.5;
		/* Une tuile garde le format 2/3 des jaquettes : sa hauteur se déduit de
		   la largeur d'une colonne, comme dans la bibliothèque. */
		--tile-width: calc(
			(
					var(--picker-width) - 2 * var(--picker-padding) - (var(--columns) - 1) * var(--gap)
				) / var(--columns)
		);
		--row-height: calc(var(--tile-width) * var(--ratio));

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

	.viewport.wide {
		--ratio: 0.5625;
	}

	.item .wide {
		display: block;
		width: 100%;
		height: 100%;
		object-fit: cover;
	}

	/* Exactement la tuile de l'accueil : même format, même rayon, même fond. */
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

	/* Et la sélection est celle d'une tuile : même contour, même halo. */
	.item.selected {
		transform: scale(1.05);
		outline: 4.5px solid var(--accent);
		box-shadow:
			0 0 38px 8px var(--accent-soft),
			0 26px 60px rgba(0, 0, 0, 0.6);
	}

	/* Le titre se pose comme sur une tuile de l'accueil, aux mêmes valeurs. */
	.caption {
		position: absolute;
		inset: auto 0 0;
		padding: 26px 10px 10px;
		font-size: 14px;
		font-weight: 600;
		text-align: center;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.88), transparent);
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
