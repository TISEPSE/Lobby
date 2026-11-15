import { svelte } from '@sveltejs/vite-plugin-svelte'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [svelte()],
  server: {
    // Vite n'a rien à surveiller côté Rust. Il suivait `src-tauri/target` et
    // s'arrêtait net (EBUSY) sur un fichier verrouillé par la compilation,
    // ce qui faisait échouer `tauri dev` avant l'ouverture de la fenêtre.
    watch: { ignored: ['**/src-tauri/**'] },
  },
})
