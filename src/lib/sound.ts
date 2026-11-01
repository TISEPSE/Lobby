/**
 * Retours sonores de l'interface.
 *
 * Les sons viennent de `public/assets/sounds/`. Ils sont décodés une fois puis
 * rejoués depuis la mémoire : un déplacement dans le carrousel ne doit pas
 * attendre un chargement. Le clic et le déplacement se choisissent dans les
 * Réglages (`SOUND_CHOICES`).
 *
 * Il reste une synthèse de secours — quelques lignes d'oscillateur — pour les
 * signaux sans fichier (l'erreur) et pour le cas où un fichier manque : mieux
 * vaut un bip qu'une interface muette qui laisse croire qu'elle n'a rien
 * entendu.
 */

type Cue = 'move' | 'accept' | 'cancel' | 'error' | 'launch' | 'pad' | 'section';

/**
 * Un son et ses réglages. `skip` saute le silence au début du fichier, en
 * secondes : le son doit partir avec le geste. Sans fichier, on synthétise.
 */
interface Sound {
	file?: string;
	gain: number;
	skip?: number;
}

/** Signaux dont le son se choisit dans les Réglages. */
export type SoundSlot = 'accept' | 'move';

export interface SoundChoice extends Sound {
	id: string;
	label: string;
	file: string;
}

/**
 * Les sons proposés, le premier étant celui par défaut. Chaque gain est réglé sur
 * le volume perçu du fichier : on peut passer de l'un à l'autre sans que l'un
 * sorte trop fort. Le mesurer avant d'en ajouter un (durée, silence de début).
 */
export const SOUND_CHOICES: Record<SoundSlot, SoundChoice[]> = {
	accept: [
		{ id: 'click-6', label: 'Clic 1', file: 'ui-click-6.mp3', gain: 0.21, skip: 0.03 },
		{ id: 'click-7', label: 'Clic 2', file: 'ui-click-7.mp3', gain: 0.15, skip: 0.15 },
		{ id: 'chime', label: 'Carillon', file: 'deep-ui-chime.mp3', gain: 0.43 },
		{ id: 'playstation', label: 'PlayStation', file: 'ps5-selection-button.wav', gain: 0.7 },
	],
	move: [
		// 0,12 s : il s'arrête quand la répétition d'une direction repart.
		{ id: 'bong', label: 'Bong', file: 'kenney-bong.ogg', gain: 0.27 },
		{ id: 'playstation', label: 'PlayStation', file: 'ps5-scroll.wav', gain: 0.45 },
	],
};

/** Le son demandé, ou celui par défaut si ce réglage ne correspond plus à rien. */
export function soundChoice(slot: SoundSlot, id: string): SoundChoice {
	return SOUND_CHOICES[slot].find((choice) => choice.id === id) ?? SOUND_CHOICES[slot][0];
}

/** Fichier et volume de chaque signal. */
const CUES: Record<Cue, Sound> = {
	// Le déplacement s'entend cent fois par minute : court et discret.
	move: SOUND_CHOICES.move[0],
	accept: SOUND_CHOICES.accept[0],
	cancel: { file: 'ps5-back-button.wav', gain: 0.6 },
	// Pas de fichier d'erreur : on garde le signal grave de synthèse, qui ne
	// ressemble à aucun autre son de l'interface.
	error: { gain: 0.9 },
	// L'ouverture d'un jeu mérite le son le plus ample du jeu de sons.
	launch: { file: 'ps5-popup-2.wav', gain: 0.8 },
	// Manette branchée ou débranchée : le même signal, plus discret.
	pad: { file: 'ps5-popup-2.wav', gain: 0.45 },
	// Changement de section (L1 / R1) : un souffle très court, synthétisé
	// (`playWhoosh`) — un glissement, pas un clic de plus.
	section: { gain: 0.5 },
};

