/**
 * Journal des notifications : les derniers messages du bandeau (`notify`),
 * relisibles dans Réglages → Système. Un avertissement qui passait trop vite
 * (connexion Epic, par exemple) se retrouve ici.
 */
export interface Notice {
	at: number;
	message: string;
	ok: boolean;
}

/** Messages gardés, les plus récents en tête. */
const KEEP = 30;

export const notices = $state<Notice[]>([]);

export function remember(message: string, ok: boolean) {
	notices.unshift({ at: Date.now(), message, ok });
	if (notices.length > KEEP) notices.length = KEEP;
}
