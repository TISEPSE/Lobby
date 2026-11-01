<script lang="ts">
	import { untrack } from 'svelte';
	import { fly } from 'svelte/transition';
	import { cubicOut } from 'svelte/easing';
	import type { Action } from './gamepad';
	import type { Game } from './types';
	import Glyph from './Glyph.svelte';
	import { imageUrl, releaseImage } from './images';

	/**
	 * Explorateur de fichiers, façon Xbox. Il sert à choisir l'exécutable d'un
	 * jeu quand la détection s'est trompée (options du jeu → « Changer
	 * l'exécutable »), ou un dossier de jeux (Réglages → Jeux). Les disques, puis
	 * les dossiers et les exécutables seulement. Haut / bas parcourent (la liste
	 * glisse pour garder la sélection au centre), A ou droite ouvre un dossier,
	 * A sur un exécutable le choisit, B ou gauche remonte d'un dossier, X ferme.
	 * Chaque dossier entre en glissant du côté où l'on va : on sent qu'on descend
	 * ou qu'on remonte.
	 *
	 * Pour choisir un dossier, on l'ouvre : la première ligne, « Choisir ce
	 * dossier », le retient. La sélection arrive sur le premier sous-dossier :
	 * deux appuis sur A descendent, ils ne choisissent pas par accident.
	 *
	 * Pour une photo de profil, seules les images sont listées, et celle qui est
	 * sélectionnée s'affiche à côté de la liste : un nom de fichier ne dit pas
	 * quelle photo c'est.
	 */
	let {
		open = false,
		game = null,
		mode = 'exe',
		startFolder = '',
		onClose,
		onPick,
	}: {
		open?: boolean;
		game?: Game | null;
		/** Ce qu'on choisit : l'exécutable d'un jeu, un dossier, ou une photo. */
		mode?: 'exe' | 'folder' | 'image';
		/** Dossier de départ pour une photo. */
		startFolder?: string;
		onClose?: () => void;
		/** Le chemin du fichier ou du dossier choisi. */
		onPick?: (path: string) => void;
	} = $props();

	interface Entry {
		name: string;
		path: string;
		kind: 'drive' | 'folder' | 'exe' | 'image' | 'pick';
		size: number;
	}

	/** Délai avant d'ouvrir l'aperçu : parcourir la liste ne charge pas chaque photo. */
	const PREVIEW_DELAY = 160;

	const ICONS: Record<Entry['kind'], string> = {
		drive: 'drive',
		folder: 'folder',
		exe: 'app',
		image: 'image',
		pick: 'check',
	};
	const ACCEPT: Record<Entry['kind'], string> = {
		drive: 'Ouvrir',
		folder: 'Ouvrir',
		exe: 'Choisir',
		image: 'Choisir cette photo',
		pick: 'Choisir ce dossier',
	};
	const TITLES = { exe: "Changer l'exécutable", folder: 'Ajouter un dossier de jeux', image: 'Importer une photo' };

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

	/** Ce que montre un dossier : pour en choisir un, pas d'exécutables, et la ligne qui le retient. */
	function visible(target: string, listed: Entry[]): Entry[] {
		if (mode !== 'folder') return listed;
		const folders = listed.filter((e) => e.kind !== 'exe');
		if (!target) return folders;
		return [{ name: 'Choisir ce dossier', path: target, kind: 'pick', size: 0 }, ...folders];
	}

	/** Ouvre un dossier (ou la liste des disques avec ''), et place la sélection. */
	async function go(target: string, from: 1 | -1, select = '') {
		if (!tauri()) {
			// Capture (`?modal=files`, `?modal=folders`) : un faux dossier, pour juger le rendu.
			path = target || 'D:/Jeux/MotoGP 24';
			parent = 'D:/Jeux';
			if (mode === 'image') {
				entries = [
					{ name: 'Vacances', path: 'D:/Images/Vacances', kind: 'folder', size: 0 },
					{ name: 'logo.png', path: '/assets/logo.png', kind: 'image', size: 120_000 },
				];
				index = 1;
				return;
			}
			entries = visible(path, [
				{ name: 'Binaries', path: 'D:/Jeux/MotoGP 24/Binaries', kind: 'folder', size: 0 },
				{ name: 'Content', path: 'D:/Jeux/MotoGP 24/Content', kind: 'folder', size: 0 },
				{ name: 'Engine', path: 'D:/Jeux/MotoGP 24/Engine', kind: 'folder', size: 0 },
				{ name: 'MotoGP24.exe', path: 'D:/Jeux/MotoGP 24/MotoGP24.exe', kind: 'exe', size: 287_000_000 },
				{ name: 'UnrealCEFSubProcess.exe', path: 'D:/Jeux/MotoGP 24/UnrealCEFSubProcess.exe', kind: 'exe', size: 1_400_000 },
			]);
			index = mode === 'exe' ? 3 : 1;
			return;
		}
		remembered.set(path, index);
		loading = true;
		error = '';
		try {
			if (target === '') {
				entries = visible('', await invoke<Entry[]>('list_roots'));
				parent = '';
			} else {
				const listing = await invoke<{ path: string; parent: string; entries: Entry[] }>('list_dir', {
					path: target,
					images: mode === 'image',
				});
				entries = visible(target, listing.entries);
				parent = listing.parent;
			}
			direction = from;
			path = target;
			const wanted = select ? entries.findIndex((e) => sameFile(e.path, select)) : -1;
			const first = entries[0]?.kind === 'pick' ? 1 : 0;
			index = wanted >= 0 ? wanted : (remembered.get(target) ?? first);
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
		const current = mode === 'exe' ? (game?.executable ?? '') : '';
		let start = mode === 'image' ? startFolder : dirname(current);
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

	/** Aperçu de la photo sélectionnée. */
	let preview = $state('');
	/** Photo voulue : une réponse arrivée après un autre déplacement est ignorée. */
	let previewing = '';

	function showPreview(url: string) {
		releaseImage(preview);
		preview = url;
	}

	$effect(() => {
		const wanted = open && mode === 'image' && entries[index]?.kind === 'image' ? entries[index].path : '';
		previewing = wanted;
		if (!wanted) {
			untrack(() => showPreview(''));
			return;
		}
		const timer = setTimeout(() => {
			imageUrl(wanted)
				.then((url) => {
					if (previewing === wanted) showPreview(url);
					else releaseImage(url);
				})
				.catch(() => {
					if (previewing === wanted) showPreview('');
				});
		}, PREVIEW_DELAY);
		return () => clearTimeout(timer);
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
		// Dossier illisible (droits) : B ramène à celui qu'on regardait, sans remonter d'un cran.
		if (error && (action === 'cancel' || action === 'left')) {
			error = '';
			return;
		}
		const entry = entries[index];
		if (action === 'up') index = Math.max(0, index - 1);
		else if (action === 'down') index = Math.min(entries.length - 1, index + 1);
		else if (action === 'cancel' || action === 'left') up();
		else if (action === 'options') onClose?.();
		else if ((action === 'accept' || action === 'right') && entry) {
			if (entry.kind === 'exe' || entry.kind === 'pick' || entry.kind === 'image') {
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
					<h2>{TITLES[mode]}</h2>
					<p class="sub">
						{#if mode === 'folder'}
							Ouvre le dossier qui contient tes jeux, puis choisis-le.
						{:else if mode === 'image'}
							Choisis une image de ce PC : tu la recadreras ensuite.
						{:else}
							{game?.title ?? ''}
						{/if}
					</p>
				</div>
				{#if mode === 'exe' && game?.executable}
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

			<div class="content">
			<div class="viewport">
				{#if error}
					<p class="state">{error}</p>
				{:else if !loading && entries.length === 0}
					<p class="state">{mode === 'image' ? 'Aucun dossier ni image ici.' : 'Aucun dossier ni exécutable ici.'}</p>
				{:else}
					{#key path}
						<ul
							class="list"
							style="--index: {index}"
							in:fly={{ x: 80 * direction, duration: 260, easing: cubicOut, opacity: 0 }}
						>
							{#each entries as entry, i (entry.path)}
								<!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
								<li
									class:selected={i === index}
									class:current={entry.kind === 'exe' && !!game?.executable && sameFile(entry.path, game.executable)}
									class:pick={entry.kind === 'pick'}
									onclick={() => {
										index = i;
										handleAction('accept');
									}}
								>
									<img class="icon {entry.kind}" src="/assets/icons/{ICONS[entry.kind]}.svg" alt="" />
									<span class="name">{entry.name}</span>
									{#if entry.kind === 'exe' || entry.kind === 'image'}
										{#if entry.kind === 'exe' && game?.executable && sameFile(entry.path, game.executable)}
											<span class="badge">Actuel</span>
										{/if}
										<span class="meta">{size(entry.size)}</span>
									{:else if entry.kind === 'pick'}
										<span class="meta">{crumbs.at(-1)}</span>
									{:else}
										<span class="chevron">›</span>
									{/if}
								</li>
							{/each}
						</ul>
					{/key}
				{/if}
			</div>
			{#if mode === 'image'}
				<aside class="preview">
					{#if preview}
						<img src={preview} alt="" />
					{:else}
						<span>Aperçu</span>
					{/if}
				</aside>
			{/if}
			</div>

			<footer class="hints">
				<span class="hint"><Glyph button="a" size="28px" />{ACCEPT[entries[index]?.kind ?? 'folder']}</span>
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
		background: var(--files-veil);
		backdrop-filter: var(--files-backdrop);
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
		border: 1px solid var(--xbox-line);
		border-radius: var(--radius-lg);
		background: var(--files-panel);
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
		background: var(--files-row-bg);
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

	.content {
		display: flex;
		gap: calc(var(--hover-room) * 2);
		align-items: stretch;
	}

	.preview {
		flex: none;
		display: grid;
		place-items: center;
		width: var(--files-preview);
		overflow: hidden;
		border-radius: var(--radius);
		background: var(--files-row-bg);
		color: var(--text-dim);
		font-size: 17px;
	}

	.preview img {
		width: 100%;
		height: 100%;
		object-fit: contain;
	}

	/* La fenêtre montre `--files-rows` lignes ; la liste glisse dedans pour
	   garder la sélection au tiers supérieur, sans jamais sauter. */
	.viewport {
		position: relative;
		flex: 1;
		min-width: 0;
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
		background: var(--files-row-bg);
		font-size: 19px;
		transition:
			transform var(--fast) var(--ease),
			background var(--fast) var(--ease),
			box-shadow var(--fast) var(--ease);
	}

	/* Sélection : contour d'accent, halo, et la ligne avance légèrement. */
	li.selected {
		background: var(--files-row-focus);
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

	li.current .name,
	li.pick .name {
		color: var(--accent);
		font-weight: 600;
	}

	.icon.pick {
		opacity: 1;
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
