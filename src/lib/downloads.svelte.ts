/**
 * Téléchargements et mises à jour en cours chez Steam.
 *
 * Steam n'expose rien localement, mais il tient ses manifestes à jour : Rust
 * les relit régulièrement et nous rend l'avancement réel. On n'interroge que
 * quand l'interface est visible, et jamais plus d'une fois par seconde.
 */
export interface DownloadStatus {
	appid: string;
	title: string;
	phase: 'download' | 'stage' | 'queued';
	bytes_done: number;
	bytes_total: number;
	percent: number;
}

export const downloads = $state<{ list: DownloadStatus[] }>({ list: [] });

let timer: ReturnType<typeof setInterval> | null = null;

/** Commence à suivre les téléchargements ; rend la fonction d'arrêt. */
export function watchDownloads(intervalMs = 2000): () => void {
	// Outil de développement : `?demo-download=1` affiche un téléchargement
	// factice, pour vérifier le rendu sans attendre une vraie mise à jour.
	if (new URLSearchParams(location.search).get('demo-download') === '1') {
		downloads.list = [
			{
				appid: '1145360',
				title: 'Hades',
				phase: 'download',
				bytes_done: 4_800_000_000,
				bytes_total: 11_900_000_000,
				percent: 40.3,
			},
		];
		return () => {};
	}

	const tauri = (window as any).__TAURI_INTERNALS__;
	if (!tauri) return () => {};

	const poll = async () => {
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			downloads.list = await invoke<DownloadStatus[]>('steam_downloads');
		} catch {
			// Steam absent ou manifeste en cours d'écriture : on garde l'état
			// précédent plutôt que de faire clignoter l'interface.
		}
	};

	void poll();
	timer = setInterval(poll, intervalMs);
	return () => {
		if (timer) clearInterval(timer);
		timer = null;
	};
}

/** Téléchargement concernant un jeu donné, s'il y en a un. */
export function downloadFor(appid: string | undefined): DownloadStatus | undefined {
	if (!appid) return undefined;
	return downloads.list.find((entry) => entry.appid === appid);
}

const PHASE_LABELS: Record<DownloadStatus['phase'], string> = {
	download: 'Téléchargement',
	stage: 'Installation',
	queued: 'En attente',
};

export function phaseLabel(status: DownloadStatus): string {
	return PHASE_LABELS[status.phase] ?? 'En cours';
}

/** « 1,4 Go / 12,0 Go », lisible d'un coup d'œil depuis le canapé. */
export function sizeText(status: DownloadStatus): string {
	if (status.bytes_total <= 0) return '';
	const giga = (value: number) => (value / 1024 ** 3).toFixed(1).replace('.', ',');
	return `${giga(status.bytes_done)} Go / ${giga(status.bytes_total)} Go`;
}
