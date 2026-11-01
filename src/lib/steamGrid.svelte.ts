/**
 * Clé SteamGridDB : son état, sa vérification et sa récupération sur le compte.
 * La clé vit dans les réglages (`steamgriddb_key`), saisie ou récupérée par
 * l'utilisateur : jamais dans le dépôt, jamais réaffichée en entier.
 */
import { settings } from './settings.svelte.js';

type Status = 'unknown' | 'testing' | 'ok' | 'bad' | 'offline';

export const steamGrid = $state<{ status: Status; pending: boolean }>({ status: 'unknown', pending: false });

/**
 * Essaie la clé auprès de SteamGridDB, sans l'afficher ni l'envoyer ailleurs : une
 * clé mal recopiée resterait sinon silencieuse jusqu'au prochain jeu sans jaquette.
 */
export async function checkSteamGridKey(key: string): Promise<string> {
	if (!key) {
		steamGrid.status = 'unknown';
		return 'empty';
	}
	if (!(window as any).__TAURI_INTERNALS__) {
		steamGrid.status = 'unknown';
		return 'offline';
	}
	steamGrid.status = 'testing';
	try {
		const { invoke } = await import('@tauri-apps/api/core');
		const result = await invoke<string>('test_steamgriddb_key', { key });
		steamGrid.status = result === 'ok' ? 'ok' : result === 'unauthorized' ? 'bad' : 'offline';
		return result;
	} catch {
		steamGrid.status = 'offline';
		return 'offline';
	}
}

/** L'état affiché : quatre caractères de la clé suffisent à la reconnaître. */
export function steamGridStatus(): string {
	if (steamGrid.pending) return 'Connexion…';
	const key = settings.steamgriddb_key;
	if (!key) return 'Non connecté · pour les jaquettes qui manquent';
	const masked = `Clé ····${key.slice(-4)}`;
	if (steamGrid.status === 'testing') return `${masked} · vérification…`;
	if (steamGrid.status === 'ok') return `${masked} · vérifiée`;
	if (steamGrid.status === 'bad') return `${masked} · refusée`;
	if (steamGrid.status === 'offline') return `${masked} · non vérifiée`;
	return masked;
}

/** Ouvre la page de la clé ; le résultat arrive par `initSteamGrid`. */
export async function loginSteamGrid() {
	if (!(window as any).__TAURI_INTERNALS__) return;
	const { invoke } = await import('@tauri-apps/api/core');
	steamGrid.pending = true;
	try {
		await invoke('steamgriddb_login');
	} catch (e) {
		steamGrid.pending = false;
		throw e;
	}
}

/** Suit la fenêtre de connexion. `onKey` reçoit la clé trouvée, `onFailure` le refus. */
export async function initSteamGrid(onKey: (key: string) => void, onFailure: (message: string) => void) {
	if (!(window as any).__TAURI_INTERNALS__) return;
	if (settings.steamgriddb_key) void checkSteamGridKey(settings.steamgriddb_key);
	const { listen } = await import('@tauri-apps/api/event');
	await listen<{ ok: boolean; message: string; key: string }>('steamgriddb-key', (event) => {
		steamGrid.pending = false;
		if (event.payload.ok) onKey(event.payload.key);
		else onFailure(event.payload.message);
	});
}
