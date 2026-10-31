<script lang="ts">
	import { fade, fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import type { Action } from './gamepad';
	import { currentPadName } from './gamepad';
	import type { Outcome } from './types';
	import { POWER_ENTRIES, type PowerAction } from './power';
	import { LAYOUT_LABELS } from './settings.svelte.js';
	import { play as playSound } from './sound';
	import Glyph from './Glyph.svelte';

	/**
	 * Menu rapide, façon guide de console : un panneau qui glisse depuis la
	 * gauche, par-dessus l'écran du moment, ouvert par le bouton Menu (ou Home).
	 * Quatre onglets (L1 / R1) : Profil, Paramètres, Manette, Alimentation. Le
	 * dock du haut ne porte plus que l'accueil, la recherche et la bibliothèque :
	 * tout le reste passe par ici.
	 *
	 * Il ne montre que du réel : pas de ligne sans fonction derrière, ni de
	 * valeur inventée (l'API Gamepad ne donne pas la batterie d'une manette).
	 */
	let {
		open = false,
		initialTab = 0,
		initialConfirm = null,
		profileName = 'Joueur',
		avatar = '',
		accounts = [],
		clock = '',
		buttonLayout = 'ps5',
		soundEnabled = true,
		fullscreen = true,
		onClose,
		onOpenProfile,
		onEditName,
		onChangeAvatar,
		onOpenStats,
		onOpenSettings,
		onDetectGames,
		onToggleSound,
		onToggleFullscreen,
		onCycleLayout,
		onPower,
	}: {
		open?: boolean;
		/** Onglet et confirmation au premier affichage (outil de capture). */
		initialTab?: number;
		initialConfirm?: PowerAction | null;
		profileName?: string;
		avatar?: string;
		/** Comptes connectés (« Steam », « Epic Games »). */
		accounts?: string[];
		clock?: string;
		buttonLayout?: string;
		soundEnabled?: boolean;
		fullscreen?: boolean;
		onClose?: () => void;
		onOpenProfile?: () => void;
		onEditName?: () => void;
		onChangeAvatar?: () => void;
		onOpenStats?: () => void;
		onOpenSettings?: () => void;
		onDetectGames?: () => void;
		onToggleSound?: () => void;
		onToggleFullscreen?: () => void;
		onCycleLayout?: () => void;
		onPower?: (action: PowerAction) => Promise<Outcome>;
	} = $props();

	interface Row {
		label: string;
		value?: string;
		/** Sans action : une ligne d'information. */
		run?: () => void;
	}

	const TABS = [
		{ label: 'Profil', icon: 'user' },
		{ label: 'Paramètres', icon: 'settings' },
		{ label: 'Manette', icon: 'controller' },
		{ label: 'Alimentation', icon: 'power' },
	];

	/** Durée de l'écran « Extinction… » : si la machine ne s'arrête pas, on revient. */
	const LEAVING = 6000;
	/** Entrée d'une page : `--normal` et `--fast`, et le chemin parcouru en pixels. */
	const SLIDE = 260;
	const FADE = 180;
	const SHIFT = 48;

	let tab = $state(Math.min(TABS.length - 1, Math.max(0, initialTab)));
	let row = $state(0);
	/** Action d'alimentation en attente de confirmation. */
	let pending = $state<PowerAction | null>(initialConfirm);
	/** Écran affiché pendant que la machine s'arrête. */
	let leaving = $state('');
	let pad = $state('');
	/** Sens du dernier changement de page : le contenu entre du côté où l'on va. */
	let direction = $state<1 | -1>(1);

	const confirming = $derived(POWER_ENTRIES.find((entry) => entry.action === pending) ?? null);

	const rows = $derived.by((): Row[] => {
		if (confirming) {
			return [
				{ label: `${confirming.label} maintenant`, run: () => void power(confirming.action) },
				{ label: 'Annuler', run: cancelConfirm },
			];
		}
		switch (tab) {
			case 0:
				return [
					{ label: 'Voir mon profil', run: () => onOpenProfile?.() },
					{ label: 'Changer le pseudo', value: profileName, run: () => onEditName?.() },
					{ label: 'Changer la photo', run: () => onChangeAvatar?.() },
					{ label: 'Statistiques détaillées', run: () => onOpenStats?.() },
				];
			case 1:
				// Une seule ligne mène à la page : les autres agissent sur place.
				return [
					{ label: 'Tous les paramètres', run: () => onOpenSettings?.() },
					{ label: 'Détecter mes jeux', run: () => onDetectGames?.() },
					{ label: 'Sons de l’interface', value: soundEnabled ? 'Activés' : 'Désactivés', run: () => onToggleSound?.() },
					{ label: 'Affichage', value: fullscreen ? 'Plein écran' : 'Fenêtre', run: () => onToggleFullscreen?.() },
				];
			case 2:
				return [
					{ label: 'Manette', value: pad || 'Aucune' },
					{ label: 'Disposition des touches', value: LAYOUT_LABELS[buttonLayout] ?? LAYOUT_LABELS.auto, run: () => onCycleLayout?.() },
				];
			default:
				return POWER_ENTRIES.map((entry) => ({
					label: entry.label,
					run: () => {
						direction = 1;
						pending = entry.action;
						row = 0;
					},
				}));
		}
	});

	const heading = $derived(confirming ? `${confirming.label} ?` : tab === 0 ? profileName : TABS[tab].label);
	const subheading = $derived(
		confirming
			? confirming.confirmHint
			: tab === 0
				? accounts.join(' · ') || 'Aucun compte connecté'
				: profileName
	);

	function cancelConfirm() {
		direction = -1;
		pending = null;
		row = 0;
	}

	async function power(action: PowerAction) {
		pending = null;
		row = 0;
		onClose?.();
		if (action !== 'quit') {
			leaving = action === 'reboot' ? 'Redémarrage…' : 'Extinction…';
			setTimeout(() => (leaving = ''), LEAVING);
		}
		const outcome = await onPower?.(action);
		if (!outcome?.ok) leaving = '';
	}

	function goToTab(next: number) {
		if (confirming || next === tab || next < 0 || next >= TABS.length) return;
		direction = next > tab ? 1 : -1;
		tab = next;
		row = 0;
		playSound('section');
	}

	/** À chaque ouverture : première ligne, et la manette branchée à cet instant. */
	export function show() {
		row = 0;
		pending = null;
		pad = currentPadName();
	}

	/** Empreinte de la sélection, pour ne sonner que si elle bouge. */
	export function selectionKey(): string {
		return `${tab}|${row}|${pending}`;
	}

	export function handleAction(action: Action) {
		if (action === 'up') row = Math.max(0, row - 1);
		else if (action === 'down') row = Math.min(rows.length - 1, row + 1);
		else if (action === 'prev' || action === 'left') goToTab(tab - 1);
		else if (action === 'next' || action === 'right') goToTab(tab + 1);
		else if (action === 'accept') rows[row]?.run?.();
		else if (action === 'menu') onClose?.();
		else if (action === 'cancel') {
			if (confirming) cancelConfirm();
			else onClose?.();
		}
	}
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="veil" class:open onclick={() => onClose?.()}></div>

<section class="panel" class:open aria-hidden={!open}>
	<nav class="tabs" class:locked={confirming}>
		<Glyph button="l1" size="var(--dock-glyph)" />
		<div class="tab-list" style="--tab: {tab}; --tabs: {TABS.length}">
			<span class="tab-pill"></span>
			{#each TABS as entry, i (entry.label)}
				<button
					type="button"
					class="tab"
					class:active={tab === i}
					aria-label={entry.label}
					onclick={() => goToTab(i)}
				>
					<img src="/assets/icons/{entry.icon}.svg" alt="" />
				</button>
			{/each}
		</div>
		<Glyph button="r1" size="var(--dock-glyph)" />
	</nav>

	<header>
		<span class="avatar">
			{#if avatar}
				<img src={avatar} alt="" />
			{:else}
				{profileName.charAt(0).toUpperCase()}
			{/if}
		</span>
		{#key heading}
			<div class="titles" in:fade={{ duration: FADE }}>
				<h2>{heading}</h2>
				<span class="sub">{subheading}</span>
			</div>
		{/key}
		<span class="clock">{clock}</span>
	</header>

	<div class="rows" style="--row: {row}">
		<span class="glider focus-ring"></span>
		{#key confirming?.action ?? tab}
			<div class="list" in:fly={{ x: SHIFT * direction, duration: SLIDE, easing: cubicOut, opacity: 0 }}>
				{#each rows as entry, i (entry.label)}
					<button
						type="button"
						class="row"
						class:selected={open && row === i}
						onclick={() => {
							row = i;
							entry.run?.();
						}}
					>
						<span class="label">{entry.label}</span>
						{#if entry.value}
							<span class="value">{entry.value}</span>
						{/if}
					</button>
				{/each}
			</div>
		{/key}
	</div>

	<footer class="hints">
		{#if rows[row]?.run}
			<span class="hint"><Glyph button="a" size="28px" />Sélectionner</span>
		{/if}
		<span class="hint"><Glyph button="b" size="28px" />{confirming ? 'Retour' : 'Fermer'}</span>
	</footer>
</section>

{#if leaving}
	<div class="leaving">
		<h2>{leaving}</h2>
		<p>Ne débranche pas la console</p>
	</div>
{/if}

<style>
	.veil {
		position: fixed;
		inset: 0;
		z-index: 7;
		background: var(--quick-veil);
		opacity: 0;
		pointer-events: none;
		transition: opacity var(--normal) var(--ease);
	}

	.veil.open {
		opacity: 1;
		pointer-events: auto;
	}

	/* Le gris mat des fenêtres d'options (`--xbox-*`). `visibility` retire le
	   panneau fermé du parcours, après la fin de sa sortie. */
	.panel {
		position: fixed;
		z-index: 7;
		top: var(--quick-inset);
		bottom: var(--quick-inset);
		left: var(--quick-inset);
		display: flex;
		flex-direction: column;
		width: var(--quick-width);
		border: 1px solid var(--xbox-line);
		border-radius: var(--xbox-radius);
		background: var(--xbox-panel);
		box-shadow: 0 30px 90px rgba(0, 0, 0, 0.8);
		transform: translateX(calc(-100% - 2 * var(--quick-inset)));
		visibility: hidden;
		transition:
			transform var(--normal) var(--ease),
			visibility var(--normal);
	}

	.panel.open {
		transform: none;
		visibility: visible;
	}

	.tabs {
		display: flex;
		align-items: center;
		gap: 6px;
		padding: 14px 14px 0;
		transition: opacity var(--fast) var(--ease);
	}

	/* Pendant une confirmation, on ne change pas d'onglet. */
	.tabs.locked {
		opacity: 0.4;
	}

	/* L'onglet ouvert porte la pilule claire du dock, qui glisse d'un onglet à
	   l'autre : le contour reste réservé à la sélection, dans la liste. */
	.tab-list {
		position: relative;
		flex: 1;
		display: grid;
		grid-template-columns: repeat(var(--tabs), 1fr);
		isolation: isolate;
	}

	.tab-pill {
		position: absolute;
		inset: 0 auto 0 0;
		width: calc(100% / var(--tabs));
		border-radius: var(--xbox-radius);
		background: var(--dock-active);
		transform: translateX(calc(var(--tab) * 100%));
		transition: transform var(--normal) var(--ease);
	}

	.tab {
		position: relative;
		z-index: 1;
		display: grid;
		place-items: center;
		height: var(--quick-tab);
		border-radius: var(--xbox-radius);
		transition: background var(--fast) var(--ease);
	}

	.tab:hover:not(.active) {
		background: var(--dock-hover);
	}

	.tab img {
		width: var(--quick-icon);
		height: var(--quick-icon);
		opacity: 0.6;
		transition: opacity var(--fast) var(--ease);
	}

	.tab.active img {
		opacity: 1;
	}

	header {
		display: flex;
		align-items: center;
		gap: 16px;
		padding: 22px 24px;
		border-bottom: 1px solid var(--xbox-line);
	}

	/* Ronde, jamais carrée : la photo remplit son cercle, cerclé d'accent comme
	   partout ailleurs. */
	.avatar {
		flex: none;
		display: grid;
		place-items: center;
		width: var(--quick-avatar);
		height: var(--quick-avatar);
		overflow: hidden;
		border-radius: 50%;
		background: var(--accent);
		color: var(--on-accent);
		font-size: var(--quick-title);
		font-weight: 700;
		box-shadow: 0 0 0 2px var(--accent);
	}

	.avatar img {
		width: 100%;
		height: 100%;
		object-fit: cover;
	}

	.titles {
		flex: 1;
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}

	h2 {
		margin: 0;
		font-size: var(--quick-title);
		font-weight: 600;
		line-height: 1.15;
		overflow: hidden;
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	.sub {
		font-size: 17px;
		color: var(--text-dim);
		overflow: hidden;
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	.clock {
		flex: none;
		align-self: flex-start;
		font-size: 19px;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}

	.rows {
		position: relative;
		flex: 1;
		min-height: 0;
		padding: var(--options-pad);
		isolation: isolate;
	}

	.glider {
		top: var(--options-pad);
		left: var(--options-pad);
		right: var(--options-pad);
		height: var(--options-row);
		--glide-y: calc(var(--row) * (var(--options-row) + var(--options-gap)));
		--glide-scale: 1.02;
		border-radius: var(--xbox-radius);
		background: var(--surface-strong);
	}

	.list {
		display: flex;
		flex-direction: column;
		gap: var(--options-gap);
	}

	.row {
		flex: none;
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 16px;
		width: 100%;
		height: var(--options-row);
		padding: 0 18px;
		border-radius: var(--xbox-radius);
		background: var(--xbox-row);
		text-align: left;
		transition: background var(--fast) var(--ease);
	}

	.row:hover {
		background: var(--surface-strong);
	}

	/* C'est le cadre qui marque la sélection : la ligne le laisse transparaître. */
	.row.selected {
		background: transparent;
	}

	.label,
	.value {
		position: relative;
		z-index: 1;
	}

	.label {
		flex: none;
		font-size: 19px;
		font-weight: 600;
	}

	.value {
		min-width: 0;
		font-size: 17px;
		color: var(--text-dim);
		overflow: hidden;
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	.hints {
		display: flex;
		justify-content: flex-end;
		gap: 28px;
		padding: 18px 24px;
		border-top: 1px solid var(--xbox-line);
		font-size: 17px;
		color: var(--text-dim);
	}

	.hint {
		display: flex;
		align-items: center;
		gap: 10px;
	}

	.leaving {
		position: fixed;
		inset: 0;
		z-index: 9;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 12px;
		background: var(--bg);
	}

	.leaving h2 {
		font-size: var(--settings-heading);
	}

	.leaving p {
		margin: 0;
		font-size: 17px;
		color: var(--text-dim);
	}
</style>
