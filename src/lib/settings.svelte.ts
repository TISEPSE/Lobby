/**
 * Préférences utilisateur de la console : pseudo, avatar, disposition manette,
 * et dossiers de jeux suivis.
 * Persisté via Tauri (disque) et localStorage (secours).
 */
import type { UserSettings } from './types';

const STORAGE_KEY = 'interface-console.settings';

export const settings = $state<UserSettings>({
	profile_name: 'Joueur',
	avatar_path: '/assets/avatars/a11_face.svg',
	button_layout: 'ps5',
	game_folders: ['D:/Jeux'],
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
			await invoke('save_user_settings', {
				settings: {
					profile_name: settings.profile_name,
					avatar_path: settings.avatar_path,
					button_layout: settings.button_layout,
					game_folders: settings.game_folders,
				},
			});
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
