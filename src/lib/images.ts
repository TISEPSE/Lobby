/**
 * Photos importées. Le webview ne lit que le dossier de données : une image
 * choisie ailleurs sur le PC arrive par Rust (`read_image`), et la photo recadrée
 * y retourne (`save_avatar`). Hors application (captures), le chemin est servi tel
 * quel et rien n'est écrit.
 */
const inApp = () => !!(window as any).__TAURI_INTERNALS__;

/** Adresse affichable d'une image du PC. À libérer par `releaseImage`. */
export async function imageUrl(path: string): Promise<string> {
	if (!inApp()) return path;
	const { invoke } = await import('@tauri-apps/api/core');
	const bytes = await invoke<ArrayBuffer>('read_image', { path });
	return URL.createObjectURL(new Blob([bytes]));
}

export function releaseImage(url: string) {
	if (url.startsWith('blob:')) URL.revokeObjectURL(url);
}

/** Enregistre la photo recadrée et rend l'adresse à garder dans les réglages. */
export async function saveAvatarImage(canvas: HTMLCanvasElement): Promise<string> {
	if (!inApp()) return canvas.toDataURL('image/png');
	const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'));
	if (!blob) throw new Error('Photo impossible à préparer.');
	const { invoke, convertFileSrc } = await import('@tauri-apps/api/core');
	const path = await invoke<string>('save_avatar', new Uint8Array(await blob.arrayBuffer()));
	return convertFileSrc(path);
}
