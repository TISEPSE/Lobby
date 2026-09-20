# Interface Console

Interface de type console ("10-foot UI") qui transforme un PC en console de jeux. Elle se lance au démarrage, s'affiche sur TV et se contrôle uniquement à la manette.

## Vision et rendu final

- Le PC démarre directement sur l'interface, sans bureau ni souris.
- Écran d'accueil avec carrousel de jaquettes, bibliothèque en grille, fiche détaillée d'un jeu.
- Style moderne et cinématique (références : PS5, Xbox, Steam Big Picture) avec une identité originale.
- Fond = artwork du jeu sélectionné, thème sombre, une seule couleur d'accent.
- Navigation 100 % manette : D-pad / stick, A = valider, B = retour, X = options, Y = recherche.
- Lancer un jeu met l'interface de côté, puis la ramène au premier plan quand le jeu se termine.
- Cible finale : session Linux dédiée (Gamescope + systemd), comme le Steam Deck.

## Stack

- **Tauri 2** (coquille Rust) + **Svelte 5** + **Vite** + TypeScript.
- Le rendu est du web : la direction artistique vit dans le CSS, pas dans du code.
- Cible : Linux (Arch / Bazzite), Wayland via Gamescope. Développement sous Windows (WebView2), tout doit rester portable.
- **Aucune clé d'API nulle part** : jaquettes et fiches viennent des points d'entrée publics de Steam.

### Pourquoi pas Godot

Le projet a d'abord été écrit en Godot 4 / GDScript. Tout est conservé dans l'historique git (commit « Sauvegarde de la version Godot avant bascule sur Tauri ») : écrans, thème, détection de jeux, lecteur `.lnk`, métadonnées Steam, intégration Gamescope. La bascule a eu lieu parce que chaque évolution visuelle y coûtait un `StyleBoxFlat`, des offsets mesurés à la main et un cycle import/relance, là où le même changement tient en trois lignes de CSS. **Pour retrouver un algorithme (détection Steam/Epic, parseur `.lnk`, seuils manette), lire le commit de sauvegarde plutôt que de le réinventer.**

## Structure du projet

```
.
├── index.html
├── package.json
├── vite.config.ts
├── public/
│   └── assets/
│       ├── buttons/        # glyphes des touches : xbox/ et ps5/
│       ├── icons/          # icônes d'interface (étoile Font Awesome, etc.)
│       ├── avatars/        # photos de profil fournies
│       └── boot/           # vidéos d'introduction
├── src/
│   ├── App.svelte          # racine : écran courant, entrées, lancement
│   ├── app.css             # thème : variables de couleur, rayons, durées
│   └── lib/
│       ├── Home.svelte     # accueil : artwork + carrousel
│       ├── Detail.svelte   # fiche d'un jeu
│       ├── Backdrop.svelte # artwork en fondu enchaîné
│       ├── HelpBar.svelte  # barre d'aide, glyphes de la manette branchée
│       ├── gamepad.ts      # manette et clavier → actions
│       ├── launcher.ts     # lancement d'un jeu via Tauri
│       └── data/games.json # bibliothèque
├── src-tauri/              # coquille Rust (fenêtre, lancement de process)
├── system/                 # scripts Linux : gamescope, systemd, autologin
└── Références-XBOX/        # captures de référence pour la direction artistique
```

## Conventions

