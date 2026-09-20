/** Repli d'image partagé par l'accueil et la bibliothèque. */

/**
 * Toutes les jaquettes Steam n'existent pas au format vertical : on retombe sur
 * la bannière horizontale plutôt que d'afficher une case vide.
 */
export function coverFallback(event: Event, appid: string) {
	const img = event.currentTarget as HTMLImageElement;
	const header = `https://cdn.cloudflare.steamstatic.com/steam/apps/${appid}/header.jpg`;
	if (!img.src.endsWith('header.jpg')) img.src = header;
}
