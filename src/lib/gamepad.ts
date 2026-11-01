/**
 * Entrées manette et clavier, ramenées à une poignée d'actions.
 *
 * Même principe que l'InputManager de la version Godot : maintenir une
 * direction fait défiler, avec un délai initial puis une répétition. Les seuils
 * sont hauts et asymétriques (engagement 0,65 / relâchement 0,40) pour qu'un
 * stick qui traîne au repos ne déplace pas la sélection tout seul.
 */
import { GLYPHS, type GlyphFamily } from './glyphs';

export type Action =
	| 'up'
	| 'down'
	| 'left'
	| 'right'
	| 'accept'
	| 'cancel'
	| 'options'
	| 'search'
	/** Bouton de droite, Options (PlayStation) / Menu (Xbox) : le panneau de droite. */
	| 'menu'
	/** L1/LB et R1/RB : section précédente / suivante du dock, onglets du menu rapide. */
	| 'prev'
	| 'next'
	/** L2/LT et R2/RT : catégorie précédente / suivante (filtres, périodes). */
	| 'pagePrev'
	| 'pageNext'
	/** Bouton de gauche, View (Xbox) / Create (PS5), ou Home : le menu rapide, à gauche. */
	| 'view';

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
	6: 'pagePrev',
	7: 'pageNext',
	8: 'view',
	9: 'menu',
	// Xbox / PS : souvent pris par la Game Bar ou Steam, d'où le bouton View.
	16: 'view',
};

/** La croix : à part des boutons, elle suit la règle du stick (maintenir répète). */
const DPAD: [number, Action][] = [
	[12, 'up'],
	[13, 'down'],
	[14, 'left'],
	[15, 'right'],
];

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
	m: 'view',
	g: 'view',
	Home: 'view',
	Tab: 'view',
	p: 'menu',
	// Dock : A / E, comme L1 / R1. Catégories : Page précédente / suivante.
	a: 'prev',
	e: 'next',
	PageUp: 'pagePrev',
	PageDown: 'pageNext',
};

type Listener = (action: Action) => void;

const listeners = new Set<Listener>();
let held: Action | null = null;
let nextRepeat = 0;
/** L'action en cours d'envoi vient d'une touche maintenue, pas d'un nouvel appui. */
let repeating = false;
/**
 * Depuis quand Lobby n'a plus le focus. Un accroc d'une image ne compte pas : il
 * remettait la manette à zéro, et une direction maintenue se retrouvait bloquée
 * comme une touche déjà tenue, jusqu'au relâchement.
 */
let focusLostAt: number | null = null;
const FOCUS_GRACE = 300;

/**
 * Pour un geste qui ne doit pas se répéter tout seul : dans l'explorateur, gauche et
 * droite changent de dossier, et maintenus ils traverseraient toute l'arborescence.
 */
export function isRepeat(): boolean {
	return repeating;
}
let frame = 0;
/** Boutons enfoncés à la frame précédente, pour ne déclencher qu'au front montant. */
const pressed = new Set<number>();
/**
 * Manette déjà lue une fois. À la première lecture, son état sert de point de
 * départ, sans rien déclencher : une gâchette qui ne revient pas tout à fait
 * à zéro, ou une touche tenue au branchement, déclenchait une action fantôme.
 */
let seenPad = '';
/**
 * Capture (`?nopad`) : la manette est ignorée. Chrome headless lit la vraie
 * manette du PC, et une partie en cours faisait changer l'écran capturé.
 */
const NO_PAD = typeof location !== 'undefined' && new URLSearchParams(location.search).has('nopad');

/**
 * Actions acceptées même sans le focus. Pendant l'écran de lancement, Lobby
 * est au-dessus du jeu sans en avoir le focus : B doit pouvoir l'écarter.
 */
const background = new Set<Action>();

/** Actions transmises même quand la fenêtre n'a pas le focus (vide : aucune). */
export function allowInBackground(actions: Action[]) {
	background.clear();
	for (const action of actions) background.add(action);
}

