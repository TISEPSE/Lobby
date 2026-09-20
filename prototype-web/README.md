# Prototype web — Interface Console

Prototype de comparaison : même interface, en web (Svelte + Vite) dans une
coquille **Tauri**. Le projet Godot à la racine n'est pas touché.

## À quoi ça sert

Juger si le web tient la promesse « design plus rapide à faire évoluer » :
ici, un dégradé, une ombre, une animation ou un centrage se changent dans un
fichier CSS, sans recompiler.

## Lancer

```
npm install
npm run dev            # dans le navigateur, http://localhost:5177
npm run tauri dev      # en application plein écran (compile la partie Rust)
```

## Ce qui est branché

- **Tes vrais jeux Steam** : `src/lib/data/games.json` est généré depuis les
  `appmanifest_*.acf` de ta bibliothèque, les images viennent du CDN public de
  Steam (aucune clé d'API).
- **Manette** : API Gamepad, seuils asymétriques (engagement 0,65 / relâchement
  0,40) et répétition au maintien — même logique que l'`InputManager` de Godot.
  Clavier également : flèches, Entrée, Échap.
- **Transition accueil → fiche** : `view-transition-name` sur la jaquette. Le
  navigateur anime le déplacement lui-même ; pas de jaquette fantôme à
  positionner à la main.
- **Lancement d'un jeu** : commande Rust `launch_game` (`steam -applaunch`), et
  `is_running` pour savoir quand la partie se termine.

## Outil de capture

`?screen=detail&index=4` ouvre directement un écran, comme `--capture` côté
Godot :

```
chrome --headless=new --window-size=1920,1080 --virtual-time-budget=9000 \
  --screenshot=out.png "http://localhost:5177/?screen=detail&index=4"
```

## Ce qui reste à faire si on garde cette voie

- Bibliothèque en grille, réglages, panneau latéral, vidéo de démarrage.
- Portage de la détection de jeux (Steam, Epic, `.lnk`) en Rust.
- Session Gamescope : la coquille Tauri remplace l'export Godot, le reste du
  dossier `system/` ne bouge pas.
