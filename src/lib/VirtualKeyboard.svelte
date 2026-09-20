<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import type { Action } from './gamepad';
	import HelpBar from './HelpBar.svelte';

	let {
		open = false,
		title = 'Modifier le pseudo',
		subtitle = 'Saisis ton nom avec la manette ou le clavier',
		initialValue = '',
		maxLength = 24,
		onConfirm,
		onClose,
	}: {
		open: boolean;
		title?: string;
		subtitle?: string;
		initialValue: string;
		maxLength?: number;
		onConfirm: (val: string) => void;
		onClose: () => void;
	} = $props();

	interface KeyDef {
		id: string;
		label: string;
		type?: 'char' | 'space' | 'backspace' | 'caps' | 'cancel' | 'confirm';
		width?: number; // flex weight
	}

	let text = $state('');
	let isCaps = $state(true);
	let currentRow = $state(1); // commence sur la 1ère ligne de lettres
	let currentCol = $state(0);
	let inputRef = $state<HTMLInputElement | null>(null);

	$effect(() => {
		if (open) {
			text = initialValue;
			currentRow = 1;
			currentCol = 0;
			setTimeout(() => {
				if (inputRef) {
					inputRef.focus();
					inputRef.select();
				}
			}, 60);
		}
	});

	// Rangées de touches façon clavier console (AZERTY)
	const row0Numbers: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '_'];
	const row1Letters: string[] = ['A', 'Z', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
	const row2Letters: string[] = ['Q', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'M'];
	const row3Letters: string[] = ['W', 'X', 'C', 'V', 'B', 'N', '\'', '.', '@', '#'];

	const keysGrid = $derived.by(() => {
		const r0: KeyDef[] = row0Numbers.map((c) => ({ id: c, label: c, type: 'char' }));
		const r1: KeyDef[] = row1Letters.map((c) => ({
			id: c,
			label: isCaps ? c.toUpperCase() : c.toLowerCase(),
			type: 'char',
		}));
		const r2: KeyDef[] = row2Letters.map((c) => ({
			id: c,
			label: isCaps ? c.toUpperCase() : c.toLowerCase(),
			type: 'char',
		}));
		const r3: KeyDef[] = row3Letters.map((c) => ({
			id: c,
			label: isCaps ? c.toUpperCase() : c.toLowerCase(),
			type: 'char',
		}));
		const r4: KeyDef[] = [
			{ id: 'caps', label: isCaps ? '⇪ MAJ' : '⇧ MIN', type: 'caps', width: 1.4 },
			{ id: 'space', label: 'ESPACE ␣', type: 'space', width: 2.8 },
			{ id: 'backspace', label: 'EFFACER ⌫', type: 'backspace', width: 1.6 },
			{ id: 'cancel', label: 'ANNULER ✕', type: 'cancel', width: 1.4 },
			{ id: 'confirm', label: 'VALIDER ✓', type: 'confirm', width: 2 },
		];

		return [r0, r1, r2, r3, r4];
	});

	export function handleAction(action: Action) {
		if (!open) return;

		if (action === 'up') {
			currentRow = Math.max(0, currentRow - 1);
			clampCol();
		} else if (action === 'down') {
			currentRow = Math.min(keysGrid.length - 1, currentRow + 1);
			clampCol();
		} else if (action === 'left') {
			const maxCol = keysGrid[currentRow].length - 1;
			currentCol = currentCol > 0 ? currentCol - 1 : maxCol;
		} else if (action === 'right') {
			const maxCol = keysGrid[currentRow].length - 1;
			currentCol = currentCol < maxCol ? currentCol + 1 : 0;
		} else if (action === 'accept') {
			const activeKey = keysGrid[currentRow]?.[currentCol];
			if (activeKey) pressKey(activeKey);
		} else if (action === 'cancel') {
			onClose();
		} else if (action === 'options') {
			// Touche X (PlayStation Carré / Xbox X) : Effacer
			handleBackspace();
		} else if (action === 'search') {
			// Touche Y (PlayStation Triangle / Xbox Y) : Espace
			handleSpace();
		} else if (action === 'prev' || action === 'next') {
			// LB / RB : Bascule Maj / Min
			isCaps = !isCaps;
		} else if (action === 'menu') {
			// Start : Valider direct
			handleConfirm();
		}
	}

	function clampCol() {
		const maxCol = keysGrid[currentRow].length - 1;
		if (currentCol > maxCol) {
			currentCol = maxCol;
		}
	}

	function pressKey(key: KeyDef) {
		switch (key.type) {
			case 'caps':
				isCaps = !isCaps;
				break;
			case 'space':
				handleSpace();
				break;
			case 'backspace':
				handleBackspace();
				break;
			case 'cancel':
				onClose();
				break;
			case 'confirm':
				handleConfirm();
				break;
			case 'char':
			default:
				if (text.length < maxLength) {
					text += key.label;
				}
				break;
		}
	}

	function handleSpace() {
		if (text.length < maxLength) {
			text += ' ';
		}
	}

	function handleBackspace() {
		if (text.length > 0) {
			text = text.slice(0, -1);
		}
	}

	function handleConfirm() {
		const clean = text.trim();
		if (clean) {
			onConfirm(clean);
		} else {
			onClose();
		}
	}

	function handleClearAll() {
		text = '';
	}

	// Permet la saisie au vrai clavier si l'utilisateur tape physiquement
	function onKeyDown(e: KeyboardEvent) {
		if (!open) return;

		if (e.key === 'Escape') {
			e.preventDefault();
			onClose();
		} else if (e.key === 'Enter') {
			e.preventDefault();
			handleConfirm();
		} else if (e.target !== inputRef && e.key.length === 1 && !e.ctrlKey && !e.altKey && !e.metaKey) {
			// Si le focus était sorti du champ, on y renvoie la frappe
			inputRef?.focus();
		}
	}

	onMount(() => {
		window.addEventListener('keydown', onKeyDown);
		return () => window.removeEventListener('keydown', onKeyDown);
	});
</script>

{#if open}
	<div class="keyboard-backdrop" role="dialog" aria-modal="true">
		<div class="keyboard-modal">
			<!-- En-tête -->
			<header class="header">
				<div class="header-titles">
					<h2 class="title">{title}</h2>
					<p class="subtitle">{subtitle}</p>
				</div>
				<button type="button" class="btn-close" onclick={onClose} aria-label="Fermer">
					✕
				</button>
			</header>

			<!-- Boîte de saisie / Aperçu interactif avec vrai input -->
			<div class="display-box" onclick={() => inputRef?.focus()} role="presentation">
				<input
					type="text"
					bind:this={inputRef}
					bind:value={text}
					maxlength={maxLength}
					class="real-text-input"
					placeholder="Entrez un pseudo…"
					autocomplete="off"
					spellcheck="false"
				/>

				<div class="display-meta">
					{#if text.length > 0}
						<button type="button" class="btn-clear-all" onclick={handleClearAll}>
							Effacer tout
						</button>
					{/if}
					<span class="char-count">{text.length} / {maxLength}</span>
				</div>
			</div>

			<!-- Grille de touches virtuelle -->
			<div class="keys-container">
				{#each keysGrid as row, rIdx}
					<div class="key-row">
						{#each row as key, cIdx}
							{@const isFocused = currentRow === rIdx && currentCol === cIdx}
							<button
								type="button"
								class="key-btn"
								class:focused={isFocused}
								class:special={key.type !== 'char'}
								class:confirm={key.type === 'confirm'}
								class:backspace={key.type === 'backspace'}
								style:flex={key.width ?? 1}
								onclick={() => {
									currentRow = rIdx;
									currentCol = cIdx;
									pressKey(key);
								}}
							>
								{key.label}
							</button>
						{/each}
					</div>
				{/each}
			</div>

			<!-- Légende d'aide console -->
			<div class="help-section">
				<HelpBar
					entries={[
						{ button: 'a', label: 'Taper' },
						{ button: 'x', label: 'Effacer' },
						{ button: 'y', label: 'Espace' },
						{ button: 'b', label: 'Annuler' },
					]}
				/>
				<span class="hint-shortcuts">LB / RB : Maj · Menu : Valider</span>
			</div>
		</div>
	</div>
{/if}

<style>
	.keyboard-backdrop {
		position: fixed;
		inset: 0;
		z-index: 50;
		display: grid;
		place-items: center;
		background: rgba(3, 6, 12, 0.86);
		backdrop-filter: blur(24px);
		animation: fade-in 180ms var(--ease);
	}

	.keyboard-modal {
		display: flex;
		flex-direction: column;
		gap: 20px;
		width: min(880px, 94vw);
		padding: 32px 38px 26px;
		border-radius: calc(var(--radius) * 1.5);
		background: rgba(18, 24, 38, 0.88);
		border: 1px solid rgba(255, 255, 255, 0.14);
		box-shadow: 0 28px 70px rgba(0, 0, 0, 0.85);
		animation: scale-up 200ms var(--ease);
	}

	.header {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 16px;
	}

	.title {
		margin: 0;
		font-size: 26px;
		font-weight: 800;
		color: #ffffff;
		letter-spacing: -0.5px;
	}

	.subtitle {
		margin: 4px 0 0;
		font-size: 14px;
		color: var(--text-dim);
	}

	.btn-close {
		width: 36px;
		height: 36px;
		border-radius: 50%;
		display: grid;
		place-items: center;
		background: rgba(255, 255, 255, 0.08);
		color: var(--text-dim);
		font-size: 16px;
		cursor: pointer;
		transition: all 150ms var(--ease);
	}

	.btn-close:hover {
		background: rgba(255, 255, 255, 0.2);
		color: #ffffff;
	}

	/* Zone de visualisation du texte */
	.display-box {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 16px;
		padding: 14px 24px;
		border-radius: var(--radius);
		background: rgba(0, 0, 0, 0.45);
		border: 2px solid rgba(255, 255, 255, 0.12);
		box-shadow: inset 0 2px 8px rgba(0, 0, 0, 0.5);
		cursor: text;
		transition: all 180ms var(--ease);
	}

	.display-box:focus-within {
		border-color: var(--accent);
		outline: 3px solid var(--accent);
		box-shadow:
			0 0 24px 4px var(--accent-soft),
			inset 0 2px 8px rgba(0, 0, 0, 0.5);
	}

	.real-text-input {
		flex: 1;
		width: 100%;
		border: none;
		outline: none;
		background: transparent;
		font-family: inherit;
		font-size: 28px;
		font-weight: 700;
		color: #ffffff;
		letter-spacing: 0.5px;
	}

	.real-text-input::placeholder {
		color: rgba(255, 255, 255, 0.3);
		font-weight: 500;
	}

	.display-meta {
		display: flex;
		align-items: center;
		gap: 14px;
		flex-shrink: 0;
	}

	.btn-clear-all {
		padding: 4px 10px;
		border-radius: 6px;
		background: rgba(255, 255, 255, 0.1);
		color: var(--text-dim);
		font-size: 12px;
		font-weight: 600;
		cursor: pointer;
		transition: all 150ms var(--ease);
	}

	.btn-clear-all:hover {
		background: rgba(255, 255, 255, 0.2);
		color: #ffffff;
	}

	.char-count {
		font-size: 14px;
		font-weight: 600;
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	/* Grille des touches */
	.keys-container {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}

	.key-row {
		display: flex;
		gap: 8px;
		width: 100%;
	}

	.key-btn {
		display: grid;
		place-items: center;
		height: 52px;
		min-width: 44px;
		border-radius: 10px;
		background: rgba(255, 255, 255, 0.07);
		border: 1px solid rgba(255, 255, 255, 0.1);
		color: #ffffff;
		font-size: 17px;
		font-weight: 700;
		cursor: pointer;
		transition: all 140ms cubic-bezier(0.2, 0, 0, 1);
		user-select: none;
	}

	.key-btn:hover {
		background: rgba(255, 255, 255, 0.15);
		border-color: rgba(255, 255, 255, 0.25);
	}

	.key-btn.special {
		background: rgba(255, 255, 255, 0.05);
		font-size: 14px;
		font-weight: 600;
		letter-spacing: 0.5px;
	}

	.key-btn.confirm {
		background: rgba(255, 255, 255, 0.16);
		border-color: rgba(255, 255, 255, 0.3);
		color: #ffffff;
		font-weight: 700;
	}

	.key-btn.backspace {
		color: #ff9b9b;
	}

	/* État focus manette / clavier */
	.key-btn.focused {
		background: #ffffff;
		color: #0b0f19;
		border-color: #ffffff;
		transform: scale(1.08);
		box-shadow: 0 0 22px rgba(255, 255, 255, 0.45);
		z-index: 2;
	}

	.key-btn.confirm.focused {
		background: #ffffff;
		color: #0b0f19;
		box-shadow: 0 0 28px rgba(255, 255, 255, 0.55);
	}

	.key-btn.backspace.focused {
		background: #ff5555;
		color: #ffffff;
		border-color: #ff5555;
		box-shadow: 0 0 24px rgba(255, 85, 85, 0.5);
	}

	/* Pied de page et aide */
	.help-section {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding-top: 8px;
		border-top: 1px solid rgba(255, 255, 255, 0.08);
	}

	.hint-shortcuts {
		font-size: 13px;
		color: var(--text-dim);
		opacity: 0.7;
	}

	@keyframes blink {
		0%, 50% { opacity: 1; }
		50.1%, 100% { opacity: 0; }
	}

	@keyframes fade-in {
		from { opacity: 0; }
		to { opacity: 1; }
	}

	@keyframes scale-up {
		from { opacity: 0; transform: scale(0.96) translateY(8px); }
		to { opacity: 1; transform: scale(1) translateY(0); }
	}
</style>
