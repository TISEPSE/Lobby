/**
 * Entrées manette et clavier, ramenées à une poignée d'actions.
 *
 * Même principe que l'InputManager de la version Godot : maintenir une
 * direction fait défiler, avec un délai initial puis une répétition. Les seuils
 * sont hauts et asymétriques (engagement 0,65 / relâchement 0,40) pour qu'un
 * stick qui traîne au repos ne déplace pas la sélection tout seul.
 */

export type Action =
	| 'up'
	| 'down'
	| 'left'
	| 'right'
	| 'accept'
	| 'cancel'
	| 'options'
	| 'search'
	/** Bouton Options (PlayStation) / Menu (Xbox) : l'alimentation. */
	| 'menu'
	/** Gâchettes hautes L1/LB et R1/RB : on change d'onglet. */
	| 'prev'
	| 'next';

const ENGAGE = 0.65;
const RELEASE = 0.4;
const INITIAL_REPEAT = 350;
const REPEAT_INTERVAL = 120;

/** Disposition Xbox, celle que renvoie l'API Gamepad en mapping « standard ». */
const BUTTONS: Record<number, Action> = {
	0: 'accept',
	1: 'cancel',
	2: 'options',
	3: 'search',
	4: 'prev',
	5: 'next',
	9: 'menu',
	12: 'up',
	13: 'down',
	14: 'left',
	15: 'right',
};

const KEYS: Record<string, Action> = {
	ArrowUp: 'up',
	ArrowDown: 'down',
	ArrowLeft: 'left',
	ArrowRight: 'right',
	Enter: 'accept',
	' ': 'accept',
	Escape: 'cancel',
	Backspace: 'cancel',
	x: 'options',
	y: 'search',
	m: 'menu',
	PageUp: 'prev',
	PageDown: 'next',
	a: 'prev',
	e: 'next',
};

type Listener = (action: Action) => void;

const listeners = new Set<Listener>();
let held: Action | null = null;
let nextRepeat = 0;
let frame = 0;
/** Boutons enfoncés à la frame précédente, pour ne déclencher qu'au front montant. */
const pressed = new Set<number>();

function emit(action: Action) {
	for (const listener of listeners) listener(action);
}

function direction(pad: Gamepad): Action | null {
	const [x, y] = [pad.axes[0] ?? 0, pad.axes[1] ?? 0];
	const threshold = held ? RELEASE : ENGAGE;
	if (Math.abs(x) <= threshold && Math.abs(y) <= threshold) return null;
	if (Math.abs(x) >= Math.abs(y)) return x > 0 ? 'right' : 'left';
	return y > 0 ? 'down' : 'up';
}

function poll(now: number) {
	frame = requestAnimationFrame(poll);
	const pad = navigator.getGamepads?.().find((p) => p && p.connected) ?? null;
	if (!pad) {
		held = null;
		return;
	}

	for (const [index, action] of Object.entries(BUTTONS)) {
		const i = Number(index);
		const down = pad.buttons[i]?.pressed ?? false;
		if (down && !pressed.has(i)) {
			pressed.add(i);
			emit(action);
			if (action === 'up' || action === 'down' || action === 'left' || action === 'right') {
				held = action;
				nextRepeat = now + INITIAL_REPEAT;
			}
		} else if (!down) {
			pressed.delete(i);
		}
	}

	const stick = direction(pad);
	if (stick) {
		if (stick !== held) {
			held = stick;
			nextRepeat = now + INITIAL_REPEAT;
			emit(stick);
		} else if (now >= nextRepeat) {
			nextRepeat = now + REPEAT_INTERVAL;
			emit(stick);
		}
	} else if (held && !pad.buttons[12]?.pressed && !pad.buttons[13]?.pressed && !pad.buttons[14]?.pressed && !pad.buttons[15]?.pressed) {
		held = null;
	}
}

function onKey(event: KeyboardEvent) {
	// Ne pas intercepter les touches si l'utilisateur saisit du texte ou si le clavier virtuel est ouvert
	const target = event.target as HTMLElement | null;
	const isInput = target && (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable);
	const isKeyboardOpen = typeof document !== 'undefined' && !!document.querySelector('.keyboard-backdrop');

	if (isInput || isKeyboardOpen) {
		return;
	}

	const action = KEYS[event.key];
	if (!action) return;
	event.preventDefault();
	emit(action);
}

/** Branche les entrées et rend la fonction de débranchement. */
export function listen(listener: Listener): () => void {
	listeners.add(listener);
	if (listeners.size === 1) {
		frame = requestAnimationFrame(poll);
		window.addEventListener('keydown', onKey);
	}
	return () => {
		listeners.delete(listener);
		if (listeners.size === 0) {
			cancelAnimationFrame(frame);
			window.removeEventListener('keydown', onKey);
		}
	};
}

/** Marqueurs des manettes Sony dans l'identifiant renvoyé par le navigateur. */
const SONY = ['dualsense', 'dualshock', 'playstation', 'wireless controller', '054c'];

/**
 * Famille de glyphes à afficher. Les index des boutons ne changent pas d'une
 * manette à l'autre : seule la façon de les nommer change.
 */
export function padLayout(): 'xbox' | 'ps5' {
	const pad = navigator.getGamepads?.().find((p) => p && p.connected);
	if (!pad) return 'xbox';
	const id = pad.id.toLowerCase();
	return SONY.some((marker) => id.includes(marker)) ? 'ps5' : 'xbox';
}

/** Nombre de manettes branchées, affiché dans la barre du haut. */
export function padCount(): number {
	return navigator.getGamepads?.().filter((p) => p && p.connected).length ?? 0;
}

/** Vrai dès qu'une manette est branchée : sert à afficher les bons symboles. */
export function hasGamepad(): boolean {
	return padCount() > 0;
}
