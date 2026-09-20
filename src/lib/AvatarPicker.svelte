<script lang="ts">
	import HelpBar from './HelpBar.svelte';

	let {
		open = false,
		current = '',
		profileName = 'Joueur',
		onSelect,
		onClose,
	}: {
		open: boolean;
		current: string;
		profileName: string;
		onSelect: (path: string) => void;
		onClose: () => void;
	} = $props();

	const AVATARS = [
		'', // Initiale
		'/assets/avatars/a01_play.svg',
		'/assets/avatars/a02_blocks.svg',
		'/assets/avatars/a03_ring.svg',
		'/assets/avatars/a04_bolt.svg',
		'/assets/avatars/a05_cross.svg',
		'/assets/avatars/a06_bars.svg',
		'/assets/avatars/a07_gem.svg',
		'/assets/avatars/a08_moon.svg',
		'/assets/avatars/a09_check.svg',
		'/assets/avatars/a10_hex.svg',
		'/assets/avatars/a11_face.svg',
		'/assets/avatars/a12_star.svg',
	];

	const COLUMNS = 5;
	let focusedIndex = $state(0);

	$effect(() => {
		if (open) {
			const found = AVATARS.indexOf(current);
			focusedIndex = found >= 0 ? found : 0;
		}
	});

	export function handleAction(action: string) {
		if (!open) return;
		const total = AVATARS.length;
		if (action === 'left') {
			if (focusedIndex % COLUMNS > 0) focusedIndex--;
		} else if (action === 'right') {
			if (focusedIndex % COLUMNS < COLUMNS - 1 && focusedIndex + 1 < total) focusedIndex++;
		} else if (action === 'up') {
			if (focusedIndex - COLUMNS >= 0) focusedIndex -= COLUMNS;
		} else if (action === 'down') {
			if (focusedIndex + COLUMNS < total) focusedIndex += COLUMNS;
		} else if (action === 'accept') {
			onSelect(AVATARS[focusedIndex]);
			onClose();
		} else if (action === 'cancel') {
			onClose();
		}
	}
</script>

{#if open}
	<div class="overlay" role="dialog" aria-modal="true">
		<div class="dialog">
			<header>
				<h2>Photo de profil</h2>
				<p>Choisis une illustration pour ton profil ou conserve l'initiale de ton pseudo.</p>
			</header>

			<div class="grid">
				{#each AVATARS as avatar, i}
					<button
						type="button"
						class="cell"
						class:active={focusedIndex === i}
						class:selected={current === avatar}
						onclick={() => {
							focusedIndex = i;
							onSelect(avatar);
							onClose();
						}}
					>
						{#if avatar}
							<img src={avatar} alt="" class="avatar-img" />
						{:else}
							<span class="initial">{profileName.charAt(0).toUpperCase() || 'J'}</span>
						{/if}
					</button>
				{/each}
			</div>

			<div class="footer">
				<HelpBar
					entries={[
						{ button: 'a', label: 'Choisir' },
						{ button: 'b', label: 'Fermer' },
					]}
				/>
			</div>
		</div>
	</div>
{/if}

<style>
	.overlay {
		position: fixed;
		inset: 0;
		z-index: 10;
		display: grid;
		place-items: center;
		background: rgba(3, 5, 8, 0.78);
		backdrop-filter: blur(16px);
		animation: fade-in 180ms var(--ease);
	}

	.dialog {
		display: flex;
		flex-direction: column;
		gap: 28px;
		width: min(680px, 90vw);
		padding: 36px 44px;
		border-radius: calc(var(--radius) * 1.5);
		background: var(--surface-strong);
		border: 1px solid var(--border);
		box-shadow: 0 24px 60px rgba(0, 0, 0, 0.6);
		animation: scale-in 220ms var(--ease);
	}

	header h2 {
		margin: 0 0 6px;
		font-size: 28px;
		font-weight: 700;
		color: var(--text);
	}

	header p {
		margin: 0;
		font-size: 16px;
		color: var(--text-dim);
	}

	.grid {
		display: grid;
		grid-template-columns: repeat(5, 1fr);
		gap: 16px;
		place-items: center;
	}

	.cell {
		display: grid;
		place-items: center;
		width: 92px;
		height: 92px;
		border-radius: 50%;
		background: var(--surface);
		border: 2px solid transparent;
		cursor: pointer;
		transition: transform 180ms var(--ease), border-color 180ms var(--ease), box-shadow 180ms var(--ease);
		padding: 0;
	}

	.cell.selected {
		border-color: rgba(255, 255, 255, 0.4);
	}

	.cell.active {
		transform: scale(1.15);
		border-color: var(--accent);
		box-shadow: 0 0 24px var(--accent-glow);
		background: rgba(255, 255, 255, 0.1);
	}

	.avatar-img {
		width: 58px;
		height: 58px;
		object-fit: contain;
	}

	.initial {
		font-size: 34px;
		font-weight: 800;
		color: var(--accent);
	}

	.footer {
		display: flex;
		justify-content: center;
		margin-top: 10px;
	}

	@keyframes fade-in {
		from { opacity: 0; }
		to { opacity: 1; }
	}

	@keyframes scale-in {
		from { opacity: 0; transform: scale(0.96); }
		to { opacity: 1; transform: scale(1); }
	}
</style>
