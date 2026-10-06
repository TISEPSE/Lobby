/**
 * Dispositions des claviers à l'écran. Elles vivent à part des composants :
 * l'écran les affiche, la navigation s'en sert pour savoir quelle touche est
 * sous le curseur — les deux doivent lire exactement la même grille.
 *
 * Disposition **AZERTY** : c'est celle que l'utilisateur a sous les doigts sur
 * son vrai clavier, et chercher une lettre sur une grille QWERTY quand on tape
 * en AZERTY fait perdre plus de temps que l'ordre alphabétique.
 *
 * Les rangées n'ont pas toutes la même longueur (les dernières portent des
 * touches larges) : la sélection se repère donc en **rangée + colonne**, jamais
 * par un index à plat.
 */

export interface SearchKey {
	/** Caractère inséré. Vide pour une touche d'action. */
	value: string;
	/** Ce que fait la touche quand elle n'écrit pas de caractère. */
	action?: 'space' | 'backspace' | 'clear' | 'caps' | 'cancel' | 'confirm';
	/** Icône de `public/assets/icons/` : une flèche vaut mieux que le mot « Effacer ». */
	icon?: string;
	/** Texte affiché à côté de l'icône, pour les touches larges. */
	label?: string;
	/**
	 * Bouton de la manette qui fait la même chose. Son glyphe s'affiche **sur
	 * la touche** : c'est là qu'on le cherche, pas dans une légende en bas de
	 * page.
	 */
	button?: 'a' | 'b' | 'x' | 'y';
	/** Largeur en colonnes. */
	span?: number;
}

function keys(row: string): SearchKey[] {
	return [...row].map((value) => ({ value }));
}

/** Les trois rangées de lettres, dans l'ordre d'un clavier français. */
const AZERTY = ['AZERTYUIOP', 'QSDFGHJKLM', 'WXCVBN-\':!'];

export const SEARCH_COLUMNS = 10;

/**
 * Le clavier à l'écran (pseudo, clé SteamGridDB, recherche) : chiffres en
 * tête, lettres AZERTY, la casse et les deux issues — annuler ou valider.
 */
export function textKeyboardRows(caps: boolean): SearchKey[][] {
	const letter = (row: string) =>
		[...row].map((value) => ({ value: caps ? value : value.toLowerCase() }));

	return [
		keys('1234567890'),
		...AZERTY.map(letter),
		[
			{ value: '', action: 'caps', icon: 'shift', label: caps ? 'Maj' : 'Min', span: 2 },
			{ value: '', action: 'space', icon: 'space', label: 'Espace', span: 3, button: 'y' },
			{ value: '', action: 'backspace', icon: 'backspace', label: 'Effacer', span: 2, button: 'x' },
			{ value: '', action: 'cancel', icon: 'exit', span: 1, button: 'b' },
			{ value: '', action: 'confirm', icon: 'check', label: 'Valider', span: 2 },
		],
	];
}

/** Nombre de touches d'une rangée ; les rangées n'ont pas toutes la même. */
export function rowLength(row: number, rows: SearchKey[][]): number {
	return rows[row]?.length ?? 0;
}

/** Touche sous le curseur, ou `undefined` si la position n'existe pas. */
export function keyAt(
	row: number,
	col: number,
	rows: SearchKey[][]
): SearchKey | undefined {
	return rows[row]?.[col];
}

/**
 * Colonne équivalente en passant d'une rangée à l'autre : on vise la touche la
 * plus proche horizontalement, pour ne pas sauter d'un bout à l'autre en
 * descendant sur la rangée des touches larges.
 */
export function nearestColumn(
	fromRow: number,
	fromCol: number,
	toRow: number,
	rows: SearchKey[][]
): number {
	const from = rows[fromRow];
	const to = rows[toRow];
	if (!from || !to || !from[fromCol]) return 0;

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
