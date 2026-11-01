import { mount } from 'svelte'
import './app.css'
import App from './App.svelte'
import GameOverlay from './GameOverlay.svelte'

/**
 * Rendu sans carte graphique ? Le flou d'arrière-plan y fait tomber l'explorateur
 * de 55 à 9 images par seconde, alors qu'il ne coûte rien avec une carte graphique
 * (240 images par seconde, avec ou sans). C'est le pilote WebGL qui le dit.
 */
function softwareRendering(): boolean {
  const gl = document.createElement('canvas').getContext('webgl')
  if (!gl) return true
  const info = gl.getExtension('WEBGL_debug_renderer_info')
  const renderer = info ? String(gl.getParameter(info.UNMASKED_RENDERER_WEBGL)) : ''
  gl.getExtension('WEBGL_lose_context')?.loseContext()
  return /swiftshader|llvmpipe|software|basic render/i.test(renderer)
}

if (softwareRendering()) document.documentElement.dataset.noBlur = ''

// La fenêtre du menu du jeu (`open_game_overlay`) charge la même page, avec
// `__LOBBY_OVERLAY__` posé par Rust : elle n'affiche que ce menu.
// Capture : `?overlay=demo`.
const overlay =
  (window as any).__LOBBY_OVERLAY__ !== undefined ||
  new URLSearchParams(location.search).get('overlay') === 'demo'

const app = mount(overlay ? GameOverlay : App, {
  target: document.getElementById('app')!,
})

export default app
