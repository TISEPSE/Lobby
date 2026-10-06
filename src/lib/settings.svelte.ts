/**
 * Préférences utilisateur de la console : pseudo, avatar, disposition manette,
 * et dossiers de jeux suivis.
 * Persisté via Tauri (disque) et localStorage (secours).
 */
import type { UserSettings, VolumeKey } from './types';

export const VOLUME_KEYS: VolumeKey[] = ['volume_master', 'volume_menu', 'volume_alerts', 'volume_launch', 'volume_video'];

function clampVolume(value: number): number {
	return Math.max(0, Math.min(100, Math.round(value / 10) * 10));
}

/** Change un volume par pas de 10 %, entre 0 et 100. */
export function stepVolume(key: VolumeKey, delta: number) {
	const next = clampVolume(settings[key] + delta);
	if (next === settings[key]) return;
	settings[key] = next;
	saveSettings();
}

const STORAGE_KEY = 'interface-console.settings';

export const settings = $state<UserSettings>({
	profile_name: 'Joueur',
	avatar_path: '/assets/avatars/a11_face.svg',
	button_layout: 'ps5',
	game_folders: ['D:/Jeux'],
	sound_enabled: true,
	intro_enabled: true,
	steamgriddb_key: '',
	screensaver_minutes: 5,
	home_order: 'recent',
	library_filter: 'all',
	library_sort: 'title',
	volume_master: 100,
	volume_menu: 100,
	volume_alerts: 100,
	volume_launch: 100,
	volume_video: 100,
});

export async function initSettings() {
	// 1. Tente de charger depuis Tauri
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (tauri) {
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			const loaded = await invoke<UserSettings>('load_user_settings');
			if (loaded) {
				settings.profile_name = loaded.profile_name || 'Joueur';
				settings.avatar_path = loaded.avatar_path || '/assets/avatars/a11_face.svg';
				settings.button_layout = loaded.button_layout || 'ps5';
				settings.game_folders = loaded.game_folders ?? ['D:/Jeux'];
				settings.sound_enabled = loaded.sound_enabled ?? true;
				settings.intro_enabled = loaded.intro_enabled ?? true;
				settings.steamgriddb_key = loaded.steamgriddb_key ?? '';
				settings.screensaver_minutes = loaded.screensaver_minutes ?? 5;
				settings.home_order = loaded.home_order === 'title' ? 'title' : 'recent';
				settings.library_filter = loaded.library_filter || 'all';
				settings.library_sort = loaded.library_sort || 'title';
				for (const key of VOLUME_KEYS) settings[key] = clampVolume(loaded[key] ?? 100);
				return;
			}
		} catch (e) {
			console.warn('Impossible de charger les réglages via Tauri:', e);
		}
	}

	// 2. Secours localStorage
	try {
		const raw = localStorage.getItem(STORAGE_KEY);
		if (raw) {
			const parsed = JSON.parse(raw);
			settings.profile_name = parsed.profile_name ?? settings.profile_name;
			settings.avatar_path = parsed.avatar_path ?? settings.avatar_path;
			settings.button_layout = parsed.button_layout ?? settings.button_layout;
			settings.game_folders = parsed.game_folders ?? settings.game_folders;
		}
	} catch {}
}

export async function saveSettings() {
	try {
		localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
	} catch {}

	const tauri = (window as any).__TAURI_INTERNALS__;
	if (tauri) {
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			// **Tous** les champs, toujours : la commande Rust remplace le fichier
			// entier, et les champs absents y reprennent leur valeur par défaut.
			// N'en envoyer que quatre effaçait silencieusement la clé
			// SteamGridDB et la vidéo d'introduction au premier changement de
			// pseudo.
			await invoke('save_user_settings', { settings: { ...settings } });
		} catch (e) {
			console.warn('Impossible de sauvegarder les réglages via Tauri:', e);
		}
	}
}

export function setProfileName(name: string) {
	const clean = name.trim();
	if (!clean) return;
	settings.profile_name = clean;
	saveSettings();
}

export function setAvatar(path: string) {
	if (path === settings.avatar_path) return;
	settings.avatar_path = path;
	saveSettings();
}

export function setButtonLayout(layout: string) {
	if (layout === settings.button_layout) return;
	settings.button_layout = layout;
	saveSettings();
}

export function setIntroEnabled(enabled: boolean) {
	settings.intro_enabled = enabled;
	saveSettings();
}

export function setScreensaverMinutes(minutes: number) {
	settings.screensaver_minutes = minutes;
	saveSettings();
}

/** Filtre et tri de la bibliothèque : gardés pour la prochaine session. */
export function setLibraryView(filter: string, sort: string) {
	if (settings.library_filter === filter && settings.library_sort === sort) return;
	settings.library_filter = filter;
	settings.library_sort = sort;
	saveSettings();
}

export function setHomeOrder(order: 'recent' | 'title') {
	settings.home_order = order;
	saveSettings();
}

export function setSoundEnabled(enabled: boolean) {
	settings.sound_enabled = enabled;
	saveSettings();
}

/**
 * Enregistre la clé SteamGridDB. Elle part dans le fichier de réglages local
 * (dossier de données de l'application) et nulle part ailleurs.
 */
export function setSteamGridKey(key: string) {
	settings.steamgriddb_key = key.trim();
	saveSettings();
}

export function addGameFolder(path: string) {
	const clean = path.trim().replace(/\\/g, '/').replace(/\/$/, '');
	if (!clean || settings.game_folders.includes(clean)) return;
	settings.game_folders = [...settings.game_folders, clean];
	saveSettings();
}

export function removeGameFolder(path: string) {
	settings.game_folders = settings.game_folders.filter((f) => f !== path);
	saveSettings();
}
