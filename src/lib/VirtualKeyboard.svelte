<script lang="ts">
	/**
	 * Saisie de texte : pseudo, clé SteamGridDB, et la **recherche** — qui y
	 * ajoute un suivi de la frappe (`onInput`), une sortie par le bas vers ses
	 * résultats (`onLeaveBottom`) et les résultats eux-mêmes (`children`).
	 *
	 * Les touches sont rendues par `Keyboard.svelte`, le même composant que
	 * l'écran de recherche : une touche a la même allure partout dans
	 * l'interface, et son style ne se règle qu'à un endroit.
	 */
	import { onMount, type Snippet } from 'svelte';
	import type { Action } from './gamepad';
	import Keyboard from './Keyboard.svelte';
	import { textKeyboardRows, nearestColumn } from './searchKeys';

	let {
		open = false,
		title = 'Modifier le pseudo',
		subtitle = 'Saisis ton texte avec la manette ou le clavier',
		initialValue = '',
		maxLength = 24,
		onConfirm,
		onClose,
		onInput,
		onLeaveBottom,
		active = true,
		wide = false,
		placeholder = 'Saisis ton texte…',
		children,
	}: {
		open: boolean;
		title?: string;
		subtitle?: string;
		initialValue: string;
		maxLength?: number;
		onConfirm: (val: string) => void;
		onClose: () => void;
		/** Appelé à chaque frappe : la recherche filtre en direct. */
		onInput?: (value: string) => void;
		/** « Bas » sous la dernière rangée : la sélection quitte le clavier. */
		onLeaveBottom?: () => void;
		/** Le clavier a la main ; sinon la sélection est dans `children`. */
		active?: boolean;
		/** Fenêtre plus large, pour loger des résultats sous le clavier. */
		wide?: boolean;
		placeholder?: string;
		/** Contenu affiché sous le clavier (résultats de la recherche). */
		children?: Snippet;
	} = $props();

	let text = $state('');
	let isCaps = $state(true);
	let row = $state(1);
	let col = $state(0);
	let inputRef = $state<HTMLInputElement | null>(null);

	const rows = $derived(textKeyboardRows(isCaps));

	$effect(() => {
		if (!open) return;
		text = initialValue;
		row = 1;
		col = 0;
		setTimeout(() => {
			inputRef?.focus();
			inputRef?.select();
		}, 60);
	});

	$effect(() => {
		onInput?.(text);
	});

	export function handleAction(action: Action) {
		if (!open) return;

		if (action === 'down' && row === rows.length - 1 && onLeaveBottom) {
			onLeaveBottom();
			return;
		}
		if (action === 'up') {
			const next = Math.max(0, row - 1);
			col = nearestColumn(row, col, next, rows);
			row = next;
		} else if (action === 'down') {
			const next = Math.min(rows.length - 1, row + 1);
			col = nearestColumn(row, col, next, rows);
			row = next;
		} else if (action === 'left') {
			col = col > 0 ? col - 1 : rows[row].length - 1;
		} else if (action === 'right') {
			col = col < rows[row].length - 1 ? col + 1 : 0;
		} else if (action === 'accept') {
			press(row, col);
		} else if (action === 'cancel') {
			onClose();
		} else if (action === 'options') {
			backspace();
		} else if (action === 'search') {
			insert(' ');
		} else if (action === 'prev' || action === 'next') {
			isCaps = !isCaps;
		} else if (action === 'menu') {
			confirm();
		}
	}

	function press(r: number, c: number) {
		row = r;
		col = c;
		const key = rows[r]?.[c];
		if (!key) return;
		switch (key.action) {
			case 'caps':
				isCaps = !isCaps;
				break;
			case 'space':
				insert(' ');
				break;
			case 'backspace':
				backspace();
				break;
			case 'clear':
				text = '';
				break;
			case 'cancel':
				onClose();
				break;
			case 'confirm':
				confirm();
				break;
			default:
				insert(key.value);
		}
	}

	function insert(value: string) {
		if (text.length < maxLength) text += value;
	}

	function backspace() {
		text = text.slice(0, -1);
	}

	function confirm() {
		const clean = text.trim();
		if (clean) onConfirm(clean);
		else onClose();
	}

	/** Saisie au vrai clavier : la frappe va dans le champ, pas dans la grille. */
	function onKeyDown(event: KeyboardEvent) {
		if (!open) return;
		if (event.key === 'Escape') {
			event.preventDefault();
			onClose();
		} else if (event.key === 'Enter') {
			event.preventDefault();
			confirm();
		} else if (
			event.target !== inputRef &&
			event.key.length === 1 &&
			!event.ctrlKey &&
			!event.altKey &&
			!event.metaKey
		) {
			inputRef?.focus();
		}
	}

	onMount(() => {
		window.addEventListener('keydown', onKeyDown);
		return () => window.removeEventListener('keydown', onKeyDown);
	});
