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
│       ├── sounds/         # retours sonores (.wav)
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
- Dans une grille, **descendre depuis la dernière rangée ne fait rien**. Ramener la sélection sur la toute dernière tuile la faisait sauter en diagonale, à l'autre bout de l'écran.
- Transition entre écrans : `view-transition-name` partagé sur la jaquette. Le navigateur anime le déplacement, on ne mesure aucun rectangle à la main.
- Le voile posé sur un artwork est un dégradé (`Backdrop.svelte`) : lisible en bas, artwork préservé en haut. Sur une fiche, il s'appuie à gauche, là où se trouve le texte.
- L'artwork ne change qu'une fois la nouvelle image chargée : deux couches se relaient, sinon on verrait un clignotement noir à chaque déplacement de la sélection.
- Toute grille à défilement réserve `--hover-room` autour d'elle (marge négative + padding) : sans cette gouttière, l'agrandissement et le contour de la sélection se faisaient trancher par le `overflow: hidden` de la fenêtre.
- La tuile sélectionnée **pousse** ses voisines (marges animées) au lieu de passer par-dessus, et la rangée glisse pour la garder centrée.

## Hub (barre du haut, `TopBar.svelte`)

- Profil à gauche, puis les sections **écrites en toutes lettres** (Accueil · Bibliothèque · Recherche · Réglages), heure et manettes à droite. Les pastilles rondes d'icônes obligeaient à deviner, et ne disaient pas où l'on se trouvait.
- L'onglet courant est en blanc plein, souligné d'un trait d'accent dont la largeur s'anime d'un onglet à l'autre ; les autres restent gris.
- La barre s'efface (72 %) quand la sélection est descendue dans le contenu, et s'allume quand elle reprend la main : elle reste lisible sans tirer l'œil hors du jeu regardé.

## Manette (`src/lib/gamepad.ts`)

