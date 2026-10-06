/**
 * Glyphes des boutons de manette, dans `public/assets/buttons/` : famille Xbox
 * ou PlayStation selon la manette branchée. Partagés par la barre d'aide et le
 * dock, pour qu'une touche ait la même image partout.
 */
export type GlyphButton = 'a' | 'b' | 'x' | 'y' | 'l1' | 'r1' | 'l2' | 'r2' | 'view';

export const GLYPHS: Record<'xbox' | 'ps5', Record<GlyphButton, string>> = {
	xbox: {
		a: 'xbox/a',
		b: 'xbox/b',
		x: 'xbox/x',
		y: 'xbox/y',
		l1: 'xbox/lb',
		r1: 'xbox/rb',
		l2: 'xbox/lt',
		r2: 'xbox/rt',
		view: 'xbox/view',
	},
	ps5: {
		a: 'ps5/cross',
		b: 'ps5/circle',
		x: 'ps5/square',
		y: 'ps5/triangle',
		l1: 'ps5/l1',
		r1: 'ps5/r1',
		l2: 'ps5/l2',
		r2: 'ps5/r2',
		view: 'ps5/create',
	},
};

export function glyphSrc(layout: 'xbox' | 'ps5', button: GlyphButton): string {
	return `/assets/buttons/${GLYPHS[layout][button]}.svg`;
}
