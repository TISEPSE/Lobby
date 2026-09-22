/**
 * Disposition du clavier de recherche. Elle vit à part du composant : l'écran
 * l'affiche, la navigation s'en sert pour savoir quelle touche est sous le
 * curseur — les deux doivent lire exactement la même grille.
 *
 * Les rangées n'ont pas toutes la même longueur (la dernière porte des touches
 * larges) : la sélection se repère donc en **rangée + colonne**, jamais par un
 * index à plat.
 */

export interface SearchKey {
	/** Caractère inséré. Vide pour une touche d'action. */
	value: string;
	/** Ce que fait la touche quand elle n'écrit pas de caractère. */
	action?: 'space' | 'backspace' | 'clear' | 'done';
	/** Icône de `public/assets/icons/` : une flèche vaut mieux que le mot « Effacer ». */
	icon?: string;
	/** Texte affiché à côté de l'icône, pour les touches larges. */
	label?: string;
	/** Largeur en colonnes. */
	span?: number;
}

function letters(row: string): SearchKey[] {
	return [...row].map((value) => ({ value }));
}

export const SEARCH_ROWS: SearchKey[][] = [
	letters('ABCDEFGHIJ'),
	letters('KLMNOPQRST'),
	letters('UVWXYZ-\':!'),
	letters('1234567890'),
	[
		{ value: '', action: 'space', icon: 'space', label: 'Espace', span: 5 },
		{ value: '', action: 'backspace', icon: 'backspace', label: 'Effacer', span: 3 },
		{ value: '', action: 'clear', icon: 'trash', label: 'Tout', span: 2 },
	],
];

export const SEARCH_COLUMNS = 10;

/** Nombre de touches d'une rangée ; les rangées n'ont pas toutes la même. */
export function rowLength(row: number): number {
	return SEARCH_ROWS[row]?.length ?? 0;
}

/** Touche sous le curseur, ou `undefined` si la position n'existe pas. */
export function keyAt(row: number, col: number): SearchKey | undefined {
	return SEARCH_ROWS[row]?.[col];
}

/**
 * Colonne équivalente en passant d'une rangée à l'autre : on vise la touche la
 * plus proche horizontalement, pour ne pas sauter d'un bout à l'autre en
 * descendant sur la rangée des touches larges.
 */
export function nearestColumn(fromRow: number, fromCol: number, toRow: number): number {
	const from = SEARCH_ROWS[fromRow];
	const to = SEARCH_ROWS[toRow];
	if (!from || !to) return 0;

	const ratio = (columnStart(from, fromCol) + (from[fromCol].span ?? 1) / 2) / SEARCH_COLUMNS;
	let best = 0;
	let bestDistance = Infinity;
	for (let i = 0; i < to.length; i++) {
		const center = (columnStart(to, i) + (to[i].span ?? 1) / 2) / SEARCH_COLUMNS;
		const distance = Math.abs(center - ratio);
		if (distance < bestDistance) {
			bestDistance = distance;
			best = i;
		}
	}
	return best;
}

/** Position de départ d'une touche, en colonnes de grille. */
function columnStart(row: SearchKey[], index: number): number {
	let start = 0;
	for (let i = 0; i < index; i++) start += row[i].span ?? 1;
	return start;
}

/** Compare deux titres sans se soucier des accents ni de la ponctuation. */
export function normalizeForSearch(value: string): string {
	return value
		.normalize('NFD')
		.replace(/[̀-ͯ]/g, '')
		.replace(/[^a-z0-9]/gi, '')
		.toLowerCase();
}
