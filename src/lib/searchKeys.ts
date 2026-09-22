/**
 * Disposition du clavier de recherche. Elle vit à part du composant : l'écran
 * l'affiche, la navigation s'en sert pour savoir quelle touche est sous le
 * curseur — les deux doivent lire exactement la même grille.
 */
export const SEARCH_ROWS: string[][] = [
	['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'],
	['K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T'],
	['U', 'V', 'W', 'X', 'Y', 'Z', '-', "'", ':', '!'],
	['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
];

export const SEARCH_KEYS: string[] = SEARCH_ROWS.flat();
export const SEARCH_COLUMNS = 10;

/** Compare deux titres sans se soucier des accents ni de la ponctuation. */
export function normalizeForSearch(value: string): string {
	return value
		.normalize('NFD')
		.replace(/[̀-ͯ]/g, '')
		.replace(/[^a-z0-9]/gi, '')
		.toLowerCase();
}
