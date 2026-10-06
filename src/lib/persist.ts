/**
 * Données de l'interface gardées sur le disque (commande Rust `save_store`),
 * avec le stockage du navigateur en secours.
 *
 * Le stockage du webview dépend de l'origine de la page : `tauri dev` sert
 * `localhost:5177`, l'exécutable compilé une autre adresse. Tout ce qui ne
 * vivait que dans `localStorage` (statistiques, journal, choix d'affiches)
 * semblait donc perdu dans l'exécutable. Le disque est la référence ; le
 * navigateur ne sert plus qu'à migrer les anciennes données et à faire
 * tourner le front hors application.
 */

const tauri = () => Boolean((window as any).__TAURI_INTERNALS__);

/** Écrit une valeur sur le disque et dans le navigateur. */
export function persist(name: string, key: string, value: unknown) {
	const text = JSON.stringify(value);
	try {
		localStorage.setItem(key, text);
	} catch {
		/* navigateur sans stockage : le disque suffit */
	}
	if (!tauri()) return;
	void import('@tauri-apps/api/core')
		.then(({ invoke }) => invoke('save_store', { name, data: text }))
		.catch((e) => console.warn(`Sauvegarde impossible (${name}) :`, e));
}

/**
 * Relit une valeur : le disque d'abord ; à défaut, le navigateur — et elle est
 * alors recopiée sur le disque (migration des anciennes données).
 */
export async function restore<T>(name: string, key: string): Promise<T | null> {
	if (tauri()) {
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			const text = await invoke<string | null>('load_store', { name });
			if (text) return JSON.parse(text) as T;
		} catch (e) {
			console.warn(`Lecture impossible (${name}) :`, e);
		}
	}
	try {
		const raw = localStorage.getItem(key);
		if (!raw) return null;
		const value = JSON.parse(raw) as T;
		if (tauri()) persist(name, key, value);
		return value;
	} catch {
		return null;
	}
}
