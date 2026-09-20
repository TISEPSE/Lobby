<script lang="ts">
	import type { Game } from './types';

	/**
	 * Fiche d'un jeu. La jaquette arrive depuis sa place sur l'accueil : le
	 * navigateur anime lui-même le changement de position via `view-transition`,
	 * on n'a pas à mesurer le rectangle de départ comme en Godot.
	 */
	let {
		game,
		favorite = false,
		onplay,
	}: { game: Game; favorite?: boolean; onplay?: () => void } = $props();

	const facts = ['Action, Aventure', '2024', 'Jamais joué'];
	const rating = 4.3;
</script>

<div class="detail">
	<img class="cover" src={game.cover} alt={game.title} style="view-transition-name: cover-{game.id}" />

	<div class="info">
		<h1>{game.title}</h1>
		<p class="facts">{facts.join('  ·  ')}</p>

		<div class="stars" aria-label="Note {rating} sur 5">
			{#each [0, 1, 2, 3, 4] as i}
				<svg viewBox="0 0 640 640" class:on={rating >= i + 0.5}>
					<path
						d="M341.5 45.1C337.4 37.1 329.1 32 320.1 32C311.1 32 302.8 37.1 298.7 45.1L225.1 189.3L65.2 214.7C56.3 216.1 48.9 222.4 46.1 231C43.3 239.6 45.6 249 51.9 255.4L166.3 369.9L141.1 529.8C139.7 538.7 143.4 547.7 150.7 553C158 558.3 167.6 559.1 175.7 555L320.1 481.6L464.4 555C472.4 559.1 482.1 558.3 489.4 553C496.7 547.7 500.4 538.8 499 529.8L473.7 369.9L588.1 255.4C594.5 249 596.7 239.6 593.9 231C591.1 222.4 583.8 216.1 574.8 214.7L415 189.3L341.5 45.1z"
					/>
				</svg>
			{/each}
			<span class="value">{rating.toFixed(1)}</span>
		</div>

		<p class="synopsis">
			Fiche de démonstration : le prototype affiche ici le résumé, les genres et la note
			récupérés auprès des données publiques de Steam, sans clé d'API.
		</p>

		<div class="actions">
			<button class="primary focus-ring" onclick={onplay}>Jouer</button>
			<button class="ghost">{favorite ? 'Retirer des favoris' : 'Ajouter aux favoris'}</button>
		</div>
	</div>
</div>

<style>
	.detail {
		position: relative;
		z-index: 1;
		display: grid;
		grid-template-columns: clamp(220px, 19vw, 330px) 1fr;
		gap: clamp(32px, 4vw, 72px);
		align-content: center;
		height: 100%;
		padding: var(--safe-y) var(--safe-x);
		animation: enter var(--normal) var(--ease) both;
	}

	@keyframes enter {
		from {
			opacity: 0;
			transform: translateY(18px);
		}
	}

	.cover {
		width: 100%;
		aspect-ratio: 2 / 3;
		object-fit: cover;
		border-radius: var(--radius-lg);
		box-shadow: 0 30px 70px rgba(0, 0, 0, 0.65);
		align-self: center;
	}

	.info {
		align-self: center;
		max-width: 60ch;
	}

	h1 {
		margin: 0;
		font-size: clamp(42px, 5vw, 86px);
		font-weight: 700;
		letter-spacing: -0.025em;
	}

	.facts {
		margin: 10px 0 0;
		font-size: 21px;
		color: var(--text-dim);
	}

	.stars {
		display: flex;
		align-items: center;
		gap: 8px;
		margin-top: 14px;
	}

	.stars svg {
		width: 26px;
		height: 26px;
		fill: rgba(255, 255, 255, 0.24);
	}

	.stars svg.on {
		fill: var(--accent);
	}

	.value {
		margin-left: 6px;
		font-size: 20px;
		color: var(--text-dim);
	}

	.synopsis {
		margin: 22px 0 0;
		font-size: 22px;
		line-height: 1.5;
		color: rgba(255, 255, 255, 0.86);
	}

	.actions {
		display: flex;
		gap: 16px;
		margin-top: 34px;
	}

	button {
		padding: 18px 42px;
		border-radius: var(--radius);
		font-size: 22px;
		font-weight: 600;
		transition: transform var(--fast) var(--ease), background var(--fast) var(--ease);
	}

	.primary {
		background: var(--surface-strong);
	}

	.ghost {
		background: var(--surface);
		color: var(--text-dim);
	}
</style>
