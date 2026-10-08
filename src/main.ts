import { mount } from 'svelte'
import './app.css'
import App from './App.svelte'
import GameOverlay from './GameOverlay.svelte'

// La fenêtre du menu du jeu (`open_game_overlay`) charge la même page, avec
// `__LOBBY_OVERLAY__` posé par Rust : elle n'affiche que ce menu.
const overlay = (window as any).__LOBBY_OVERLAY__ !== undefined

const app = mount(overlay ? GameOverlay : App, {
  target: document.getElementById('app')!,
})

export default app
