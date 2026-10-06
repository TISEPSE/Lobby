<script lang="ts">
	import type { Game, TileAction } from './types';
	import Cover from './Cover.svelte';
	import TileOptions from './TileOptions.svelte';
	import { heroFor } from './steam.svelte.js';
	import { lastPlayedText, playtimeOf, playtimeText } from './library.svelte.js';

	/**
	 * Accueil : artwork plein écran, rangée horizontale de jaquettes. La tuile
	 * sélectionnée s'agrandit et **pousse** ses voisines plutôt que de les
	 * recouvrir — c'est le `gap` qui s'élargit autour d'elle.
	 *
	 * En tête de rangée, la carte « Reprendre » (index -1) relance le dernier
	 * jeu en un appui, sans passer par sa fiche.
	 */
	let {
		games,
		index,
		actions = [],
		optionsOpen = false,
		optionsIndex = 0,
		resume = null,
		focused = true,
	}: {
		games: Game[];
		index: number;
		actions?: TileAction[];
		optionsOpen?: boolean;
		optionsIndex?: number;
		/** Dernier jeu lancé ; sans lui, pas de carte. */
		resume?: Game | null;
		/**
		 * La sélection est dans la rangée. Sinon (barre du haut), aucune tuile ne
		 * porte le contour : un seul élément sélectionné à l'écran.
		 */
		focused?: boolean;
	} = $props();

	const onResume = $derived(index < 0 && resume !== null);
	const selected = $derived(onResume ? resume : games[index]);

	/** « Dernière partie hier · 12 h 30 de jeu » : ce qu'on a besoin de savoir pour reprendre. */
	function resumeFacts(game: Game): string {
		const when = lastPlayedText(game.id);
		const parts = [when ? `Dernière partie ${when}` : 'Prêt à reprendre'];
		if (playtimeOf(game.id) > 0) parts.push(`${playtimeText(game.id)} de jeu`);
		return parts.join(' · ');
	}

</script>

