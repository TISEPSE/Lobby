<script lang="ts">
	import Glyph from './Glyph.svelte';
	import { currentPadName } from './gamepad';
	import { relativeTime } from './library.svelte.js';
	import { notices } from './notices.svelte.js';

	/**
	 * Panneau de droite, ouvert par le bouton Menu : ce qui se passe, d'un coup
	 * d'œil, sans quitter l'écran du moment. Notifications, heure, semaine, manette.
	 * Il ne fait que montrer : aucune ligne à choisir, B ou Menu le referment.
	 *
	 * Il ne montre que du réel, et chaque carte est indépendante : une section de
	 * plus (des amis, si Discord l'autorise un jour) n'a qu'à s'y ajouter.
	 */
	let {
		open = false,
		clock = '',
		onClose,
	}: {
		open?: boolean;
		clock?: string;
		onClose?: () => void;
	} = $props();

	/** Notifications affichées : le reste se relit dans Réglages → Système. */
	const SHOWN = 3;
	const WEEK_DAYS = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
	const BATTERY: Record<string, string> = {
		wired: 'Sur secteur',
		empty: 'Batterie vide',
		low: 'Batterie faible',
		medium: 'Batterie moyenne',
		full: 'Batterie pleine',
	};

	let today = $state(new Date());
	let pad = $state('');
	let battery = $state('');

	const longDate = $derived(today.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' }));
	const month = $derived(today.toLocaleDateString('fr-FR', { month: 'long', year: 'numeric' }));

	/** Lundi de la semaine en cours, par le calendrier (changement d'heure). */
	const monday = $derived(
		new Date(today.getFullYear(), today.getMonth(), today.getDate() - ((today.getDay() + 6) % 7))
	);
	const week = $derived(
		WEEK_DAYS.map((letter, i) => {
			const day = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i);
			return { letter, day: day.getDate(), today: day.toDateString() === today.toDateString() };
		})
	);
	/** Numéro de semaine ISO : celle du jeudi, comptée depuis la première de l'année. */
	const weekNumber = $derived.by(() => {
		const thursday = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + 3);
		const first = new Date(thursday.getFullYear(), 0, 1);
		return Math.floor(Math.round((thursday.getTime() - first.getTime()) / 86_400_000) / 7) + 1;
	});

	/** À chaque ouverture : la date, la manette et sa batterie à cet instant. */
	export async function show() {
		today = new Date();
		pad = currentPadName();
		battery = '';
		if (!(window as any).__TAURI_INTERNALS__) return;
		const { invoke } = await import('@tauri-apps/api/core');
		battery = BATTERY[(await invoke<string | null>('pad_battery').catch(() => null)) ?? ''] ?? '';
	}
</script>

<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
<div class="veil" class:open onclick={() => onClose?.()}></div>

<aside class="panel" class:open aria-hidden={!open}>
	<section class="card">
		<header>
			<h3>Notifications</h3>
			{#if notices.length}<span class="count">{notices.length}</span>{/if}
		</header>
		{#if notices.length === 0}
			<p class="empty">Aucune notification</p>
		{:else}
			<ul>
				{#each notices.slice(0, SHOWN) as notice (notice.at + notice.message)}
					<li class:failed={!notice.ok}>
						<span class="message">{notice.message}</span>
						<span class="when">{relativeTime(notice.at)}</span>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	<section class="card now">
		<span class="clock">{clock}</span>
		<span class="date">{longDate}</span>
	</section>

	<section class="card">
		<header>
			<h3 class="month">{month}</h3>
			<span class="count">Sem. {weekNumber}</span>
		</header>
		<ol class="week">
			{#each week as day, i (i)}
				<li class:today={day.today}>
					<span class="letter">{day.letter}</span>
					<span class="number">{day.day}</span>
				</li>
			{/each}
		</ol>
	</section>

	<section class="card pad">
		<img src="/assets/icons/controller.svg" alt="" />
		<div>
			<h3>{pad || 'Aucune manette'}</h3>
			{#if pad && battery}<span class="when">{battery}</span>{/if}
		</div>
	</section>

	<footer>
		<span class="hint"><Glyph button="b" size="28px" />Fermer</span>
	</footer>
</aside>

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

	/* Le miroir du menu rapide : mêmes marges, même gris mat, mêmes durées. */
	.panel {
		position: fixed;
		z-index: 7;
		top: var(--quick-inset);
		bottom: var(--quick-inset);
		right: var(--quick-inset);
		display: flex;
		flex-direction: column;
		gap: var(--side-gap);
		width: var(--side-width);
		padding: var(--side-gap);
		border: 1px solid var(--xbox-line);
		border-radius: var(--xbox-radius);
		background: var(--xbox-panel);
		box-shadow: 0 30px 90px rgba(0, 0, 0, 0.8);
		transform: translateX(calc(100% + 2 * var(--quick-inset)));
		visibility: hidden;
		transition:
			transform var(--normal) var(--ease),
			visibility var(--normal);
	}

	.panel.open {
		transform: none;
		visibility: visible;
	}

	.card {
		display: flex;
		flex-direction: column;
		gap: 10px;
		padding: 16px 18px;
		border: 1px solid var(--xbox-line);
		border-radius: var(--settings-radius);
		background: var(--xbox-row);
	}

	header {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 12px;
	}

	h3 {
		margin: 0;
		font-size: 19px;
		font-weight: 600;
	}

	.month::first-letter {
		text-transform: uppercase;
	}

	.count,
	.when,
	.empty {
		font-size: 17px;
		color: var(--text-dim);
	}

	.empty {
		margin: 0;
	}

	ul {
		display: flex;
		flex-direction: column;
		gap: 10px;
		margin: 0;
		padding: 0;
		list-style: none;
	}

	li {
		display: flex;
		flex-direction: column;
		gap: 2px;
	}

	.message {
		display: -webkit-box;
		-webkit-box-orient: vertical;
		-webkit-line-clamp: 2;
		overflow: hidden;
		font-size: 17px;
		line-height: 1.3;
	}

	ul .failed .message {
		color: var(--danger);
	}

	.now {
		align-items: center;
		gap: 2px;
	}

	.clock {
		font-size: var(--side-clock);
		font-weight: 700;
		font-variant-numeric: tabular-nums;
		line-height: 1.1;
	}

	.date {
		font-size: 18px;
		color: var(--text-dim);
	}

	.date::first-letter {
		text-transform: uppercase;
	}

	.week {
		display: grid;
		grid-template-columns: repeat(7, 1fr);
		margin: 0;
		padding: 0;
		list-style: none;
	}

	.week li {
		align-items: center;
		gap: 4px;
	}

	.letter {
		font-size: 17px;
		color: var(--text-dim);
	}

	.number {
		display: grid;
		place-items: center;
		width: var(--side-day);
		height: var(--side-day);
		border-radius: 50%;
		font-size: 18px;
		font-weight: 600;
		font-variant-numeric: tabular-nums;
	}

	.today .number {
		background: var(--accent);
		color: var(--on-accent);
	}

	.pad {
		flex-direction: row;
		align-items: center;
		gap: 14px;
	}

	.pad img {
		flex: none;
		width: 30px;
		height: 30px;
	}

	footer {
		display: flex;
		justify-content: flex-end;
		margin-top: auto;
		font-size: 17px;
		color: var(--text-dim);
	}

	.hint {
		display: flex;
		align-items: center;
		gap: 10px;
	}
</style>