/** Repli synthétisé : fréquence de départ, d'arrivée et durée. */
const TONES: Record<Cue, { from: number; to: number; duration: number }> = {
	move: { from: 620, to: 560, duration: 0.05 },
	accept: { from: 520, to: 780, duration: 0.11 },
	cancel: { from: 480, to: 320, duration: 0.11 },
	error: { from: 260, to: 200, duration: 0.2 },
	launch: { from: 440, to: 880, duration: 0.3 },
	pad: { from: 660, to: 880, duration: 0.18 },
	section: { from: 900, to: 2600, duration: 0.16 },
};

let context: AudioContext | null = null;
let enabled = true;

/** Famille de chaque son, pour les volumes réglables (Réglages → Audio). */
const GROUP: Record<Cue, 'menu' | 'alerts' | 'launch'> = {
	move: 'menu',
	accept: 'menu',
	cancel: 'menu',
	error: 'alerts',
	pad: 'alerts',
	launch: 'launch',
	section: 'menu',
};

/** Volumes de 0 à 1 : général et par famille. */
const volumes = { master: 1, menu: 1, alerts: 1, launch: 1 };

export function setVolumes(next: { master: number; menu: number; alerts: number; launch: number }) {
	Object.assign(volumes, next);
}

/** Volume effectif d'un son : le sien, multiplié par le volume général. */
function levelOf(cue: Cue): number {
	return CUES[cue].gain * volumes.master * volumes[GROUP[cue]];
}

/** Sons décodés, par fichier, prêts à rejouer. */
const buffers = new Map<string, AudioBuffer>();
/** Fichiers dont le chargement a échoué : inutile de réessayer à chaque appui. */
const missing = new Set<string>();

/** Le contexte audio n'existe qu'après une interaction : on le crée à la demande. */
function ensureContext(): AudioContext | null {
	if (!enabled) return null;
	if (context) return context;
	try {
		context = new AudioContext();
	} catch {
		// Pas de sortie audio : l'interface reste utilisable, simplement muette.
		enabled = false;
		return null;
	}
	return context;
}

/**
 * Charge et décode un son. Le premier appui sur une touche peut donc être
 * muet ; `preload()` évite ce trou au démarrage.
 */
async function load(file: string | undefined): Promise<AudioBuffer | null> {
	const ctx = ensureContext();
	if (!file || !ctx || missing.has(file)) return null;
	const known = buffers.get(file);
	if (known) return known;

	try {
		const response = await fetch(`/assets/sounds/${file}`);
		if (!response.ok) throw new Error(String(response.status));
		const decoded = await ctx.decodeAudioData(await response.arrayBuffer());
		buffers.set(file, decoded);
		return decoded;
	} catch {
		// Fichier absent ou illisible : on retombera sur la synthèse.
		missing.add(file);
		return null;
	}
}

/** Décode tous les sons d'avance, pour que le premier appui sonne déjà juste. */
export function preloadSounds() {
	if (!enabled) return;
	for (const cue of Object.keys(CUES) as Cue[]) void load(CUES[cue].file);
}

/** Applique le son choisi dans les Réglages. */
export function useSound(slot: SoundSlot, id: string) {
	const choice = soundChoice(slot, id);
	if (CUES[slot] === choice) return;
	CUES[slot] = choice;
	void load(choice.file);
}

/** Fait entendre un son de la liste, au volume où il jouerait, sans l'appliquer. */
export async function previewSound(slot: SoundSlot, id: string) {
	const ctx = ensureContext();
	if (!ctx) return;
	if (ctx.state === 'suspended') void ctx.resume();
	const { file, gain, skip } = soundChoice(slot, id);
	const buffer = await load(file);
	if (buffer) playBuffer(ctx, slot, buffer, gain * volumes.master * volumes[GROUP[slot]], skip);
}

/** Joue un signal. Sans sortie audio, ne fait rien — jamais d'erreur visible. */
export function play(cue: Cue) {
	const ctx = ensureContext();
	if (!ctx) return;
	if (ctx.state === 'suspended') void ctx.resume();

	// À zéro, on ne joue rien du tout (pas même le repli synthétique).
	if (levelOf(cue) <= 0) return;

	if (cue === 'section') {
		playWhoosh(ctx, levelOf(cue));
		return;
	}

	const { file, skip } = CUES[cue];
	const buffer = file ? buffers.get(file) : undefined;
	if (buffer) {
		playBuffer(ctx, cue, buffer, levelOf(cue), skip);
		return;
	}

	// Pas encore décodé : on émet le repli tout de suite et on charge pour la
	// prochaine fois. Attendre le fichier ferait un son en retard sur le geste.
	void load(file);
	playTone(ctx, cue);
}

