<script lang="ts">
	/**
	 * Options d'un jeu, en fenêtre façon Xbox — la même partout (accueil,
	 * bibliothèque, fiche). En tête, la jaquette et le nom du jeu : on sait
	 * toujours de quel jeu il s'agit. Les lignes entrent l'une après l'autre ;
	 * la sélection porte le contour d'accent et avance légèrement.
	 */
	import type { Game, TileAction } from './types';
	import Cover from './Cover.svelte';
	import Glyph from './Glyph.svelte';
	import { platformOf } from './stats';

	let {
		actions,
		index = 0,
		open = false,
		game = null,
	}: { actions: TileAction[]; index?: number; open?: boolean; game?: Game | null } = $props();
</script>

{#if open}
	<div class="veil">
		<section class="menu">
			{#if game}
				<header>
					<div class="cover"><Cover {game} /></div>
					<div class="titles">
						<span class="store">{platformOf(game)}</span>
						<h2>{game.title}</h2>
						<span class="sub">Options du jeu</span>
					</div>
				</header>
			{/if}

			<div class="rows">
				{#each actions as action, i (action.id)}
					<div class="row" class:selected={i === index} style="--i: {i}">
						<span class="mark">
							<img src="/assets/icons/{action.icon}.svg" alt="" />
						</span>
						<span class="label">{action.label}</span>
					</div>
				{/each}
			</div>

			<footer class="hints">
				<span class="hint"><Glyph button="a" size="28px" />Choisir</span>
				<span class="hint"><Glyph button="b" size="28px" />Fermer</span>
			</footer>
		</section>
	</div>
{/if}

<style>
	.veil {
		position: fixed;
		inset: 0;
		z-index: 7;
		display: grid;
		place-items: center;
		background: rgba(0, 0, 0, 0.7);
		backdrop-filter: blur(10px);
		animation: fade-in var(--fast) var(--ease) both;
	}

	.menu {
		display: flex;
		flex-direction: column;
		gap: 22px;
		width: var(--options-width);
		padding: 30px 32px;
		border-radius: var(--radius-lg);
		background: var(--surface-strong);
		box-shadow: 0 30px 80px rgba(0, 0, 0, 0.7);
		animation: rise var(--normal) var(--ease) both;
	}

	header {
		display: flex;
		align-items: center;
		gap: 22px;
	}

	/* `Cover` remplit son parent (position absolue) : ce cadre le contient. */
	.cover {
		position: relative;
		flex: none;
		width: var(--options-cover);
		aspect-ratio: 2 / 3;
		border-radius: var(--radius);
		overflow: hidden;
		box-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);
	}

	.titles {
		display: flex;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}

	.store {
		font-size: 17px;
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--accent);
	}

	h2 {
		margin: 0;
		font-size: 30px;
		font-weight: 700;
		line-height: 1.15;
		overflow: hidden;
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
	}

	.sub {
		font-size: 17px;
		color: var(--text-dim);
	}

	.rows {
		display: flex;
		flex-direction: column;
		gap: 10px;
	}

	.row {
		display: flex;
		align-items: center;
		gap: 16px;
		height: var(--options-row);
		padding: 0 18px;
		border-radius: var(--radius);
		background: var(--surface);
		animation: row-in var(--normal) var(--ease) backwards;
		animation-delay: calc(var(--i) * 30ms);
		transition:
			transform var(--fast) var(--ease),
			background var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	/* Sélection : contour d'accent, halo, et la ligne avance légèrement —
	   comme dans l'explorateur de fichiers. */
	.row.selected {
		background: rgba(255, 255, 255, 0.12);
		box-shadow:
			0 0 0 3px var(--accent),
			0 0 28px 4px var(--accent-soft);
		transform: translateX(8px) scale(1.01);
	}

	.mark {
		display: grid;
		place-items: center;
		flex: none;
		width: 40px;
		height: 40px;
		border-radius: 50%;
		background: rgba(255, 255, 255, 0.07);
		transition: background var(--fast) var(--ease);
	}

	.row.selected .mark {
		background: var(--accent-soft);
	}

	.mark img {
		width: 20px;
		height: 20px;
		opacity: 0.9;
	}

	.label {
		font-size: 19px;
		font-weight: 600;
	}

	.hints {
		display: flex;
		justify-content: flex-end;
		gap: 28px;
		font-size: 18px;
		color: var(--text-dim);
	}

	.hint {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	@keyframes fade-in {
		from {
			opacity: 0;
		}
	}

	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(18px) scale(0.98);
		}
	}

	@keyframes row-in {
		from {
			opacity: 0;
			transform: translateX(-12px);
		}
	}
</style>
