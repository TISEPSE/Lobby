/**
 * Retours sonores de l'interface.
 *
 * Les sons viennent de `public/assets/sounds/` (design PlayStation fourni avec
 * le projet). Ils sont décodés une fois puis rejoués depuis la mémoire : un
 * déplacement dans le carrousel ne doit pas attendre un chargement.
 *
 * Il reste une synthèse de secours — quelques lignes d'oscillateur — pour les
 * signaux sans fichier (l'erreur) et pour le cas où un fichier manque : mieux
 * vaut un bip qu'une interface muette qui laisse croire qu'elle n'a rien
 * entendu.
 */

type Cue = 'move' | 'accept' | 'cancel' | 'error' | 'launch' | 'pad';

/** Fichier et volume de chaque signal. Sans fichier, on synthétise. */
const CUES: Record<Cue, { file?: string; gain: number }> = {
	// Le déplacement s'entend cent fois par minute : court et discret.
	move: { file: 'ps5-scroll.wav', gain: 0.45 },
	accept: { file: 'ps5-selection-button.wav', gain: 0.7 },
	cancel: { file: 'ps5-back-button.wav', gain: 0.6 },
	// Pas de fichier d'erreur : on garde le signal grave de synthèse, qui ne
	// ressemble à aucun autre son de l'interface.
	error: { gain: 0.9 },
	// L'ouverture d'un jeu mérite le son le plus ample du jeu de sons.
	launch: { file: 'ps5-popup-2.wav', gain: 0.8 },
	// Manette branchée ou débranchée : le même signal, plus discret.
	pad: { file: 'ps5-popup-2.wav', gain: 0.45 },
};

/** Repli synthétisé : fréquence de départ, d'arrivée et durée. */
const TONES: Record<Cue, { from: number; to: number; duration: number }> = {
	move: { from: 620, to: 560, duration: 0.05 },
	accept: { from: 520, to: 780, duration: 0.11 },
	cancel: { from: 480, to: 320, duration: 0.11 },
	error: { from: 260, to: 200, duration: 0.2 },
	launch: { from: 440, to: 880, duration: 0.3 },
	pad: { from: 660, to: 880, duration: 0.18 },
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

/** Sons décodés, prêts à rejouer. */
const buffers = new Map<Cue, AudioBuffer>();
/** Fichiers dont le chargement a échoué : inutile de réessayer à chaque appui. */
const missing = new Set<Cue>();

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
async function load(cue: Cue): Promise<AudioBuffer | null> {
	const { file } = CUES[cue];
	const ctx = ensureContext();
	if (!file || !ctx || missing.has(cue)) return null;
	const known = buffers.get(cue);
	if (known) return known;

	try {
		const response = await fetch(`/assets/sounds/${file}`);
		if (!response.ok) throw new Error(String(response.status));
		const decoded = await ctx.decodeAudioData(await response.arrayBuffer());
		buffers.set(cue, decoded);
		return decoded;
	} catch {
		// Fichier absent ou illisible : on retombera sur la synthèse.
		missing.add(cue);
		return null;
	}
}

/** Décode tous les sons d'avance, pour que le premier appui sonne déjà juste. */
export function preloadSounds() {
	if (!enabled) return;
	for (const cue of Object.keys(CUES) as Cue[]) void load(cue);
}

/** Joue un signal. Sans sortie audio, ne fait rien — jamais d'erreur visible. */
export function play(cue: Cue) {
	const ctx = ensureContext();
	if (!ctx) return;
	if (ctx.state === 'suspended') void ctx.resume();

	// À zéro, on ne joue rien du tout (pas même le repli synthétique).
	if (levelOf(cue) <= 0) return;

	const buffer = buffers.get(cue);
	if (buffer) {
		playBuffer(ctx, buffer, levelOf(cue));
		return;
	}

	// Pas encore décodé : on émet le repli tout de suite et on charge pour la
	// prochaine fois. Attendre le fichier ferait un son en retard sur le geste.
	if (!missing.has(cue) && CUES[cue].file) {
		void load(cue).then((loaded) => {
			if (!loaded) return;
		});
	}
	playTone(ctx, cue);
}

function playBuffer(ctx: AudioContext, buffer: AudioBuffer, gain: number) {
	const source = ctx.createBufferSource();
	source.buffer = buffer;
	const volume = ctx.createGain();
	volume.gain.value = gain;
	source.connect(volume).connect(ctx.destination);
	source.start();
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
	}
}

export function isSoundEnabled(): boolean {
	return enabled;
}
