<script lang="ts">
	import { padLayout } from './gamepad';
	import { glyphSrc, type GlyphButton, type GlyphFamily } from './glyphs';

	/**
	 * Glyphe d'un bouton de manette, de la famille de la manette branchée
	 * (Xbox ou PlayStation). Posé là où l'action se fait : le raccourci se lit
	 * sur l'élément, pas dans une légende.
	 */
	let { button, size = '24px' }: { button: GlyphButton; size?: string } = $props();

	let layout = $state<GlyphFamily>(padLayout());
	$effect(() => {
		const timer = setInterval(() => (layout = padLayout()), 1000);
		return () => clearInterval(timer);
	});
</script>

<img src={glyphSrc(layout, button)} alt={button.toUpperCase()} style="width: {size}; height: {size}" />