</script>

{#if open}
	<div class="backdrop" role="dialog" aria-modal="true">
		<div class="modal" class:wide>
			<header>
				<h2>{title}</h2>
				<p class="subtitle">{subtitle}</p>
			</header>

			<div class="display" onclick={() => inputRef?.focus()} role="presentation">
				<input
					type="text"
					bind:this={inputRef}
					bind:value={text}
					maxlength={maxLength}
					{placeholder}
					autocomplete="off"
					spellcheck="false"
				/>
				<span class="count">{text.length} / {maxLength}</span>
			</div>

			<div class="pad">
				<Keyboard {rows} {row} {col} {active} onPress={press} />
			</div>

			{@render children?.()}

			<!-- L'aide des touches est celle de l'application, en bas de l'écran :
			     deux barres superposées se chevauchaient. Ici, seuls les raccourcis
			     propres au clavier. -->
			{#if !children}
				<p class="hint">LB / RB : Maj · Menu : Valider</p>
			{/if}
		</div>
	</div>
{/if}

<style>
	.backdrop {
		position: fixed;
		inset: 0;
		z-index: 50;
		display: grid;
		place-items: center;
		background: rgba(3, 6, 12, 0.86);
		backdrop-filter: blur(24px);
		animation: fade-in var(--fast) var(--ease);
	}

	.modal.wide {
		width: min(1500px, 94vw);
	}

	/* Le clavier garde sa largeur habituelle, centré : seuls le champ et les
	   résultats profitent de la fenêtre élargie. */
	.wide .pad {
		width: min(880px, 100%);
		margin: 0 auto;
	}

	.modal {
		display: flex;
		flex-direction: column;
		gap: 20px;
		width: min(880px, 94vw);
		padding: 32px 38px 26px;
		border-radius: calc(var(--radius) * 1.5);
		background: rgba(18, 24, 38, 0.88);
		box-shadow: 0 28px 70px rgba(0, 0, 0, 0.85);
		animation: scale-up 200ms var(--ease);
	}

	h2 {
		margin: 0;
		font-size: 26px;
		font-weight: 800;
		letter-spacing: -0.02em;
	}

	.subtitle {
		margin: 4px 0 0;
		font-size: 15px;
		color: var(--text-dim);
	}

	.display {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 16px;
		padding: 14px 24px;
		border-radius: var(--radius);
		background: rgba(0, 0, 0, 0.45);
		box-shadow: inset 0 0 0 2px rgba(255, 255, 255, 0.12);
		cursor: text;
	}

	.display:focus-within {
		box-shadow: inset 0 0 0 2px var(--accent);
	}

	input {
		flex: 1;
		border: none;
		outline: none;
		background: transparent;
		font-family: inherit;
		font-size: 28px;
		font-weight: 700;
		color: #fff;
	}

	input::placeholder {
		color: rgba(255, 255, 255, 0.3);
		font-weight: 500;
	}

	.count {
		font-size: 14px;
		font-weight: 600;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	/* Touches un peu plus compactes que sur l'écran de recherche : la modale
	   doit tenir dans sa largeur, le style reste le même. */
	.pad {
		--key-size: 50px;
		--key-font: 22px;
		--key-gap: 8px;
	}

	.hint {
		margin: 0 0 0 auto;
		font-size: 14px;
		color: var(--text-dim);
	}

	@keyframes fade-in {
		from {
			opacity: 0;
		}
	}

	@keyframes scale-up {
		from {
			opacity: 0;
			transform: scale(0.97);
		}
	}
</style>
