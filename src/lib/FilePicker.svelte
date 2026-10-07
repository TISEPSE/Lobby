<script lang="ts">
	import { untrack } from 'svelte';
	import { fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import type { Action } from './gamepad';
	import type { Game } from './types';
	import Glyph from './Glyph.svelte';

	/**
	 * Explorateur de fichiers, façon Xbox, pour choisir l'exécutable d'un jeu
	 * quand la détection s'est trompée (options du jeu → « Changer
	 * l'exécutable »). Les disques, puis les dossiers et les exécutables
	 * seulement. Haut / bas parcourent (la liste glisse pour garder la sélection
	 * au centre), A ou droite ouvre un dossier, A sur un exécutable le choisit,
	 * B ou gauche remonte d'un dossier, X ferme. Chaque dossier entre en
	 * glissant du côté où l'on va : on sent qu'on descend ou qu'on remonte.
	 */
	let {
		open = false,
		game = null,
		onClose,
		onPick,
	}: {
		open?: boolean;
		game?: Game | null;
		onClose?: () => void;
		/** Le chemin de l'exécutable choisi. */
		onPick?: (path: string) => void;
	} = $props();

	interface Entry {
		name: string;
		path: string;
		kind: 'drive' | 'folder' | 'exe';
		size: number;
	}

	/** Dossier affiché ; vide pour la liste des disques. */
	let path = $state('');
	let parent = $state('');
	let entries = $state<Entry[]>([]);
	let index = $state(0);
	let loading = $state(false);
	let error = $state('');
	/** Sens du dernier déplacement : on descend dans un dossier, ou on remonte. */
	let direction = $state<1 | -1>(1);
	/** Sélection retrouvée en remontant : on revient sur le dossier d'où l'on sort. */
	const remembered = new Map<string, number>();

	const tauri = () => (window as any).__TAURI_INTERNALS__;

	async function invoke<T>(command: string, args?: Record<string, unknown>): Promise<T> {
		const { invoke } = await import('@tauri-apps/api/core');
		return invoke<T>(command, args);
	}

	/** Ouvre un dossier (ou la liste des disques avec ''), et place la sélection. */
	async function go(target: string, from: 1 | -1, select = '') {
		if (!tauri()) {
			// Capture (`?modal=files`) : un faux dossier, pour juger le rendu.
			path = target || 'D:/Jeux/MotoGP 24';
			parent = 'D:/Jeux';
			entries = [
				{ name: 'Binaries', path: 'D:/Jeux/MotoGP 24/Binaries', kind: 'folder', size: 0 },
				{ name: 'Content', path: 'D:/Jeux/MotoGP 24/Content', kind: 'folder', size: 0 },
				{ name: 'Engine', path: 'D:/Jeux/MotoGP 24/Engine', kind: 'folder', size: 0 },
				{ name: 'MotoGP24.exe', path: 'D:/Jeux/MotoGP 24/MotoGP24.exe', kind: 'exe', size: 287_000_000 },
				{ name: 'UnrealCEFSubProcess.exe', path: 'D:/Jeux/MotoGP 24/UnrealCEFSubProcess.exe', kind: 'exe', size: 1_400_000 },
			];
			index = 3;
			return;
		}
		remembered.set(path, index);
		loading = true;
		error = '';
		try {
			if (target === '') {
				entries = await invoke<Entry[]>('list_roots');
				parent = '';
			} else {
				const listing = await invoke<{ path: string; parent: string; entries: Entry[] }>('list_dir', {
					path: target,
				});
				entries = listing.entries;
				parent = listing.parent;
			}
			direction = from;
			path = target;
			const wanted = select ? entries.findIndex((e) => sameFile(e.path, select)) : -1;
			index = wanted >= 0 ? wanted : (remembered.get(target) ?? 0);
			index = Math.min(index, Math.max(0, entries.length - 1));
		} catch (e) {
			error = String(e);
		} finally {
			loading = false;
		}
	}

	const sameFile = (a: string, b: string) => normalize(a) === normalize(b);
	const normalize = (p: string) => p.replace(/\\/g, '/').replace(/\/+$/, '').toLowerCase();

	/** Dossier d'un fichier (`C:/Jeux/Moto/moto.exe` → `C:/Jeux/Moto`). */
	function dirname(file: string): string {
		const cut = Math.max(file.lastIndexOf('/'), file.lastIndexOf('\\'));
		return cut > 0 ? file.slice(0, cut) : '';
	}

	// À l'ouverture : on part du dossier de l'exécutable actuel. Un jeu Steam
	// pointe sur le client Steam : on part alors de ses jeux installés.
	$effect(() => {
		if (!open) return;
		remembered.clear();
		const current = game?.executable ?? '';
		let start = dirname(current);
		if (/steam\.exe$/i.test(current)) start = `${start}/steamapps/common`;
		// `go` lit `path` et `index` : sans `untrack`, l'effet les suivait et
		// chaque déplacement ramenait l'explorateur à son dossier de départ.
		untrack(() => {
			path = '';
			void go(start, 1, current).then(() => {
				if (error && start) void go('', 1);
			});
		});
	});

	/** Segments du chemin affiché, pour le fil d'Ariane. */
	const crumbs = $derived(path ? path.replace(/\\/g, '/').split('/').filter(Boolean) : []);

	function size(bytes: number): string {
		if (bytes >= 1e9) return `${(bytes / 1e9).toLocaleString('fr-FR', { maximumFractionDigits: 1 })} Go`;
		if (bytes >= 1e6) return `${Math.round(bytes / 1e6)} Mo`;
		return `${Math.max(1, Math.round(bytes / 1e3))} Ko`;
	}

	function up() {
		if (path === '') return onClose?.();
		const back = path;
		// Racine d'un disque : on remonte à la liste des disques.
		void go(parent, -1, back);
	}

	/** Touches de l'explorateur ; l'appelant les lui transmet tant qu'il est ouvert. */
	export function handleAction(action: Action) {
		if (loading) return;
		const entry = entries[index];
		if (action === 'up') index = Math.max(0, index - 1);
		else if (action === 'down') index = Math.min(entries.length - 1, index + 1);
		else if (action === 'cancel' || action === 'left') up();
		else if (action === 'options') onClose?.();
		else if ((action === 'accept' || action === 'right') && entry) {
			if (entry.kind === 'exe') {
				if (action === 'accept') onPick?.(entry.path);
			} else {
				void go(entry.path, 1);
			}
		}
	}

	/** Empreinte de la sélection, pour ne sonner que si elle bouge. */
	export function selectionKey(): string {
		return `${path}|${index}`;
	}
</script>

{#if open}
	<div class="veil">
		<section class="browser">
			<header>
				<div class="titles">
					<h2>Changer l'exécutable</h2>
					<p class="sub">{game?.title ?? ''}</p>
				</div>
				{#if game?.executable}
					<p class="current" title={game.executable}>
						Actuel : <span>{game.executable.split(/[\\/]/).pop()}</span>
					</p>
				{/if}
			</header>

			<!-- Fil d'Ariane : où l'on est, le dernier dossier en évidence. -->
			<nav class="crumbs">
				<span class="crumb" class:last={crumbs.length === 0}>
					<img src="/assets/icons/drive.svg" alt="" />Ce PC
				</span>
				{#each crumbs as crumb, i (i + crumb)}
					<span class="sep">›</span>
					<span class="crumb" class:last={i === crumbs.length - 1}>{crumb}</span>
				{/each}
			</nav>

			<div class="viewport">
				{#if error}
					<p class="state">{error}</p>
				{:else if !loading && entries.length === 0}
					<p class="state">Aucun dossier ni exécutable ici.</p>
				{:else}
					{#key path}
						<ul
							class="list"
							style="--index: {index}"
							in:fly={{ x: 80 * direction, duration: 260, easing: cubicOut, opacity: 0 }}
						>
							{#each entries as entry, i (entry.path)}
								<li
									class:selected={i === index}
									class:current={entry.kind === 'exe' && !!game?.executable && sameFile(entry.path, game.executable)}
								>
									<img class="icon {entry.kind}" src="/assets/icons/{entry.kind === 'exe' ? 'app' : entry.kind}.svg" alt="" />
									<span class="name">{entry.name}</span>
									{#if entry.kind === 'exe'}
										{#if game?.executable && sameFile(entry.path, game.executable)}
											<span class="badge">Actuel</span>
										{/if}
										<span class="meta">{size(entry.size)}</span>
									{:else}
										<span class="chevron">›</span>
									{/if}
								</li>
							{/each}
						</ul>
					{/key}
				{/if}
			</div>

			<footer class="hints">
				<span class="hint"><Glyph button="a" size="28px" />{entries[index]?.kind === 'exe' ? 'Choisir' : 'Ouvrir'}</span>
				<span class="hint"><Glyph button="b" size="28px" />{path ? 'Dossier parent' : 'Fermer'}</span>
				<span class="hint"><Glyph button="x" size="28px" />Fermer</span>
			</footer>
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
		animation: veil-in var(--fast) var(--ease) both;
	}

	@keyframes veil-in {
		from {
			opacity: 0;
		}
	}

	.browser {
		display: flex;
		flex-direction: column;
		gap: 18px;
		width: var(--files-width);
		padding: 30px 34px;
		border-radius: var(--radius-lg);
		background: var(--surface-strong);
		box-shadow: 0 30px 80px rgba(0, 0, 0, 0.7);
		animation: browser-in var(--normal) var(--ease) both;
	}

	@keyframes browser-in {
		from {
			opacity: 0;
			transform: translateY(18px) scale(0.98);
		}
	}

	header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: 24px;
	}

	h2 {
		margin: 0;
		font-size: 30px;
		font-weight: 700;
	}

	.sub,
	.current {
		margin: 4px 0 0;
		font-size: 17px;
		color: var(--text-dim);
	}

	.current span {
		color: var(--text);
		font-weight: 600;
	}

	.crumbs {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 8px;
		font-size: 17px;
		color: var(--text-dim);
	}

	.crumb {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		padding: 6px 12px;
		border-radius: 999px;
		background: var(--surface);
	}

	.crumb img {
		width: 18px;
		height: 18px;
		opacity: 0.8;
	}

	.crumb.last {
		background: var(--dock-active);
		color: var(--text);
		font-weight: 600;
	}

	.sep {
		opacity: 0.5;
	}

	/* La fenêtre montre `--files-rows` lignes ; la liste glisse dedans pour
	   garder la sélection au tiers supérieur, sans jamais sauter. */
	.viewport {
		position: relative;
		height: calc(var(--files-rows) * (var(--files-row) + var(--files-gap)));
		margin: calc(-1 * var(--hover-room));
		padding: var(--hover-room);
		overflow: hidden;
		mask-image: linear-gradient(to bottom, transparent 0, #000 6%, #000 90%, transparent 100%);
	}

	.list {
		display: flex;
		flex-direction: column;
		gap: var(--files-gap);
		margin: 0;
		padding: 0;
		list-style: none;
		transform: translateY(
			calc(-1 * max(0, var(--index) - 3) * (var(--files-row) + var(--files-gap)))
		);
		transition: transform var(--normal) var(--ease);
	}

	li {
		display: flex;
		align-items: center;
		gap: 18px;
		height: var(--files-row);
		padding: 0 22px;
		border-radius: var(--radius);
		background: var(--surface);
		font-size: 19px;
		transition:
			transform var(--fast) var(--ease),
			background var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	/* Sélection : contour d'accent, halo, et la ligne avance légèrement. */
	li.selected {
		background: rgba(255, 255, 255, 0.12);
		outline: 3px solid var(--accent);
		box-shadow: 0 0 28px 4px var(--accent-soft);
		transform: translateX(8px) scale(1.01);
	}

	.icon {
		flex: none;
		width: 28px;
		height: 28px;
		opacity: 0.75;
	}

	.icon.exe {
		opacity: 1;
	}

	li.selected .icon {
		opacity: 1;
	}

	.name {
		flex: 1;
		min-width: 0;
		overflow: hidden;
		white-space: nowrap;
		text-overflow: ellipsis;
	}

	li.current .name {
		color: var(--accent);
		font-weight: 600;
	}

	.badge {
		padding: 3px 10px;
		border-radius: 999px;
		background: var(--accent);
		color: var(--on-accent);
		font-size: 17px;
		font-weight: 700;
	}

	.meta,
	.chevron {
		color: var(--text-dim);
		font-variant-numeric: tabular-nums;
	}

	.chevron {
		font-size: 26px;
		line-height: 1;
	}

	.state {
		margin: 40px 0;
		font-size: 20px;
		color: var(--text-dim);
		text-align: center;
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
</style>