/** Fondu d'un son coupé : inaudible comme tel, mais il évite un claquement. */
const CUT_FADE = 0.03;

/** Son en train de jouer, par signal : le même signal ne s'empile jamais sur lui-même. */
const voices = new Map<Cue, { source: AudioBufferSourceNode; volume: GainNode }>();

function playBuffer(ctx: AudioContext, cue: Cue, buffer: AudioBuffer, gain: number, skip = 0) {
	const previous = voices.get(cue);
	if (previous) {
		const end = ctx.currentTime + CUT_FADE;
		previous.volume.gain.setValueAtTime(previous.volume.gain.value, ctx.currentTime);
		previous.volume.gain.linearRampToValueAtTime(0, end);
		previous.source.stop(end);
	}
	const source = ctx.createBufferSource();
	source.buffer = buffer;
	const volume = ctx.createGain();
	volume.gain.value = gain;
	source.connect(volume).connect(ctx.destination);
	voices.set(cue, { source, volume });
	source.onended = () => {
		if (voices.get(cue)?.source === source) voices.delete(cue);
	};
	source.start(0, skip);
}

/**
 * Souffle de glissement : un bruit blanc très court, passé dans un filtre dont
 * la fréquence monte — l'oreille l'entend comme un « fffuit » qui glisse.
 */
function playWhoosh(ctx: AudioContext, level: number) {
	const { from, to, duration } = TONES.section;
	const now = ctx.currentTime;

	const noise = ctx.createBuffer(1, Math.ceil(ctx.sampleRate * duration), ctx.sampleRate);
	const data = noise.getChannelData(0);
	for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
	const source = ctx.createBufferSource();
	source.buffer = noise;

	const filter = ctx.createBiquadFilter();
	filter.type = 'bandpass';
	filter.Q.value = 1.4;
	filter.frequency.setValueAtTime(from, now);
	filter.frequency.exponentialRampToValueAtTime(to, now + duration);

	// Montée douce puis extinction : pas de claquement au début ni à la fin.
	const envelope = ctx.createGain();
	const peak = Math.max(level * 0.35, 0.0002);
	envelope.gain.setValueAtTime(0.0001, now);
	envelope.gain.exponentialRampToValueAtTime(peak, now + duration * 0.35);
	envelope.gain.exponentialRampToValueAtTime(0.0001, now + duration);

	source.connect(filter).connect(envelope).connect(ctx.destination);
	source.start(now);
	source.stop(now + duration + 0.02);
}

function playTone(ctx: AudioContext, cue: Cue) {
	const { from, to, duration } = TONES[cue];
	const gain = levelOf(cue) * 0.1;
	const now = ctx.currentTime;

	const oscillator = ctx.createOscillator();
	oscillator.type = 'triangle';
	oscillator.frequency.setValueAtTime(from, now);
	oscillator.frequency.exponentialRampToValueAtTime(to, now + duration);

	// Attaque immédiate, extinction douce : un son sec « claque » désagréablement.
	const envelope = ctx.createGain();
	envelope.gain.setValueAtTime(0.0001, now);
	envelope.gain.exponentialRampToValueAtTime(Math.max(gain, 0.0002), now + 0.012);
	envelope.gain.exponentialRampToValueAtTime(0.0001, now + duration);

	oscillator.connect(envelope).connect(ctx.destination);
	oscillator.start(now);
	oscillator.stop(now + duration + 0.02);
}

/** Coupe ou rétablit tous les retours sonores. */
export function setSoundEnabled(value: boolean) {
	enabled = value;
	if (!value && context) {
		void context.close();
		context = null;
		buffers.clear();
		voices.clear();
	}
}

export function isSoundEnabled(): boolean {
	return enabled;
}