- Code, variables, noms de fichiers en anglais ; commentaires et textes d'interface en français.
- TypeScript partout, `strict` activé. Svelte 5 avec les runes (`$state`, `$derived`, `$props`, `$effect`).
- Composants en `PascalCase.svelte`, modules en `camelCase.ts`.
- **Pas de valeurs magiques dans les composants** : couleurs, rayons, durées et marges sont des variables CSS définies dans `src/app.css`. Changer l'accent ou l'espacement se fait à un seul endroit.
- Marges de sécurité TV : `--safe-x` / `--safe-y` (5 %).
- Animations courtes (`--fast` 180 ms, `--normal` 260 ms) avec `--ease`, jamais de ralentissement perceptible.
- Texte d'au moins 17 px à l'écran, contraste élevé : ça se lit depuis un canapé.
- La sélection doit toujours être visible (agrandissement + contour d'accent + halo) et jamais perdue.
- Transition entre écrans : `view-transition-name` partagé sur la jaquette. Le navigateur anime le déplacement, on ne mesure aucun rectangle à la main.
- Le voile posé sur un artwork est un dégradé (`Backdrop.svelte`) : lisible en bas, artwork préservé en haut. Sur une fiche, il s'appuie à gauche, là où se trouve le texte.
- L'artwork ne change qu'une fois la nouvelle image chargée : deux couches se relaient, sinon on verrait un clignotement noir à chaque déplacement de la sélection.
- La tuile sélectionnée **pousse** ses voisines (marges animées) au lieu de passer par-dessus, et la rangée glisse pour la garder centrée.

## Manette (`src/lib/gamepad.ts`)

- API Gamepad, interrogée à chaque frame ; le clavier est branché en parallèle (flèches, Entrée, Échap).
- Seuils **asymétriques** : engagement à 0,65, relâchement à 0,40. Sans cette hystérésis, un stick qui traîne au repos fait défiler la sélection tout seul — c'est le bug qu'on a eu dans la version Godot.
- Maintenir une direction répète l'action après 350 ms, puis toutes les 120 ms.
- Les boutons ne déclenchent qu'au front montant : un appui = une action.
- `padLayout()` choisit la famille de glyphes d'après l'identifiant de la manette (formes PlayStation si Sony, lettres Xbox sinon). Les index des boutons, eux, ne changent jamais.

## Lancement d'un jeu

- Commande Rust `launch_game(program, args)` : démarre le processus et rend le PID.
- `is_running(pid)` dit quand la partie se termine (tasklist sous Windows, `/proc` ailleurs).
- Les jeux Steam se lancent par `steam -applaunch <appid>` : c'est Steam qui connaît les arguments.
- Hors application (simple onglet de navigateur), `play()` se contente de l'annoncer — le front reste utilisable pour juger le design.

## Fiches Steam (commande Rust `steam_details`)

- Les points d'entrée publics de Steam **ne renvoient pas d'en-tête CORS** : le webview ne peut pas les appeler. C'est Rust qui interroge `store.steampowered.com/api/appdetails`, et le résultat revient au front par `invoke`.
- La réponse est **mise en cache sur le disque**, une fiche par jeu (`<app data>/steam/<appid>.json`) : une fois récupérée, elle s'affiche même hors ligne. `refresh: true` force une nouvelle requête.
- Les jeux récents n'ont plus leurs images à l'ancien emplacement du CDN (`/steam/apps/<id>/...` répond 404) : `first_available()` teste les adresses candidates en HEAD et garde la première qui répond, en finissant par `header_image` donné par l'API. C'est ce qui a rattrapé les jaquettes manquantes.
- Côté front, `steam.svelte.ts` garde les fiches dans un `$state` : `ensureDetails(appid)` lance la récupération sans rien bloquer, et `coverOf` / `heroOf` prennent la valeur résolue dès qu'elle arrive.
- La fiche d'un jeu (genres, date, résumé, note Metacritic ramenée sur 5) vient de là aussi.

## Données de jeu

- `src/lib/data/games.json` : identifiant, titre, appid Steam, adresses de la jaquette et de l'artwork.
- Les images viennent du CDN public de Steam. Toutes les jaquettes verticales n'existent pas : on retombe sur `header.jpg` plutôt que d'afficher une case vide.
- Fiches (note, genres, date, résumé) : `store.steampowered.com/api/appdetails` ; recherche par titre : `steamcommunity.com/actions/SearchApps`. Aucun compte, aucune clé.
- Comparer les titres en **deux passes** : nom identique d'abord, ressemblance ensuite. Sinon « Hollow Knight » tombe sur « Hollow Knight: Silksong ».
- La note Metacritic est ramenée sur 5 (`score / 20`) et s'affiche en étoiles (icône Font Awesome dans `public/assets/icons/star.svg`). À 0, on n'affiche rien : une rangée éteinte ferait croire à une mauvaise note.

## Intégration système (dossier `system/`)

- `interface-console.sh` (installé en `/usr/local/bin/interface-console`) lance Gamescope en plein écran sur le binaire Tauri. Résolution, fréquence et chemin se règlent par variables d'environnement (`INTERFACE_CONSOLE_WIDTH`, `_HEIGHT`, `_REFRESH`, `_BIN`).
- `interface-console.service` prend `tty1` (`Conflicts=getty@tty1`), comme la session du Steam Deck. `Restart=on-failure` seulement : quitter l'interface doit ramener à un terminal, pas la relancer en boucle.
- `install.sh` copie le binaire dans `/opt/interface-console/`, écrit l'unité pour le bon utilisateur et recharge systemd. `autologin.conf` couvre la variante sans unité dédiée.
- Sous Linux, Tauri s'appuie sur WebKitGTK (`webkit2gtk-4.1`).
- Toujours prévoir une porte de sortie pour ne pas se bloquer hors du système pendant les tests (voir `system/README.md`).

## Commandes utiles

- Développement dans le navigateur : `npm run dev` puis http://localhost:5177
- Application plein écran : `npm run tauri dev`
- Vérifier le code sans rien lancer : `npx svelte-check --threshold error`
- Construire : `npm run build` (front) ou `npm run tauri build` (application)
- Capturer un écran sans manette — l'équivalent du `--capture` de la version Godot :
  ```
  chrome --headless=new --window-size=1920,1080 --virtual-time-budget=9000 \
    --screenshot=out.png "http://localhost:5177/?screen=detail&index=4"
  ```
  `?screen=home|detail` et `?index=N` ouvrent directement un état donné.

## Feuille de route

1. **Socle** : accueil (carrousel), fiche de jeu, navigation manette, lancement réel. — *fait*
2. **Bibliothèque** : grille, filtres (Tous / Favoris / Récemment joué), tri.
3. **Réglages** : profil (pseudo, photo parmi celles fournies), vidéo de démarrage, dossiers de jeux, système.
4. **Détection de jeux** : porter en Rust la détection Steam / Epic / raccourcis `.lnk` (algorithmes dans le commit de sauvegarde Godot), avec validation par l'utilisateur avant ajout.
5. **Fiches** : notes, genres, résumés et jaquettes récupérés automatiquement, en tâche de fond.
6. **Système** : build Linux, Gamescope, systemd, boot direct.
7. **Finitions** : vidéo d'introduction, son, écran de veille, gestion des erreurs.

## Règles de travail pour Claude

- Lire ce fichier avant toute modification et le tenir à jour si l'architecture change.
- Avancer étape par étape : une fonctionnalité à la fois, testable.
- Après chaque changement, lancer `npx svelte-check --threshold error` et, si le rendu bouge, une capture pour vérifier de ses yeux.
- Ne jamais supprimer de fichiers sans me le demander.
- Les visuels (rendu, animations, sensation manette) sont validés par moi : indiquer clairement ce que je dois tester.
- Répondre en français, de façon concise.
