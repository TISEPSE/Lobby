/**
 * Actions confiées à Steam : installer, mettre à jour, vérifier, désinstaller.
 * On ne touche pas aux fichiers nous-mêmes — Steam sait le faire, et lui seul
 * connaît l'état réel d'une installation.
 */
import type { Outcome } from './types';

async function openSteam(url: string, done: string): Promise<Outcome> {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return { ok: true, message: "Hors application : Steam n'est pas joignable ici." };
	const { invoke } = await import('@tauri-apps/api/core');
	try {
		await invoke('open_url', { url });
		return { ok: true, message: done };
	} catch (error) {
		return { ok: false, message: `Steam n'a pas répondu : ${error}` };
	}
}

/** Installe un jeu possédé mais pas installé : Steam ouvre sa fenêtre d'installation. */
export function installGame(appid: string) {
	return openSteam(`steam://install/${appid}`, 'Steam prend le relais pour l\'installation.');
}

/** Installe un jeu Epic possédé : le launcher Epic ouvre sa fenêtre d'installation. */
export function installEpicGame(appName: string) {
	return openSteam(
		`com.epicgames.launcher://apps/${appName}?action=install`,
		'Le launcher Epic prend le relais pour l\'installation.'
	);
}

/** Lance l'installation ou la mise à jour du jeu. */
export function updateGame(appid: string) {
	return openSteam(`steam://install/${appid}`, 'Steam prend le relais pour la mise à jour.');
}

/** Vérifie l'intégrité des fichiers installés. */
export function verifyGame(appid: string) {
	return openSteam(`steam://validate/${appid}`, 'Vérification des fichiers lancée dans Steam.');
}

/** Demande la désinstallation ; Steam affiche sa propre confirmation. */
export function uninstallGame(appid: string) {
	return openSteam(`steam://uninstall/${appid}`, 'Désinstallation demandée à Steam.');
}