<section class="stage">
	{#if selected}
		<div class="headline">
			<h1>{selected.title}</h1>
			<p class="facts">{onResume ? resumeFacts(selected) : 'Installé · Prêt à jouer'}</p>
		</div>
	{/if}

	<div
		class="rail"
		class:on-resume={onResume}
		style="--index: {index}; --lead: {resume ? 1 : 0}"
	>
		{#if resume}
			<button class="resume" class:selected={focused && onResume} aria-current={onResume}>
				<span class="art" style="background-image: url({heroFor(resume)})"></span>
				<span class="label">
					<span class="chip"><img src="/assets/icons/play.svg" alt="" />Reprendre</span>
					<span class="name">{resume.title}</span>
				</span>
			</button>
			{#if onResume}
				<TileOptions {actions} index={optionsIndex} open={optionsOpen} />
			{/if}
		{/if}
		{#each games as game, i (game.id)}
			<button
				class="tile"
				class:selected={focused && i === index}
				style="--i: {i}"
				aria-current={i === index}
			>
				<Cover {game} />
				<span class="caption">{game.title}</span>
			</button>
			{#if i === index}
				<TileOptions {actions} index={optionsIndex} open={optionsOpen} />
			{/if}
		{/each}
	</div>
</section>

<style>
	.stage {
		position: relative;
		z-index: 1;
		display: flex;
		flex-direction: column;
		justify-content: flex-end;
		height: 100%;
		/* On dégage la barre d'aide : la rangée ne doit jamais venir dessous. */
		padding: 0 0 calc(var(--safe-y) + 46px);
	}

	.headline {
		padding: 0 var(--safe-x);
		margin-bottom: 4vh;
	}

	h1 {
		margin: 0;
		font-size: clamp(38px, 4.4vw, 76px);
		font-weight: 700;
		letter-spacing: -0.02em;
		/* Le titre suit la sélection sans clignoter : il glisse. */
		animation: rise var(--normal) var(--ease) both;
	}

	.facts {
		margin: 8px 0 0;
		font-size: 19px;
		color: var(--text-dim);
	}

	@keyframes rise {
		from {
			opacity: 0;
			transform: translateY(14px);
		}
	}

	.rail {
		display: flex;
		align-items: flex-end;
		gap: var(--tile-gap);
		padding: 40px 0 0;
		/* La sélection se tient un peu à droite du centre : pile au milieu, la
		   rangée paraît figée et la lecture est moins naturelle. */
		transform: translateX(
			calc(
				50vw + var(--selection-shift) - var(--lead) * (var(--resume-width) + var(--tile-gap)) -
					(var(--index) + 0.5) * (var(--tile) + var(--tile-gap))
			)
		);
		transition: transform var(--normal) var(--ease);
		will-change: transform;
	}

	/* Sur la carte « Reprendre », la rangée s'aligne sur le titre au lieu de se
	   centrer : centrée, la carte laissait un grand vide à sa gauche. La marge
	   de la carte sélectionnée compense exactement son agrandissement. */
	.rail.on-resume {
		transform: translateX(var(--safe-x));
	}

	/* Une tuile couchée, à la hauteur des autres : elle fait partie de la
	   rangée, elle ne flotte pas au-dessus. */
	.resume {
		position: relative;
		flex: 0 0 var(--resume-width);
		width: var(--resume-width);
		height: calc(var(--tile) * 1.5);
		padding: 0;
		border-radius: var(--radius);
		overflow: hidden;
		background: var(--surface);
		text-align: left;
		transform-origin: center bottom;
		transition:
			transform var(--normal) var(--ease),
			box-shadow var(--normal) var(--ease),
			margin var(--normal) var(--ease);
		box-shadow: 0 12px 30px rgba(0, 0, 0, 0.45);
	}

	.resume.selected {
		transform: scale(var(--tile-focus-scale));
		margin: 0 calc(var(--resume-width) * (var(--tile-focus-scale) - 1) / 2);
		outline: 4.5px solid var(--accent);
		box-shadow:
			0 0 38px 8px var(--accent-soft),
			0 26px 60px rgba(0, 0, 0, 0.6);
	}

	.art {
		position: absolute;
		inset: 0;
		background-size: cover;
		background-position: center;
	}

	/* Voile en bas : le titre se lit sur n'importe quel artwork. */
	.label {
		position: absolute;
		inset: auto 0 0;
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 8px;
		padding: 40px 18px 16px;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.9), transparent);
	}

	.chip {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		padding: 5px 12px 5px 10px;
		border-radius: 999px;
		background: var(--accent);
		color: var(--on-accent);
		font-size: 17px;
		font-weight: 700;
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}

	/* L'icône est blanche : on la fonce pour qu'elle suive le texte de la pastille. */
	.chip img {
		width: 15px;
		height: 15px;
		filter: brightness(0);
		opacity: 0.85;
	}

	.name {
		font-size: 19px;
		font-weight: 700;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 100%;
	}

	.tile {
		position: relative;
		flex: 0 0 var(--tile);
		width: var(--tile);
		aspect-ratio: 2 / 3;
		padding: 0;
		border-radius: var(--radius);
		overflow: hidden;
		background: var(--surface);
		transform-origin: center bottom;
		transition:
			transform var(--normal) var(--ease),
			box-shadow var(--normal) var(--ease),
			margin var(--normal) var(--ease);
		box-shadow: 0 12px 30px rgba(0, 0, 0, 0.45);
	}

	/* La tuile agrandie écarte ses voisines au lieu de passer par-dessus. */
	.tile.selected {
		transform: scale(var(--tile-focus-scale));
		margin: 0 calc(var(--tile) * (var(--tile-focus-scale) - 1) / 2);
		outline: 4.5px solid var(--accent);
		box-shadow:
			0 0 38px 8px var(--accent-soft),
			0 26px 60px rgba(0, 0, 0, 0.6);
	}

	.caption {
		position: absolute;
		inset: auto 0 0;
		padding: 26px 10px 10px;
		font-size: 14px;
		font-weight: 600;
		text-align: center;
		background: linear-gradient(to top, rgba(0, 0, 0, 0.88), transparent);
	}
</style>
