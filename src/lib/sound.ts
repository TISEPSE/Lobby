/**
 * Retours sonores de l'interface.
 *
 * Les sons sont **synthétisés** à la volée plutôt que chargés depuis des
 * fichiers : quelques dizaines de lignes valent mieux que des assets à gérer,
 * et le résultat reste cohérent — une même enveloppe, une même famille de
 * timbres pour toute l'interface.
 */

type Cue = 'move' | 'accept' | 'cancel' | 'error' | 'launch';

/** Fréquence et durée de chaque signal, en hertz et en secondes. */
const CUES: Record<Cue, { from: number; to: number; duration: number; gain: number }> = {
	// Un clic court et discret : on l'entend cent fois par minute.
	move: { from: 620, to: 560, duration: 0.05, gain: 0.05 },
	// La validation monte : elle ouvre.
	accept: { from: 520, to: 780, duration: 0.11, gain: 0.08 },
	// Le retour descend : il ferme.
	cancel: { from: 480, to: 320, duration: 0.11, gain: 0.07 },
	// L'erreur reste basse et un peu plus longue, sans être agressive.
	error: { from: 260, to: 200, duration: 0.2, gain: 0.09 },
	// Le lancement d'un jeu mérite un accord, pas un bip.
	launch: { from: 440, to: 880, duration: 0.3, gain: 0.1 },
};

let context: AudioContext | null = null;
let enabled = true;

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

/** Joue un signal. Sans sortie audio, ne fait rien — jamais d'erreur visible. */
export function play(cue: Cue) {
	const ctx = ensureContext();
	if (!ctx) return;
	if (ctx.state === 'suspended') void ctx.resume();

	const { from, to, duration, gain } = CUES[cue];
	const now = ctx.currentTime;

	const oscillator = ctx.createOscillator();
	oscillator.type = 'triangle';
	oscillator.frequency.setValueAtTime(from, now);
	oscillator.frequency.exponentialRampToValueAtTime(to, now + duration);

	// Attaque immédiate, extinction douce : un son sec « claque » désagréablement.
	const envelope = ctx.createGain();
	envelope.gain.setValueAtTime(0.0001, now);
	envelope.gain.exponentialRampToValueAtTime(gain, now + 0.012);
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
	}
}

export function isSoundEnabled(): boolean {
	return enabled;
}