- API Gamepad, interrogée à chaque frame ; le clavier est branché en parallèle (flèches, Entrée, Échap).
- Seuils **asymétriques** : engagement à 0,65, relâchement à 0,40. Sans cette hystérésis, un stick qui traîne au repos fait défiler la sélection tout seul — c'est le bug qu'on a eu dans la version Godot.
- Maintenir une direction répète l'action après 350 ms, puis toutes les 120 ms.
- Les boutons ne déclenchent qu'au front montant : un appui = une action.
- **L1 / R1** (LB / RB) **ne changent pas de section** : on passe d'un onglet à l'autre par la barre du haut. Ils parcourent les catégories là où il y en a, c'est-à-dire les filtres de la bibliothèque. Au clavier : `PageUp` / `PageDown`, ou `A` / `E`.
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
- Dans « Changer la jaquette », les vraies jaquettes verticales viennent en tête, mais les images larges sont proposées ensuite : beaucoup de jeux (« Ballgame Demo ») n'ont **aucune** jaquette verticale chez Steam, et une fenêtre vide ne laisse aucun choix. L'aperçu montrant le recadrage réel, personne n'est surpris.
- Deux entrées distinctes dans le menu d'options : **« Changer la jaquette »** (la tuile) et **« Changer l'image de fond »** (l'artwork derrière). La même fenêtre sert aux deux (`target`), mais elle ne montre que des images comparables : verticales d'un côté, larges de l'autre, en aperçu 16/9. Changer le fond ne touche pas à la tuile.
- `ArtPicker.svelte` montre **tout ce qui existe** pour ce jeu — jaquettes et bannières Steam, Lutris, jusqu'à dix-huit grids SteamGridDB (commande Rust `art_candidates`). La grille affiche les vignettes ; seule l'image retenue est tirée en pleine taille.
- L'aperçu d'un candidat passe par **`Cover.svelte` lui-même** (prop `override`), dans une tuile au format, au rayon, à la légende et au contour de l'accueil : rien n'est reproduit à la main, donc rien ne peut diverger. L'aperçu charge l'image **pleine**, pas la miniature — une vignette au cadrage différent donnait une fausse idée du résultat sur les bannières.
- Rien ne se pose **sur** l'aperçu : pas d'étiquette de provenance en haut de la tuile, elle cachait une partie de la bannière qu'on est justement en train de juger.
- Le choix passe par `pick_game_art` : l'image est écrite sous un nom **horodaté** (`<id>-<kind>-<epoch>.<ext>`), les anciens fichiers de ce type sont effacés ensuite, et `artStyles[game.id]` retient le type choisi.
- L'horodatage n'est pas décoratif : **l'adresse doit changer**, sinon le webview resservait l'ancienne image depuis son cache et rien ne bougeait à l'écran. Un paramètre d'URL (`?v=…`) ne marche pas — le protocole d'accès aux fichiers le prend pour une partie du chemin, et l'image ne se charge plus du tout.
- `download_once` cherche donc un fichier existant **quel que soit son suffixe** (`art_files()`) : le choix de l'utilisateur est retrouvé tel quel, même après un vidage du stockage du navigateur.
- Le fichier local passe avant la fiche Steam dans `Cover.svelte`, sans quoi le choix serait recouvert.
- Les affiches sont rangées sous l'**identifiant du jeu**, jamais sous l'appid : un appid peut manquer, un id jamais.
- **Tout ce qui montre une jaquette passe par `Cover.svelte`** — tuiles, fenêtre de choix et fiche de jeu. La fiche lisait la jaquette de la fiche Steam : le choix de l'utilisateur n'y apparaissait pas, et un jeu sans jaquette chez Steam n'y montrait rien du tout.

## Jaquettes manquantes : SteamGridDB

- Les jeux récents n'ont **plus rien à l'ancien emplacement du CDN** (`/steam/apps/<id>/…` répond 404 pour toutes les images) : chaque visuel vit sous `store_item_assets` avec **son propre identifiant**, impossible à deviner. Seule la fiche du magasin (`appdetails`) les donne — `art_candidates` l'interroge donc systématiquement (`store_asset_candidates`). C'est le cas de « Ballgame Demo ».
- Dernier recours quand Steam puis Lutris ne donnent rien : `fetch_steamgriddb_art()` (recherche par titre, puis `grids` 600x900, `heroes`, `logos`).
- **La clé n'est jamais dans le code ni dans le dépôt** : elle est saisie dans Réglages → Jeux (« Clé SteamGridDB ») et vit dans `settings.json` du dossier de données (`steamgriddb_key`). Sans clé, la chaîne s'arrête simplement avant, comme aujourd'hui.
- L'interface ne réaffiche jamais la clé en entier : `Configurée ····<4 derniers caractères>`, suivi de son état.
- La clé est **essayée à la saisie** (`test_steamgriddb_key`, une simple recherche) : une faute de copie se voit tout de suite au lieu d'attendre le prochain jeu sans jaquette.
- SteamGridDB peut avoir **plusieurs fiches pour un même jeu** (deux entrées « Rhythia », une jaquette chacune) : on interroge toutes celles dont le titre correspond (`titles_match`), pas seulement la première. L'API ignore toute limite demandée, la troncature (24) se fait côté Rust.
- Quand **aucune** fiche ne correspond, on ne renvoie rien. Retomber sur le premier résultat proposait les jaquettes d'un autre jeu — « Ballgame Demo » se voyait offrir celles de « Bunnies & Ballgames! ».

## Menu d'options d'une tuile

- **X** sur l'accueil ouvre un panneau **dans la rangée**, à droite de la tuile sélectionnée : il pousse les tuiles suivantes au lieu de les recouvrir, en animant sa largeur. On voit donc toujours de quel jeu il s'agit.
- Entrées : favori, changer l'affiche, mettre à jour, vérifier les fichiers, désinstaller.
- Le panneau est **un tiroir de la tuile** : il reprend sa hauteur, son contour d'accent et ses coins, et se colle à son bord droit (marges négatives qui annulent l'espacement de la rangée). Tuile et panneau se lisent comme un seul bloc.
- Sur une **fiche de jeu**, il n'y a pas de tuile à prolonger : un troisième bouton « Options » (et la touche X) ouvre le même jeu d'actions dans `OptionsMenu.svelte`, avec des lignes identiques à celles du tiroir.
- Tout ce qui touche à l'installation est **confié à Steam** par un lien `steam://` (`install`, `validate`, `uninstall`), ouvert par la commande Rust `open_url` — qui n'accepte que ce protocole, pour ne pas devenir un moyen d'exécuter n'importe quoi depuis la page.

