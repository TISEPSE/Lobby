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
- **L1 / R1** (LB / RB) passent d'un onglet à l'autre sans remonter dans la barre. Au clavier : `PageUp` / `PageDown`, ou `A` / `E`.
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

## Jaquettes

- **Jamais de bannière 16/9 étirée dans une tuile 2/3** : c'est laid et ça coupe les titres. `steam_details` ne renvoie dans `cover` qu'une **vraie jaquette verticale** (`library_600x900`) ; sinon le champ reste vide.
- Sans jaquette, `Cover.svelte` en **compose** une : l'artwork du jeu en fond assombri, le logo détouré par-dessus (`logo.png` du CDN quand il existe), et à défaut le titre. Le résultat reste au format d'une tuile.
- L'utilisateur peut changer l'affiche d'un jeu (menu d'options d'une tuile) : jaquette, artwork ou bannière. Le choix est gardé par jeu (`artStyles`).

## Jaquettes manquantes : SteamGridDB

- Dernier recours quand Steam puis Lutris ne donnent rien : `fetch_steamgriddb_art()` (recherche par titre, puis `grids` 600x900, `heroes`, `logos`).
- **La clé n'est jamais dans le code ni dans le dépôt** : elle est saisie dans Réglages → Jeux (« Clé SteamGridDB ») et vit dans `settings.json` du dossier de données (`steamgriddb_key`). Sans clé, la chaîne s'arrête simplement avant, comme aujourd'hui.
- L'interface ne réaffiche jamais la clé en entier : `Configurée ····<4 derniers caractères>`.

## Menu d'options d'une tuile

- **X** sur l'accueil ouvre un panneau **dans la rangée**, à droite de la tuile sélectionnée : il pousse les tuiles suivantes au lieu de les recouvrir, en animant sa largeur. On voit donc toujours de quel jeu il s'agit.
- Entrées : favori, changer l'affiche, mettre à jour, vérifier les fichiers, désinstaller.
- Le panneau est **un tiroir de la tuile** : il reprend sa hauteur, son contour d'accent et ses coins, et se colle à son bord droit (marges négatives qui annulent l'espacement de la rangée). Tuile et panneau se lisent comme un seul bloc.
- Tout ce qui touche à l'installation est **confié à Steam** par un lien `steam://` (`install`, `validate`, `uninstall`), ouvert par la commande Rust `open_url` — qui n'accepte que ce protocole, pour ne pas devenir un moyen d'exécuter n'importe quoi depuis la page.

## Écran de veille

- Après `screensaver_minutes` sans aucune action (5 min par défaut, réglable dans Réglages → Apparence, `0` = jamais), `ScreenSaver.svelte` prend l'écran : artworks de la bibliothèque qui se relaient toutes les 12 s avec un lent panoramique, heure et date en bas à gauche.
- La première action **réveille seulement** : elle n'est pas transmise à l'écran en dessous, pour ne pas lancer un jeu en voulant rallumer l'écran.
- Pas de veille pendant la vidéo d'introduction, ni s'il n'y a aucun artwork à montrer.

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

## Recherche

- Écran dédié, sans modale : le clavier reste affiché à gauche, les résultats à droite se mettent à jour à chaque lettre.
- A tape, Y insère une espace, B efface une lettre — et quitte l'écran quand le champ est vide.
- Le passage clavier ↔ résultats se fait au bord (à droite depuis la dernière colonne, à gauche depuis la première tuile).
- Comparaison via `normalizeForSearch` : sans accents ni ponctuation, « repo » trouve « R.E.P.O. ».
- La hauteur de la fenêtre de résultats est en **unités d'écran** : un pourcentage à l'intérieur d'une variable CSS se résout contre la hauteur du parent, pas sa largeur — le calcul partait faux.

## Vidéo d'introduction

- Les vidéos sont dans `public/assets/boot/` au format **.webm** (le web le lit nativement ; l'Ogg Theora était une contrainte de Godot).
- `BootVideo.svelte` la joue au lancement par-dessus l'interface déjà construite derrière. N'importe quelle touche la passe, et une vidéo illisible enchaîne directement sur l'accueil plutôt que de laisser un écran noir.
- Réglages → Apparence : choix de la vidéo et activation (`boot_video`, `boot_video_enabled`, persistés côté Rust).
- `?boot=0` la saute — utile pour les captures.

## Feuille de route

1. **Socle** : accueil (carrousel), fiche de jeu, navigation manette, lancement réel. — *fait*
2. **Bibliothèque** : grille, filtres (Tous / Favoris / Récemment joué), tri. — *fait*
2b. **Recherche** : clavier à l'écran et résultats filtrés à la frappe. — *fait*
3. **Réglages** : profil (pseudo, photo parmi celles fournies), dossiers de jeux, système. — *fait*
4. **Détection de jeux** : détection Steam / Epic / dossiers de jeux / raccourcis `.lnk` en Rust avec validation utilisateur. — *fait*
5. **Fiches** : notes, genres, résumés et jaquettes récupérés automatiquement — *fait*. Les visuels sont **téléchargés une fois** dans `<app data>/artwork/` (`cache_game_art`) : l'interface lit un fichier, pas une adresse web, donc l'association jeu ↔ jaquette ne peut plus changer et tout s'affiche hors ligne.
6. **Système** : build Linux, Gamescope, systemd, boot direct.
7. **Finitions** : vidéo d'introduction, son, écran de veille — *faits* ; reste la gestion des erreurs.

## Règles de travail pour Claude

- Lire ce fichier avant toute modification et le tenir à jour si l'architecture change.
- Avancer étape par étape : une fonctionnalité à la fois, testable.
- Après chaque changement, lancer `npx svelte-check --threshold error` et, si le rendu bouge, une capture pour vérifier de ses yeux.
- Ne jamais supprimer de fichiers sans me le demander.
- Les visuels (rendu, animations, sensation manette) sont validés par moi : indiquer clairement ce que je dois tester.
- Répondre en français, de façon concise.
