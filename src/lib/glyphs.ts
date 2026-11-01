/**
 * Glyphes des boutons de manette, dans `public/assets/buttons/`. Trois familles :
 * Xbox, PlayStation, et PlayStation en formes pleines. `auto` suit la manette
 * branchée. Partagés par la barre d'aide et le dock, pour qu'une touche ait la
 * même image partout.
 */
export type GlyphButton = 'a' | 'b' | 'x' | 'y' | 'l1' | 'r1' | 'l2' | 'r2' | 'view' | 'menu' | 'dpad' | 'up' | 'down' | 'left' | 'right';

export type GlyphFamily = 'xbox' | 'ps5' | 'ps5_solid';

const DIRECTIONS = { up: 'dpad_up', down: 'dpad_down', left: 'dpad_left', right: 'dpad_right' };

const PLAYSTATION: Record<GlyphButton, string> = {
	a: 'ps5/cross',
	b: 'ps5/circle',
	x: 'ps5/square',
	y: 'ps5/triangle',
	l1: 'ps5/l1',
	r1: 'ps5/r1',
	l2: 'ps5/l2',
	r2: 'ps5/r2',
	view: 'ps5/create',
	menu: 'ps5/options',
	dpad: 'ps5/dpad',
	...DIRECTIONS,
};

export const GLYPHS: Record<GlyphFamily, Record<GlyphButton, string>> = {
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
		menu: 'xbox/menu',
		dpad: 'xbox/dpad',
		...DIRECTIONS,
	},
	ps5: PLAYSTATION,
	ps5_solid: {
		...PLAYSTATION,
		a: 'ps5/cross_solid',
		b: 'ps5/circle_solid',
		x: 'ps5/square_solid',
		y: 'ps5/triangle_solid',
	},
};

export function glyphSrc(layout: GlyphFamily, button: GlyphButton): string {
	return `/assets/buttons/${GLYPHS[layout][button]}.svg`;
}

/** Aperçu d'un pack : ses quatre touches principales. */
export function glyphPreview(layout: GlyphFamily): string[] {
	return (['a', 'b', 'x', 'y'] as const).map((button) => glyphSrc(layout, button));
}
