/**
 * Générateur d'affiches et de bannières procédurales haut de gamme pour jeux PC.
 * Garantit qu'aucun jeu n'apparaît jamais sans jaquette ou avec un carré vide.
 */

interface Palette {
	primary: string;
	secondary: string;
	accent: string;
	mesh: string;
}

const PALETTES: Palette[] = [
	{ primary: '#0f172a', secondary: '#1e293b', accent: '#38bdf8', mesh: '#0284c7' }, // Cyber Blue
	{ primary: '#18181b', secondary: '#27272a', accent: '#22d366', mesh: '#16a34a' }, // Console Green
	{ primary: '#1c1917', secondary: '#292524', accent: '#f59e0b', mesh: '#d97706' }, // Warm Amber
	{ primary: '#1a102f', secondary: '#2e1065', accent: '#c084fc', mesh: '#9333ea' }, // Royal Violet
	{ primary: '#200e18', secondary: '#4c0519', accent: '#fb7185', mesh: '#e11d48' }, // Crimson Blood
	{ primary: '#042f2e', secondary: '#115e59', accent: '#2dd4bf', mesh: '#0d9488' }, // Deep Teal
	{ primary: '#1e1b4b', secondary: '#312e81', accent: '#818cf8', mesh: '#4f46e5' }, // Indigo Night
	{ primary: '#1f130b', secondary: '#451a03', accent: '#fb923c', mesh: '#ea580c' }, // Sunset Orange
];

function hash(str: string): number {
	let h = 0;
	for (let i = 0; i < str.length; i++) {
		h = (h << 5) - h + str.charCodeAt(i);
		h |= 0;
	}
	return Math.abs(h);
}