## Erreurs

- Les actions qui peuvent échouer (`play`, `runPower`, `steamActions`) renvoient un `Outcome` (`{ ok, message }`) plutôt qu'une chaîne : l'appelant sait alors si c'est une confirmation ou une erreur.
- `notify()` est le seul point d'affichage : bandeau rouge liseré + pastille, son `error`, et 6 s à l'écran au lieu de 3 — le temps de lire depuis un canapé.
- `window.onerror` et `unhandledrejection` alimentent le même bandeau : une erreur non rattrapée se voit au lieu de figer l'interface en silence (c'est ce qui avait donné un écran noir muet).
- Capture : `?notice=error`. Attention, le budget de temps virtuel de Chrome fait expirer les `setTimeout` — garder `--virtual-time-budget` sous la durée du bandeau.

## Sons

- Les signaux viennent de `public/assets/sounds/` (design PlayStation fourni) : `ps5-scroll` pour le déplacement, `ps5-selection-button` pour la validation, `ps5-back-button` pour le retour, `ps5-popup-2` pour le lancement d'un jeu.
- Les fichiers sont **décodés une fois** au démarrage (`preloadSounds()`) puis rejoués depuis la mémoire : un déplacement dans le carrousel ne doit pas attendre un chargement.
- L'**erreur** n'a pas de fichier : elle garde le signal grave de synthèse, qui ne ressemble à aucun autre son de l'interface. Cette synthèse sert aussi de secours si un fichier manque — mieux vaut un bip qu'une interface muette.
- Couper puis rallumer les sons ferme et rouvre le contexte audio : il faut alors redécoder (`preloadSounds()` à nouveau).

## Écran de veille

- Après `screensaver_minutes` sans aucune action (5 min par défaut, réglable dans Réglages → Apparence, `0` = jamais), `ScreenSaver.svelte` prend l'écran : artworks de la bibliothèque qui se relaient toutes les 12 s avec un lent panoramique, heure et date en bas à gauche.
- La première action **réveille seulement** : elle n'est pas transmise à l'écran en dessous, pour ne pas lancer un jeu en voulant rallumer l'écran.
- Pas de veille pendant la vidéo d'introduction, ni s'il n'y a aucun artwork à montrer.

## Réglages

- `saveSettings()` envoie **tous** les champs : la commande Rust réécrit le fichier entier et les champs absents y reprennent leur valeur par défaut. N'en envoyer qu'une partie effaçait silencieusement la clé SteamGridDB et la vidéo d'introduction au premier changement de pseudo.

## Données de jeu

