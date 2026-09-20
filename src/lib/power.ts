/**
 * Alimentation de la machine. Tout passe par la couche Rust : le web n'a pas le
 * droit d'éteindre un PC, et c'est tant mieux — ça reste une action explicite,
 * confirmée, et refusée proprement hors application.
 */
export type PowerAction = 'shutdown' | 'reboot' | 'quit';

/** Entrées du menu, dans l'ordre d'affichage. */
export interface PowerEntry {
	action: PowerAction;
	label: string;
	/** Icône de `public/assets/icons/`. */
	icon: string;
	/** Une ligne sous le libellé : ce que l'action fait vraiment. */
	hint: string;
	/** Phrase affichée au moment de confirmer. */
	confirmHint: string;
	confirm: boolean;
}

export const POWER_ENTRIES: PowerEntry[] = [
	{
		action: 'shutdown',
		label: 'Éteindre',
		icon: 'power',
		hint: 'Arrête complètement la machine.',
		confirmHint: 'Les jeux en cours seront fermés.',
		confirm: true,
	},
	{
		action: 'reboot',
		label: 'Redémarrer',
		icon: 'restart',
		hint: 'Relance la machine et revient ici.',
		confirmHint: 'Les jeux en cours seront fermés.',
		confirm: true,
	},
	{
		action: 'quit',
		label: "Quitter l'interface",
		icon: 'exit',
		hint: 'Revient au bureau sans éteindre.',
		confirmHint: "L'interface se ferme, la machine reste allumée.",
		confirm: true,
	},
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
