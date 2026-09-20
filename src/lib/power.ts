/**
 * Alimentation de la machine. Tout passe par la couche Rust : le web n'a pas le
 * droit d'éteindre un PC, et c'est tant mieux — ça reste une action explicite,
 * confirmée, et refusée proprement hors application.
 */
export type PowerAction = 'shutdown' | 'reboot' | 'quit';

/** Entrées du menu, dans l'ordre d'affichage. */
export const POWER_ENTRIES: { action: PowerAction; label: string; confirm: boolean }[] = [
	{ action: 'shutdown', label: 'Éteindre le PC', confirm: true },
	{ action: 'reboot', label: 'Redémarrer', confirm: true },
	{ action: 'quit', label: "Quitter l'interface", confirm: true },
];

export async function runPower(action: PowerAction): Promise<string> {
	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return "Hors application : l'alimentation n'est pas disponible ici.";

	const { invoke } = await import('@tauri-apps/api/core');
	try {
		await invoke('power_action', { action });
		return action === 'quit' ? 'Fermeture…' : 'Commande envoyée.';
	} catch (error) {
		return String(error);
	}
}