/**
 * Lobby est-il vraiment au premier plan ? Le webview ne le dit pas de façon
 * fiable : `document.hasFocus()` restait vrai pendant qu'on jouait, et la
 * manette pilotait l'interface derrière le jeu. Dans l'application, on
 * demande donc à Windows si Lobby est au premier plan (`lobby_in_front`),
 * quatre fois par seconde.
 */
let windowActive = true;
let activeTimer: ReturnType<typeof setInterval> | null = null;

function watchForeground() {
	if (!(window as any).__TAURI_INTERNALS__ || activeTimer) return;
	activeTimer = setInterval(async () => {
		try {
			const { invoke } = await import('@tauri-apps/api/core');
			windowActive = await invoke<boolean>('lobby_in_front');
		} catch {
			windowActive = true;
		}
	}, 250);
}

/**
 * View + Menu (Share + Options) maintenus ensemble pendant une partie :
 * Lobby revient et ouvre le menu du jeu, comme le bouton Xbox. Lu même quand
 * Lobby n'est pas au premier plan — c'est tout l'intérêt. Maintenir évite de
 * le déclencher par mégarde ; les deux boutons, rarement pressés ensemble en
 * jeu, évitent le bouton Xbox / PS, déjà pris par la Game Bar et Steam.
 */
const COMBO = [8, 9];
const COMBO_HOLD = 400;
let comboHandler: (() => void) | null = null;
let comboSince = 0;
let comboFired = false;

/** Ce que déclenche View + Menu maintenus hors de Lobby (`null` : rien). */
export function onGameCombo(handler: (() => void) | null) {
	comboHandler = handler;
}

function checkCombo(pad: Gamepad, now: number) {
	const both = COMBO.every((i) => pad.buttons[i]?.pressed);
	if (!both) {
		comboSince = 0;
		comboFired = false;
		return;
	}
	if (!comboSince) comboSince = now;
	if (!comboFired && now - comboSince >= COMBO_HOLD) {
		comboFired = true;
		comboHandler?.();
	}
}

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

/** La direction demandée : la croix, sinon le stick. */
function wantedDirection(pad: Gamepad): Action | null {
	return DPAD.find(([i]) => pad.buttons[i]?.pressed)?.[1] ?? direction(pad);
}