- `src/lib/data/games.json` : identifiant, titre, appid Steam, adresses de la jaquette et de l'artwork.
- Les images viennent du CDN public de Steam. Toutes les jaquettes verticales n'existent pas : on retombe sur `header.jpg` plutôt que d'afficher une case vide.
- Fiches (note, genres, date, résumé) : `store.steampowered.com/api/appdetails` ; recherche par titre : `steamcommunity.com/actions/SearchApps`. Aucun compte, aucune clé.
- Comparer les titres en **deux passes** : nom identique d'abord, ressemblance ensuite. Sinon « Hollow Knight » tombe sur « Hollow Knight: Silksong ».
- La ressemblance passe par `titles_match()` : une simple inclusion ne suffit pas. « osu » est contenu dans des dizaines de noms et « Ball » dans « Golf Ballgame » — c'est ainsi qu'une jaquette se retrouvait sur le mauvais jeu. Il faut au moins cinq caractères et que le titre court fasse 70 % du long.
- Un exécutable générique (`game.exe`, `launcher.exe`, `start.exe`…) n'est **pas** utilisé comme variante de titre : le chercher revenait à tirer une jaquette au hasard.
- **Aucune source ne renvoie « le premier résultat venu »** : Lutris comme Steam passent par `titles_match`, y compris sur la réponse d'un slug direct (un slug peut tomber sur un homonyme). C'est la passe « premier jeu qui a une jaquette » de Lutris qui collait GOLF KEEPER sur osu!(lazer), la recherche « osu » y renvoyant n'importe quoi.
- La table statique d'appids (`match_steam_app`) ne se vérifie pas toute seule : elle contenait `osu → 1222440`, un jeu délisté dont les images CDN sont celles de GOLF KEEPER. Avant d'y ajouter une ligne, ouvrir `store.steampowered.com/app/<id>`.
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

## Recherche et clavier à l'écran

- L'écran reprend la mise en page de la bibliothèque (même titre, même grille de jaquettes) : on ne change pas de monde en appuyant sur Y. S'y ajoutent une **grande barre de saisie** en tête et le clavier juste en dessous.
- Le clavier est un composant à part (`Keyboard.svelte`), utilisé **aussi par la saisie des réglages** (`VirtualKeyboard.svelte`) : une touche a la même allure partout, et son style ne se règle qu'à un endroit. Les dispositions vivent dans `searchKeys.ts` (`SEARCH_ROWS` pour la recherche, `textKeyboardRows(caps)` pour les réglages).
- Disposition **AZERTY** : c'est celle que l'utilisateur a sous les doigts.
- Une touche sélectionnée **inverse ses couleurs**, sans agrandissement ni halo : sur une grille serrée, un agrandissement ferait sauter tout le clavier à chaque déplacement.
- Touches **grandes** (26 px) : un clavier de console se lit à trois mètres. Les touches qui n'écrivent pas (Espace, Effacer, Tout) sont larges, portent une icône, **et le glyphe du bouton manette qui fait la même chose** : le raccourci se lit sur la touche, pas dans une légende en bas de page.
- Sur une touche d'action, ce glyphe **prend la place de l'icône**, juste avant le mot : c'est le bouton qui compte, l'icône décorative n'apportait rien et décentrait la touche.
- L'écran de recherche a un **fond plein** : l'artwork derrière brouillait les lettres du clavier.
- Les rangées n'ont **pas toutes la même longueur** : la sélection se repère en `{ row, col }`, jamais par un index à plat, et `nearestColumn()` garde l'alignement horizontal en changeant de rangée.
- A tape, Y insère une espace, B efface une lettre — et quitte l'écran quand le champ est vide.
- Descendre sous la dernière rangée fait passer aux résultats : le clavier **se replie** (hauteur animée) et la grille récupère la place. Remonter depuis la première rangée de jaquettes le ramène.
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
7. **Finitions** : vidéo d'introduction, son, écran de veille, gestion des erreurs. — *fait*

## Règles de travail pour Claude

- Lire ce fichier avant toute modification et le tenir à jour si l'architecture change.
- Avancer étape par étape : une fonctionnalité à la fois, testable.
- Après chaque changement, lancer `npx svelte-check --threshold error` et, si le rendu bouge, une capture pour vérifier de ses yeux.
- Ne jamais supprimer de fichiers sans me le demander.
- Les visuels (rendu, animations, sensation manette) sont validés par moi : indiquer clairement ce que je dois tester.
- Répondre en français, de façon concise.
