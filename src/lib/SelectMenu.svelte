<script lang="ts">
	import { tick } from 'svelte';
	import type { Action } from './gamepad';
	import type { SelectRequest } from './types';

	/**
	 * Menu déroulant, à la place des boutons qui faisaient défiler leurs valeurs à
	 * l'aveugle : tout est visible, la valeur actuelle est cochée, A choisit et
	 * B referme sans rien changer. Il s'ancre à son bouton et se retourne vers le
	 * haut quand la place manque ; sans ancre, il se centre.
	 *
	 * Une seule instance, dans `App.svelte` : chaque écran ne fait que la demander.
	 */
	let {
		request = null,
		onClose,
	}: {
		request?: SelectRequest | null;
		onClose?: () => void;
	} = $props();

	let index = $state(0);
	let panel = $state<HTMLElement | null>(null);
	let position = $state('');

	// À chaque ouverture : la sélection part de la valeur actuelle.
	$effect(() => {
		if (!request) return;
		index = Math.max(0, request.options.findIndex((option) => option.id === request.value));
		void place(request);
	});

	/** Sous l'ancre, au-dessus si ça déborde, toujours dans l'écran. */
	async function place(current: SelectRequest) {
		position = '';
		await tick();
		if (!panel || !current.anchor) return;
		const anchor = current.anchor.getBoundingClientRect();
		const { offsetWidth: width, offsetHeight: height } = panel;
		const margin = parseFloat(getComputedStyle(panel).getPropertyValue('--select-margin')) || 0;
		const below = anchor.bottom + margin;
		const top = below + height + margin <= innerHeight ? below : Math.max(margin, anchor.top - height - margin);
		const left = Math.min(Math.max(margin, anchor.left), innerWidth - width - margin);
		position = `top: ${top}px; left: ${left}px; transform: none`;
	}

	function pick(i: number) {
		const option = request?.options[i];
		if (!option) return;
		request?.onPick(option.id);
		onClose?.();
	}

	/** Empreinte de la sélection, pour ne sonner que si elle bouge. */
	export function selectionKey(): string {
		return String(index);
	}

	export function handleAction(action: Action) {
		if (!request) return;
		if (action === 'up') index = Math.max(0, index - 1);
		else if (action === 'down') index = Math.min(request.options.length - 1, index + 1);
		else if (action === 'accept') pick(index);
		else if (action === 'cancel') onClose?.();
	}
</script>

{#if request}
	<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
	<div class="veil" onclick={() => onClose?.()}></div>
	<div class="menu" bind:this={panel} style={position} role="listbox" aria-label={request.title}>
		<h3>{request.title}</h3>
		<div class="options" style="--index: {index}">
			<span class="glider focus-ring"></span>
			{#each request.options as option, i (option.id)}
				<button
					type="button"
					class="option"
					class:selected={index === i}
					role="option"
					aria-selected={option.id === request.value}
					onclick={() => pick(i)}
				>
					<span class="check">
						{#if option.id === request.value}<img src="/assets/icons/check.svg" alt="" />{/if}
					</span>
					<span class="label">{option.label}</span>
					{#if option.preview}
						<span class="preview">
							{#each option.preview as src (src)}<img {src} alt="" />{/each}
						</span>
					{/if}
				</button>
			{/each}
		</div>
	</div>
{/if}

<style>
	.veil {
		position: fixed;
		inset: 0;
		z-index: 11;
		background: var(--select-veil);
		animation: appear var(--fast) var(--ease) both;
	}

	/* Centré tant qu'aucune ancre ne l'a placé. */
	.menu {
		position: fixed;
		z-index: 11;
		top: 50%;
		left: 50%;
		transform: translate(-50%, -50%);
		width: var(--select-width);
		padding: var(--select-pad);
		border: 1px solid var(--xbox-line);
		border-radius: var(--settings-radius);
		background: var(--files-panel);
		box-shadow: 0 24px 60px rgba(0, 0, 0, 0.7);
		animation: appear var(--fast) var(--ease) both;
	}

	@keyframes appear {
		from {
			opacity: 0;
		}
	}

	h3 {
		margin: 0;
		padding: 4px 8px 12px;
		font-size: 17px;
		font-weight: 600;
		color: var(--text-dim);
	}

	.options {
		position: relative;
		display: flex;
		flex-direction: column;
		gap: var(--select-gap);
		isolation: isolate;
	}

	.glider {
		top: 0;
		left: 0;
		right: 0;
		height: var(--select-row);
		--glide-y: calc(var(--index) * (var(--select-row) + var(--select-gap)));
		border-radius: var(--xbox-radius);
		background: var(--files-row-focus);
	}

	.option {
		display: flex;
		align-items: center;
		gap: 10px;
		height: var(--select-row);
		padding: 0 14px 0 10px;
		border-radius: var(--xbox-radius);
		background: var(--files-row-bg);
		font-size: 19px;
		font-weight: 600;
		text-align: left;
		transition: background var(--normal) var(--ease);
	}

	.option.selected {
		background: transparent;
	}

	.option > * {
		position: relative;
		z-index: 1;
	}

	.check {
		flex: none;
		display: grid;
		place-items: center;
		width: var(--select-check);
		height: var(--select-check);
	}

	.check img {
		width: 100%;
		height: 100%;
	}

	.label {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	.preview {
		flex: none;
		display: flex;
		gap: 4px;
	}

	.preview img {
		width: var(--select-glyph);
		height: var(--select-glyph);
	}
</style>