function poll(now: number) {
	frame = requestAnimationFrame(poll);
	const pad = navigator.getGamepads?.().find((p) => p && p.connected) ?? null;
	// Fenêtre sans le focus (un jeu, une autre application) : la manette ne
	// pilote plus l'interface. Au retour, son état sert de nouveau départ :
	// une touche encore tenue ne déclenche rien.
	const focused = windowActive && document.hasFocus();
	if (focused) focusLostAt = null;
	else focusLostAt ??= now;
	if (pad && !NO_PAD && !focused && comboHandler) checkCombo(pad, now);
	const ignored = !focused && background.size === 0;
	if (!pad || NO_PAD || (ignored && now - (focusLostAt ?? now) >= FOCUS_GRACE)) {
		held = null;
		seenPad = '';
		return;
	}
	// Focus perdu depuis un instant : on n'agit pas, mais rien n'est oublié.
	if (ignored) return;
	const key = `${pad.index}:${pad.id}`;
	if (key !== seenPad) {
		seenPad = key;
		pressed.clear();
		pad.buttons.forEach((button, i) => {
			if (button?.pressed) pressed.add(i);
		});
		held = wantedDirection(pad);
		nextRepeat = Number.POSITIVE_INFINITY;
		return;
	}

	for (const [index, action] of Object.entries(BUTTONS)) {
		const i = Number(index);
		const down = pad.buttons[i]?.pressed ?? false;
		if (down && !pressed.has(i)) {
			pressed.add(i);
			if (!focused && !background.has(action)) continue;
			emit(action);
		} else if (!down) {
			pressed.delete(i);
		}
	}

	// Croix ou stick, même règle : un déplacement tout de suite, puis la répétition
	// tant que la direction est tenue.
	const wanted = focused ? wantedDirection(pad) : null;
	if (!wanted) {
		held = null;
	} else if (wanted !== held) {
		held = wanted;
		nextRepeat = now + INITIAL_REPEAT;
		emit(wanted);
	} else if (now >= nextRepeat) {
		nextRepeat = now + REPEAT_INTERVAL;
		repeating = true;
		emit(wanted);
		repeating = false;
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

	// Verr. Maj. ne doit pas désactiver les raccourcis.
	const action = KEYS[event.key.length === 1 ? event.key.toLowerCase() : event.key];
	if (!action) return;
	event.preventDefault();
	repeating = event.repeat;
	emit(action);
	repeating = false;
}

/** Branche les entrées et rend la fonction de débranchement. */
export function listen(listener: Listener): () => void {
	listeners.add(listener);
	if (listeners.size === 1) {
		frame = requestAnimationFrame(poll);
		window.addEventListener('keydown', onKey);
		watchForeground();
	}
	return () => {
		listeners.delete(listener);
		if (listeners.size === 0) {
			cancelAnimationFrame(frame);
			window.removeEventListener('keydown', onKey);
			if (activeTimer) clearInterval(activeTimer);
			activeTimer = null;
		}
	};
}

/** Marqueurs des manettes Sony dans l'identifiant renvoyé par le navigateur. */
const SONY = ['dualsense', 'dualshock', 'playstation', 'wireless controller', '054c'];

/** Choix de Réglages → Apparence : `auto` suit la manette branchée. */
let layoutChoice = 'auto';

export function setLayoutChoice(choice: string) {
	layoutChoice = choice;
}

/**
 * Famille de glyphes à afficher. Les index des boutons ne changent pas d'une
 * manette à l'autre : seule la façon de les nommer change.
 */
export function padLayout(): GlyphFamily {
	if (layoutChoice in GLYPHS) return layoutChoice as GlyphFamily;
	const pad = navigator.getGamepads?.().find((p) => p && p.connected);
	if (!pad) return 'xbox';
	const id = pad.id.toLowerCase();
	return SONY.some((marker) => id.includes(marker)) ? 'ps5' : 'xbox';
}

/**
 * Nom lisible d'une manette, tiré de l'identifiant du navigateur
 * (« DualSense Wireless Controller (STANDARD GAMEPAD Vendor: 054c …) »).
 */
export function padName(id: string): string {
	const lower = id.toLowerCase();
	if (lower.includes('dualsense') || lower.includes('0ce6') || lower.includes('0df2')) return 'Manette DualSense';
	if (lower.includes('dualshock') || (lower.includes('054c') && lower.includes('wireless controller'))) {
		return 'Manette DualShock 4';
	}
	if (lower.includes('xbox') || lower.includes('xinput') || lower.includes('045e')) return 'Manette Xbox';
	if (lower.includes('pro controller') || lower.includes('057e')) return 'Manette Switch Pro';
	if (lower.includes('8bitdo')) return 'Manette 8BitDo';
	// Sinon, le nom avant les détails techniques entre parenthèses.
	const name = id.replace(/\(.*$/, '').trim();
	return name || 'Manette';
}

/** Nom de la manette branchée, vide s'il n'y en a pas. */
export function currentPadName(): string {
	const pad = navigator.getGamepads?.().find((p) => p && p.connected);
	return pad ? padName(pad.id) : '';
}

/** Nombre de manettes branchées, affiché dans la barre du haut. */
export function padCount(): number {
	return navigator.getGamepads?.().filter((p) => p && p.connected).length ?? 0;
}

/** Vrai dès qu'une manette est branchée : sert à afficher les bons symboles. */
export function hasGamepad(): boolean {
	return padCount() > 0;
}