function getInitials(title: string): string {
	const cleaned = title
		.replace(/marvel'?s\s+/gi, '')
		.replace(/[^a-zA-Z0-9\s]/g, ' ')
		.trim();
	const words = cleaned.split(/\s+/).filter(Boolean);
	if (words.length === 0) return 'GP';
	if (words.length === 1) return words[0].slice(0, 2).toUpperCase();
	return (words[0][0] + words[1][0]).toUpperCase();
}

function escapeXml(unsafe: string): string {
	return unsafe
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;')
		.replace(/'/g, '&apos;');
}

/**
 * Crée une jaquette verticale 600x900 au format SVG Data-URI.
 * Zéro requête réseau, 100% hors ligne et instantané.
 */
export function generateProceduralCover(title: string, source = 'pc'): string {
	const h = hash(title);
	const palette = PALETTES[h % PALETTES.length];
	const initials = getInitials(title);
	const safeTitle = escapeXml(title);
	const badgeText = (source === 'steam' ? 'STEAM' : source === 'epic' ? 'EPIC GAMES' : 'PC GAME').toUpperCase();

	const svg = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 900" width="600" height="900">
	<defs>
		<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
			<stop offset="0%" stop-color="${palette.secondary}" />
			<stop offset="50%" stop-color="${palette.primary}" />
			<stop offset="100%" stop-color="#05070a" />
		</linearGradient>
		<radialGradient id="glow" cx="50%" cy="40%" r="55%">
			<stop offset="0%" stop-color="${palette.accent}" stop-opacity="0.28" />
			<stop offset="100%" stop-color="${palette.accent}" stop-opacity="0" />
		</radialGradient>
		<linearGradient id="scrim" x1="0%" y1="0%" x2="0%" y2="100%">
			<stop offset="0%" stop-color="#000000" stop-opacity="0" />
			<stop offset="60%" stop-color="#000000" stop-opacity="0.6" />
			<stop offset="100%" stop-color="#030508" stop-opacity="0.96" />
		</linearGradient>
		<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
			<feDropShadow dx="0" dy="8" stdDeviation="12" flood-color="#000000" flood-opacity="0.75" />
		</filter>
	</defs>

	<!-- Fond dégradé sombre et riche -->
	<rect width="600" height="900" fill="url(#bg)" />

	<!-- Motifs géométriques & lueur -->
	<circle cx="300" cy="380" r="260" fill="url(#glow)" />
	<path d="M-50 150 L650 350 M-50 450 L650 650 M-50 750 L650 950" stroke="${palette.accent}" stroke-opacity="0.06" stroke-width="1.5" />
	<circle cx="300" cy="380" r="140" fill="none" stroke="${palette.accent}" stroke-opacity="0.16" stroke-width="2" stroke-dasharray="8 6" />

	<!-- Badge Plateforme en haut à droite -->
	<g transform="translate(420, 36)">
		<rect width="144" height="34" rx="17" fill="rgba(0, 0, 0, 0.45)" stroke="rgba(255, 255, 255, 0.16)" stroke-width="1" />
		<text x="72" y="22" fill="#ffffff" opacity="0.85" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif" font-size="12" font-weight="700" text-anchor="middle" letter-spacing="1">${badgeText}</text>
	</g>

	<!-- Emblème central avec initiales -->
	<g transform="translate(300, 380)" filter="url(#shadow)">
		<rect x="-70" y="-70" width="140" height="140" rx="32" fill="rgba(255, 255, 255, 0.05)" stroke="${palette.accent}" stroke-width="2.5" />
		<text x="0" y="20" fill="#ffffff" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif" font-size="52" font-weight="900" text-anchor="middle" letter-spacing="2">${initials}</text>
	</g>

	<!-- Voile inférieur avec titre du jeu -->
	<rect y="480" width="600" height="420" fill="url(#scrim)" />

	<!-- Barre décorative d'accent -->
	<rect x="40" y="740" width="48" height="4" rx="2" fill="${palette.accent}" />

	<!-- Titre du jeu centré et lisible -->
	<text x="40" y="785" fill="#ffffff" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif" font-size="32" font-weight="800" filter="url(#shadow)">
		${safeTitle.length > 22 ? safeTitle.slice(0, 20) + '…' : safeTitle}
	</text>
	<text x="40" y="825" fill="rgba(255, 255, 255, 0.65)" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif" font-size="15" font-weight="600" letter-spacing="0.5">
		INSTALLÉ SUR CET APPAREIL
	</text>
</svg>
`.trim();

	return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
}

/**
 * Crée une bannière horizontale 1920x620 au format SVG Data-URI.
 */
export function generateProceduralHero(title: string, source = 'pc'): string {
	const h = hash(title);
	const palette = PALETTES[h % PALETTES.length];
	const initials = getInitials(title);
	const safeTitle = escapeXml(title);

	const svg = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1920 620" width="1920" height="620">
	<defs>
		<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="50%">
			<stop offset="0%" stop-color="${palette.secondary}" />
			<stop offset="60%" stop-color="${palette.primary}" />
			<stop offset="100%" stop-color="#030508" />
		</linearGradient>
		<radialGradient id="glow" cx="30%" cy="50%" r="50%">
			<stop offset="0%" stop-color="${palette.accent}" stop-opacity="0.3" />
			<stop offset="100%" stop-color="${palette.accent}" stop-opacity="0" />
		</radialGradient>
	</defs>

	<rect width="1920" height="620" fill="url(#bg)" />
	<circle cx="500" cy="310" r="400" fill="url(#glow)" />

	<!-- Emblème stylisé discret -->
	<g transform="translate(1500, 310)" opacity="0.12">
		<rect x="-180" y="-180" width="360" height="360" rx="60" fill="none" stroke="${palette.accent}" stroke-width="6" />
		<text x="0" y="50" fill="${palette.accent}" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif" font-size="140" font-weight="900" text-anchor="middle">${initials}</text>
	</g>

	<!-- Titre et sous-titre de la bannière -->
	<g transform="translate(100, 350)">
		<rect x="0" y="-80" width="60" height="6" rx="3" fill="${palette.accent}" />
		<text x="0" y="-20" fill="#ffffff" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif" font-size="54" font-weight="900">${safeTitle}</text>
	</g>
</svg>
`.trim();

	return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`;
}

/**
 * Retourne la jaquette officielle ou le visuel procédural garanti.
 */
export function getGameCover(game: { title: string; cover?: string; source?: string }): string {
	if (game.cover && game.cover.trim().length > 0) {
		return game.cover;
	}
	return generateProceduralCover(game.title, game.source);
}

/**
 * Retourne le visuel large d'arrière-plan garanti.
 */
export function getGameHero(game: { title: string; hero?: string; cover?: string; source?: string }): string {
	if (game.hero && game.hero.trim().length > 0) {
		return game.hero;
	}
	if (game.cover && game.cover.trim().length > 0) {
		return game.cover;
	}
	return generateProceduralHero(game.title, game.source);
}
