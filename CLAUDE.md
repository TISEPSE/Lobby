# Lobby (Interface Console)

**Lobby** est le nom de l'application (fenêtre, exécutable, installeur) ; « Interface Console » reste le nom du dépôt. L'identifiant `fr.interface.console` ne change pas : le dossier de données (réglages, sessions chiffrées, jaquettes) reste le même.

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

- Le rendu est du web : la direction artistique vit dans le CSS, pas dans du code.
- Cible : Linux (Arch / Bazzite), Wayland via Gamescope. Développement sous Windows (WebView2), tout doit rester portable.
- **Aucune clé d'API dans le code ni le dépôt** : jaquettes et fiches viennent des points d'entrée publics de Steam. La seule clé (SteamGridDB, facultative) est **saisie par l'utilisateur** et ne vit que dans `settings.json`. Steam et Epic passent par une connexion au compte, jamais par une clé.

### Pourquoi pas Godot

Le projet a d'abord été écrit en Godot 4 / GDScript. Tout est conservé dans l'historique git (commit « Sauvegarde de la version Godot avant bascule sur Tauri ») : écrans, thème, détection de jeux, lecteur `.lnk`, métadonnées Steam, intégration Gamescope. La bascule a eu lieu parce que chaque évolution visuelle y coûtait un `StyleBoxFlat`, des offsets mesurés à la main et un cycle import/relance, là où le même changement tient en trois lignes de CSS. **Pour retrouver un algorithme (détection Steam/Epic, parseur `.lnk`, seuils manette), lire le commit de sauvegarde plutôt que de le réinventer.**

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
- Transition vers une fiche : `startViewTransition` (fondu), le dock garde son propre nom pour ne pas clignoter. La fiche n'a plus de jaquette (maquette) : plus de jaquette partagée à animer.
- **Changer de section n'utilise pas `startViewTransition`** : il photographiait toute la page, dock flouté compris, et le fondu saccadait. Le contenu entre seul (`.screen`, `{#key section}` : fondu court + léger glissement), le dock ne bouge pas. Les view transitions restent pour la fiche (jaquette partagée), et le dock y porte son propre nom (`view-transition-name: dock`) pour ne pas clignoter.
- Le voile posé sur un artwork est un dégradé (`Backdrop.svelte`) : lisible en bas, artwork préservé en haut. Sur une fiche, il s'appuie à gauche, là où se trouve le texte.
- L'artwork ne change qu'une fois la nouvelle image chargée : deux couches se relaient, sinon on verrait un clignotement noir à chaque déplacement de la sélection.
- Toute grille à défilement réserve `--hover-room` autour d'elle (marge négative + padding) : sans cette gouttière, l'agrandissement et le contour de la sélection se faisaient trancher par le `overflow: hidden` de la fenêtre.
- La tuile sélectionnée **pousse** ses voisines (marges animées) au lieu de passer par-dessus, et la rangée glisse pour la garder centrée.

## Hub (dock du haut, `TopBar.svelte`)

- Le champ de recherche annonce le nombre de jeux **de toute la bibliothèque** (`allGames` : installés et possédés), comme la recherche elle-même.
- **Dock façon Xbox** (`--topbar-height` 76 px, boutons de 40 px, **centré à la largeur de son contenu** — étiré d'un bord à l'autre, il barrait tout l'écran ; variables `--dock-*`) : pilule translucide floutée. À gauche Accueil et Bibliothèque, au centre le **champ de recherche** (« Rechercher parmi N jeux », glyphe Y posé dessus), à droite Réglages puis le **Profil** (la photo). **L'heure et les manettes sont hors du dock**, dans le coin haut droit de l'écran : ce ne sont pas des sections. Les glyphes **LB / RB** (L1 / R1) encadrent le dock.
- **On ne circule dans le dock qu'avec L1 / R1** : la sélection ne monte jamais dessus, elle reste dans le contenu. Monter depuis le haut d'un écran ne fait rien. Pas de bouclage aux extrémités. Ordre : Accueil · Bibliothèque · Réglages · Profil. La recherche n'est **pas** une étape : c'est une fenêtre (Y, ou clic sur le champ).
- Le dock n'a donc pas d'état « sélectionné » : la section courante est une **pilule claire** (`--dock-active`) qui affiche son nom, sans contour d'accent — le contour reste réservé à la sélection, dans le contenu.
- **Boutons toujours ouverts** : chaque bouton montre en permanence son icône **et son nom** (le profil : photo et pseudo). Rien ne s'ouvre ni ne se ferme au changement de section — l'ancien nom qui se dépliait sur la section courante donnait une navigation peu lisible. Le dock garde donc toujours la même taille.
- **Survol** (`--dock-hover`) : la pilule s'éclaire, le texte passe en blanc, le bouton se soulève d'un pixel ; un appui l'enfonce légèrement. La section courante garde sa pilule claire (`--dock-active`).

## Manette (`src/lib/gamepad.ts`)

- API Gamepad, interrogée à chaque frame ; le clavier est branché en parallèle (flèches, Entrée, Échap).
- Seuils **asymétriques** : engagement à 0,65, relâchement à 0,40. Sans cette hystérésis, un stick qui traîne au repos fait défiler la sélection tout seul — c'est le bug qu'on a eu dans la version Godot.
- Maintenir une direction répète l'action après 350 ms, puis toutes les 120 ms.
- Les boutons ne déclenchent qu'au front montant : un appui = une action.
- **L1 / R1** (LB / RB) : section précédente / suivante du dock, et rien d'autre (`prev` / `next`). Au clavier : `A` / `E`. Un léger **souffle** (`section`, bruit filtré synthétisé par `playWhoosh`, famille « Menus ») accompagne le changement ; au bout du dock, rien.
- **L2 / R2** (LT / RT) : catégories de l'écran — filtres de la bibliothèque, périodes des statistiques (`pagePrev` / `pageNext`). Au clavier : `PageUp` / `PageDown`.
- **Y** ouvre la recherche de partout (hors fenêtres). **View / Create** (bouton 8, action `view`, clavier `Tab`) : le tri de la bibliothèque.
- Les glyphes viennent de `glyphs.ts`, partagé par la barre d'aide, le dock et `Glyph.svelte` (glyphe posé sur un élément : pastille Sync, périodes) ; `xbox/lt.svg` et `xbox/rt.svg` ont été dessinés sur le modèle de `lb.svg`.
- Les directions ont leurs **propres glyphes** (`up`, `down`, `left`, `right` → `buttons/dpad_<dir>.svg` : la croix, branche concernée allumée), communs aux deux familles — plutôt que des ▲ ▼ en texte.
- `padLayout()` choisit la famille de glyphes d'après l'identifiant de la manette (formes PlayStation si Sony, lettres Xbox sinon). Les index des boutons, eux, ne changent jamais.
- **Notification de manette** (`PadToast.svelte`), façon Xbox : sur `gamepadconnected` / `gamepaddisconnected`, un rond d'accent portant la manette surgit en bas au centre (à hauteur de la barre d'aide, sans cacher les jaquettes), puis la pilule s'ouvre : « Manette connectée », nom (`padName()` : DualSense, DualShock 4, Xbox, Switch Pro, 8BitDo…) et « Joueur N ». Débranchée, le rond s'éteint. Son `pad`, 3,6 s à l'écran. La **sortie est l'apparition à l'envers** (`--toast-stay`) : le texte s'efface, la pilule se referme sur le rond, puis le rond rétrécit et disparaît. Une même manette s'annonce souvent **plusieurs fois d'un coup** (XInput + HID, manettes virtuelles de Steam Input) — on en a eu trois notifications à la fois : les annonces d'une même seconde (`BURST`) n'en donnent qu'**une**, au nom le plus parlant, et une nouvelle remplace celle à l'écran (`?pad=triple` le vérifie). Variables `--toast-*`. Le navigateur n'annonce une manette qu'après un premier appui sur l'une de ses touches. Capture : `?pad=xbox|ps5`.

## Fenêtre

- **Mise à l'échelle de l'écran** (`fit_to_screen`, `lib.rs`) : l'interface est dessinée pour du 1920 × 1080 (`DESIGN_WIDTH` / `DESIGN_HEIGHT`) ; le zoom du webview vaut min(largeur / 1920, hauteur / 1080) en pixels logiques, recalculé à chaque redimensionnement. Sur un portable, « Rechercher parmi N jeux » passait à la ligne ; sur une TV 4K, tout était minuscule. Zoom **du navigateur** (`set_zoom`), pas `zoom` CSS : la page voit 1920 × 1080 pixels CSS et `vw` / `vh` restent justes.

- Démarrage en **plein écran sans bordure** (`fullscreen: true`, `decorations: false` dans `tauri.conf.json`).
- **Pas de pointeur** : `set_cursor_visible(false)` sur la fenêtre au démarrage, et `cursor: none !important` sur tout élément (des boutons déclaraient `cursor: pointer` et faisaient réapparaître la main).
- Porte de sortie : **F11** ou Réglages → Système → Affichage bascule vers une fenêtre classique avec sa barre de titre (`toggle_fullscreen`, bordures réglées *avant* le plein écran).

## Lancement d'un jeu

- Commande Rust `launch_game(program, args)` : démarre le processus et rend le PID.
- `is_running(pid)` dit quand la partie se termine (tasklist sous Windows, `/proc` ailleurs).
- Les jeux Steam se lancent par `steam -applaunch <appid>` : c'est Steam qui connaît les arguments.
- **Temps de jeu Steam** : `steam -applaunch` rend la main aussitôt, son processus ne dit rien. `watchSteam` interroge `steam_running_app` toutes les 3 s — l'appid du jeu en cours selon Steam (`RunningAppID` dans le registre sous Windows, `~/.steam/registry.vdf` sous Linux, testé) : la partie commence quand Steam annonce notre jeu, finit quand il ne l'annonce plus, et entre dans le journal (`recordSession`). Dix minutes sans démarrage (mise à jour, annulation) : on abandonne.
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
- **Tout ce qui montre une jaquette passe par `Cover.svelte`** — tuiles et fenêtre de choix (la fiche de jeu n'en montre plus). La fiche lisait la jaquette de la fiche Steam : le choix de l'utilisateur n'y apparaissait pas, et un jeu sans jaquette chez Steam n'y montrait rien du tout.

## Jaquettes manquantes : SteamGridDB

- Les jeux récents n'ont **plus rien à l'ancien emplacement du CDN** (`/steam/apps/<id>/…` répond 404 pour toutes les images) : chaque visuel vit sous `store_item_assets` avec **son propre identifiant**, impossible à deviner. Seule la fiche du magasin (`appdetails`) les donne — `art_candidates` l'interroge donc systématiquement (`store_asset_candidates`). C'est le cas de « Ballgame Demo ».
- Dernier recours quand Steam puis Lutris ne donnent rien : `fetch_steamgriddb_art()` (recherche par titre, puis `grids` 600x900, `heroes`, `logos`).
- **La clé n'est jamais dans le code ni dans le dépôt** : elle est saisie dans Réglages → Jeux (« Clé SteamGridDB ») et vit dans `settings.json` du dossier de données (`steamgriddb_key`). Sans clé, la chaîne s'arrête simplement avant, comme aujourd'hui.
- L'interface ne réaffiche jamais la clé en entier : `Configurée ····<4 derniers caractères>`, suivi de son état.
- La clé est **essayée à la saisie** (`test_steamgriddb_key`, une simple recherche) : une faute de copie se voit tout de suite au lieu d'attendre le prochain jeu sans jaquette.
- SteamGridDB peut avoir **plusieurs fiches pour un même jeu** (deux entrées « Rhythia », une jaquette chacune) : on interroge toutes celles dont le titre correspond (`titles_match`), pas seulement la première. L'API ignore toute limite demandée, la troncature (24) se fait côté Rust.
- Quand **aucune** fiche ne correspond, on ne renvoie rien. Retomber sur le premier résultat proposait les jaquettes d'un autre jeu — « Ballgame Demo » se voyait offrir celles de « Bunnies & Ballgames! ».

## Compte Epic Games (`epic_account.rs`, `epicAccount.svelte.ts`)

- Epic **ne garde pas le temps de jeu sur le disque** : il faut le demander à ses serveurs. Méthode des launchers libres (Legendary, Heroic) : `epic_login` ouvre une fenêtre sur la **page de connexion officielle** d'Epic (l'interface ne voit jamais le mot de passe) ; la page finale affiche un code en JSON, `on_page_load` le relit et navigue vers `https://epic-code.invalid/?code=…`, que `on_navigation` intercepte ; le code est échangé contre un jeton (`eg1`), et seul le **jeton de renouvellement** est gardé (`<app data>/epic.json`).
- `epic_login` est **asynchrone** : sous Windows, créer une fenêtre depuis une commande synchrone (fil principal) peut bloquer l'application — c'est pour ça que la première version n'ouvrait rien.
- Le code n'est **pas lu par `JSON.parse`** : le visualiseur JSON de WebView2 ajoute son propre texte autour. On le cherche par expression régulière (`"authorizationCode": "…"`), en réessayant quelques secondes.
- Fermer la fenêtre sans se connecter envoie `epic-login` avec « connexion annulée » : l'interface ne reste pas bloquée sur « Connexion… ». Chaque étape laisse une trace dans le journal (`Epic : …`).
- Le fournisseur ferme sa pop-up par `window.close()`, que Tauri ne relayait pas : la fenêtre restait **blanche et impossible à fermer**, au-dessus de tout, jusqu'à la fin de la connexion Epic. Un script injecté remplace `close()` par une navigation vers `https://epic-popup-close.invalid/`, interceptée → la pop-up est détruite. Elle garde sa barre de titre (`decorations`, `closable`).
- **« Autres méthodes de connexion »** (Google, Xbox, PlayStation, Steam…) ouvrent une pop-up (`window.open`), que Tauri **refuse par défaut** — rien ne se passait. `on_new_window` crée une vraie fenêtre (`NewWindowResponse::Create`, `window_features`) : même environnement WebView2, donc `window.opener` fonctionne et la pop-up rend la main à Epic. Fermer la fenêtre de connexion ferme aussi les pop-ups (`epic-popup-<n>`).
- La page finale d'Epic peut se **charger plusieurs fois** : seul le **premier** code compte (`done.swap`, et `window.__epicCodeSent` côté page). Un code ne s'échange qu'une fois — les doublons étaient refusés (400) et affichaient des erreurs alors que la connexion avait réussi. Dès la fin, la fenêtre de connexion **et** les pop-ups des fournisseurs sont détruites (`close_login_windows`).
- La session Epic (jeton de renouvellement) est **chiffrée** sur le disque (`epic.session`, `secure_store`) ; l'ancien `epic.json` en clair est converti puis supprimé à la première lecture.
- Client id / secret : ceux du launcher Epic lui-même, publiés par ces projets — pas une clé de l'utilisateur.
- `epic_account` renouvelle la session à chaque lecture puis lit `library-service …/playtime/account/<id>/all` : temps de jeu par `artifactId`, qui est l'`AppName` des manifestes — d'où l'identifiant `epic-<appname>` des jeux Epic. `playtimeOf` prend le plus grand de nos mesures, de Steam et d'Epic.
- Réglages → Profil → « Compte Epic Games » : se connecter, actualiser, ou se reconnecter si la session a expiré ; une ligne en dessous déconnecte. Le résultat de la connexion arrive par l'événement `epic-login`.
- **Bibliothèque complète** : `epic_account` lit aussi toute la bibliothèque (`library-service …/items`, paginée par `cursor`), garde les applications publiques, puis demande au **catalogue** (`catalog-public-service …/bulk/items`) titre, catégories et jaquettes (`DieselGameBoxTall` verticale, `DieselGameBox` large). Seuls les **jeux** restent (catégorie `games`, pas de `mainGameItem` : pas de DLC). Les fiches du catalogue sont en **cache chiffré** (`epic.catalog`) : la première lecture prend une trentaine de secondes pour ~550 jeux, les suivantes ne demandent que les nouveaux. Huit requêtes de catalogue à la fois.
- Les jeux Epic non installés (`uninstalledEpicGames`, `epic-<appname>`, `installed: false`) rejoignent « Tous » comme ceux de Steam, avec la jaquette du catalogue (pas de recherche d'affiche pour eux, `Cover.svelte`). Un jeu déjà installé n'est pas doublé (identifiant ou titre). « Installer » ouvre `com.epicgames.launcher://apps/<AppName>?action=install`.
- `epicMinutesOf` ne regarde que l'identifiant : un jeu non installé n'est pas dans `games`. Le **Profil et les Statistiques reçoivent `allGames`** (installés + possédés Steam et Epic) : sans ça, 1 450 h de Fortnite non installé n'apparaissaient nulle part.
- Un jeu Epic repéré seulement par son dossier (`.egstore`, sans `.mancpn` lisible) a un identifiant tiré du titre (`epic-rocketleague`), pas du nom interne (`Sugar`) : `epicMinutesOf` le retrouve alors **par son titre** dans la bibliothèque du compte (même normalisation que `normalize()` côté Rust).

## Profil (`Profile.svelte`)

- **Sa propre page**, dernière section du dock (la photo), séparée des Réglages : tout ce qui parle de toi est ici — identité, comptes, statistiques.
- Façon Xbox : à gauche la **carte d'identité** ; à droite le **temps de jeu total** et l'activité mois par mois, **les plus joués** (jaquettes), genres favoris et boutiques en pourcentage du temps.
- **Pas de bouton « Modifier »** : la **photo** et le **pseudo** se sélectionnent eux-mêmes au joystick. A sur la photo → `AvatarPicker` ; A sur le pseudo → `VirtualKeyboard` (fenêtre de l'application, `nameKeyboardOpen`).
- Les tuiles de compte portent le **logo de la boutique** (`icons/steam.svg`, `icons/epic.svg`, tirés de Simple Icons, licence CC0, passés en blanc) dans une pastille ronde ; la photo du compte Steam s'y accroche en médaillon.
- Puis les tuiles **Comptes** : **Steam** — une seule tuile pour le compte **et** sa bibliothèque (A se connecte ; connectée, plus de « Synchroniser » : X déconnecte (oublie la liste) ; à la première connexion, si le pseudo est encore « Joueur », pseudo et photo Steam sont repris) —, Epic Games (A se connecte, ou se reconnecte si la session a expiré — plus d'« Actualiser », le compte est relu à chaque démarrage ; X déconnecte), et **Statistiques détaillées**. Parcours haut / bas : photo → pseudo → Steam → Epic → Statistiques.
- **Jamais de photo carrée** : partout (dock, profil, `AvatarPicker`) l'image est ronde et remplit son cercle (`object-fit: cover`), et le contour de sélection de la photo est un anneau, pas un cadre.
- Les chiffres viennent de `playtimeOf` (nos mesures + Steam + Epic), pas du journal. L'activité mensuelle, elle, vient du journal.

## Secrets sur le disque (`secure_store.rs`)

- Tout secret gardé sur le disque passe par `secure_store::write` / `read`. Sous Windows : **DPAPI** (`CryptProtectData`, via `windows-sys` déjà tiré par Tauri) — le fichier n'est lisible que par le même compte Windows sur le même PC. Sous Linux (session Gamescope, sans coffre garanti) : fichier en droits `600`, comme Steam et Heroic.
- Un test vérifie qu'un secret écrit n'apparaît pas en clair dans le fichier. `wipe()` efface un secret de la mémoire (écriture volatile) avant de le libérer.

## Compte Steam (`steam_account.rs`, `steamAccount.svelte.ts`)

- **Aucune clé, aucun mot de passe** : le compte est lu dans les fichiers du client Steam. `config/loginusers.vdf` donne le compte (marqué `MostRecent`, sinon `AutoLogin`, sinon le plus récent), `config/avatarcache/<steamid>.png` sa photo (copiée dans le dossier de données, seul endroit lisible par le webview), et `userdata/<steamid − 76561197960265728>/config/localconfig.vdf` la date de dernière partie et le temps de jeu de **chaque jeu joué**.
- Seul le bloc `Software/Valve/Steam/apps` de `localconfig.vdf` compte : d'autres blocs `apps` y ont un tout autre sens.
- `lastPlayedAt(id)` et `playtimeOf(id)` (dans `library.svelte.ts`) combinent nos mesures et celles de Steam : la date la plus récente, le temps le plus grand. C'est ce qui donne enfin un temps de jeu aux jeux Steam (lancés par `steam -applaunch`, ils échappent à notre mesure) et l'ordre « dernière partie » même pour un jeu lancé depuis Steam.
- Tests : `cargo test --lib steam_account` ; `cargo test dump_account -- --ignored --nocapture` affiche le compte de la machine.
- **Bibliothèque complète, par connexion au compte (pas de clé d'API)** — `steam_library.rs`. Steam n'a pas d'OAuth pour les tiers (OpenID ne dit que *qui* on est) et ne donne plus la liste des jeux d'un profil sans être connecté. Comme pour Epic, Profil → tuile « Steam » ouvre la **page de connexion officielle** (QR code de l'application mobile, ou identifiants), Dès que Steam quitte la page de connexion (connexion réussie), `on_navigation` **bloque la page suivante au lieu de l'afficher** et cache la fenêtre : rien d'autre ne s'ouvre à l'écran, la liste se lit en arrière-plan. (Avant, la page « Jeux » du site s'affichait pendant la lecture — inutile et déroutant.) La liste n'est plus écrite dans les pages de Steam, elle vient de l'API officielle. `fetch_games` essaie donc, dans l'ordre : **`IPlayerService/GetOwnedGames` avec le jeton d'accès de la session** (seconde moitié de `steamLoginSecure`, sans clé d'API), puis avec le jeton que la boutique donne à la session (`pointssummary/ajaxgetasyncconfig` → `webapi_token`), puis l'ancienne page (`data-profile-gameslist`), puis les seuls identifiants (`dynamicstore/userdata` → `rgOwnedApps`, noms repris des fiches). Chaque échec laisse une trace sans secret dans le journal (`Steam : …`).
- **Sécurité** — la session Steam donne un accès complet au compte sur le web, c'est le secret le plus sensible de l'application :
  - fenêtre en **navigation privée** (`incognito`) : rien n'est écrit sur le disque par le navigateur, tout disparaît à la fermeture ;
  - navigation **limitée à Steam en HTTPS** (`steamcommunity.com`, `*.steampowered.com`, `*.steamstatic.com`, testé contre les faux domaines), **aucune pop-up** ;
  - le cookie `steamLoginSecure` est lu **une seule fois, en mémoire** (`cookies_for_url`, dans une tâche à part : sous Windows, la lecture bloque dans un gestionnaire d'événement), envoyé seulement aux serveurs de Steam (`api.steampowered.com`, `store.steampowered.com`, `steamcommunity.com`, client `https_only`), puis **effacé de la mémoire** (`secure_store::wipe`). Jamais enregistré, jamais transmis à l'interface, jamais journalisé ;
  - seule la **liste des jeux** est gardée, **chiffrée** (`steam/library.bin`, `secure_store`). Pour l'actualiser (nouvel achat), on se reconnecte ; X sur la tuile l'oublie.
- Les jeux possédés mais pas installés (`uninstalledSteamGames`, `installed: false`) **ne sont jamais enregistrés** dans la bibliothèque : ils se recalculent de la liste Steam et disparaissent une fois installés et détectés. Ils sont **mélangés dans « Tous »** (`allGames`, et dans la recherche), grisés avec un badge « Non installé » ; leur fiche propose **« Installer »** (`steam://install/<appid>`), leurs options n'offrent pas mise à jour ni désinstallation. L'accueil, lui, ne montre que les jeux installés.
- Les requêtes vers Steam (fiches, affiches) passent par une **file de quatre** (`queued` dans `steam.svelte.ts`) : la grille peut montrer des centaines de jeux d'un coup.

## Panneaux de l'accueil (`HomePanels.svelte`)

- Sous la rangée, trois panneaux pour une page vivante (maquette de l'utilisateur) : **Vos lanceurs** (jeux installés par boutique, `platformOf`, cinq tuiles au plus dont « Autres » ; en pied, la dernière lecture de la bibliothèque Steam), **Cette semaine** (temps de jeu du lundi au dimanche d'après le journal, `weekDays()` dans `stats.ts`, aujourd'hui en accent, total en tête), **Mises à jour** (téléchargements Steam en cours, `downloads`, « Prête » / pourcentage / « En attente »). Variables `--home-gap`, `--panel-*`.
- **Bas** depuis la rangée descend dans les panneaux (`homeZone: 'panels'`), gauche / droite entre eux, haut remonte. A : Bibliothèque, Statistiques, ou la fiche du jeu en cours de mise à jour. La rangée n'a alors plus de contour : une seule sélection à l'écran.
- La ligne sous le titre dit, pour la carte comme pour une tuile : dernière partie (ou « Jamais joué »), temps de jeu, boutique.
- Sur l'accueil, la barre de téléchargement globale (`DownloadBar`) est masquée : le panneau « Mises à jour » la remplace, et elle le chevauchait.
- Capture : `?resume=demo&demo-download=1&stats=demo` (journal fictif), `&zone=panels&panel=N`.

## Ordre de l'accueil

- La rangée suit `home_order` (Réglages → Apparence) : **dernière partie d'abord** par défaut (les jamais joués ensuite, par titre), ou par titre. Persisté côté Rust (`home_order`, `default_home_order`).

## Carte « Reprendre » (accueil)

- En tête de la rangée, à l'index **-1**, une carte couchée (16/9, à la hauteur des tuiles, `--resume-width`) montre le dernier jeu lancé. **A le lance directement**, sans passer par sa fiche ; X ouvre le même tiroir d'options qu'une tuile.
- Le jeu de la carte **n'est pas répété** dans la rangée (`homeGames` l'exclut) : deux fois le même jeu côte à côte n'avait pas de sens.
- L'accueil **démarre sur cette carte** : le dernier jeu se relance en un appui dès l'allumage. Sans jeu à reprendre, la carte n'existe pas et la sélection part de la première tuile (une fois la bibliothèque chargée, `libraryReady`).
- Sur la carte, la rangée s'aligne sur la marge de gauche (`--safe-x`) au lieu de se centrer : centrée, elle laissait un grand vide à sa gauche.
- `lastPlayed` est posé **au lancement** (`markLaunched`), pas à la fin de la partie : pour un jeu Steam, le processus rend la main aussitôt et la carte ne l'aurait jamais montré.
- Capture : `?resume=demo` invente un jeu à reprendre.

## Fiche d'un jeu (`Detail.svelte`)

- D'après la maquette de l'utilisateur (sans la rangée de jeux ni les boutons ronds du bas) : à gauche, la **boutique** en petites capitales d'accent, le **titre en très grand**, un **résumé de trois lignes**, **trois chiffres** (temps de jeu, dernière partie, note en étoiles — ou la sortie sans note), puis **JOUER** (pilule d'accent, « Installer » pour un jeu non installé) · **Détails du jeu** (descend vers « Captures et vidéos » et « Plus sur… ») · **Options** (favori compris). Pas de jaquette : l'artwork occupe le fond.
- Le fond a son propre voile (`Backdrop`, `detail`) : sombre sous le texte, l'artwork presque intact à droite. La page « Captures et vidéos » reprend le voile sombre.
- La sélection d'un bouton l'agrandit ; JOUER garde son aplat d'accent (`--detail-button-focus` pour les autres).
- Pièges de nommage dans ce composant : `.play` est déjà l'icône de lecture des diapositives (JOUER est `.cta`), et `dl` est stylé pour le panneau « Plus sur… » (les chiffres sont des `div`).

## Fiche : captures et vidéos

- La fiche a **deux pages l'une sous l'autre** : la présentation, puis « Captures et vidéos ». Descendre depuis les boutons fait glisser la seconde (une page entière, `translateY(-100%)`) ; haut (ou B) revient. Un repère « Captures et vidéos ▾ » en bas dit qu'il y a une suite.
- **Slider horizontal centré** (12 médias au plus, `mediaOf()` : jusqu'à trois bandes-annonces d'abord, avec un bouton de lecture, puis les captures). Le ruban (`.reel`, sur toute la largeur de l'écran) se décale pour que la sélection tombe pile au centre (`--slide-width`, `--slide-gap`, `--slide-duration`) ; la sélection est à pleine taille avec le contour d'accent, ses voisines plus petites et estompées débordent sur les bords. Gauche / droite pour parcourir, position « 3 / 12 » et points en dessous.
- **Tout est préchargé et décodé** à l'ouverture de la fiche (`Image.decode()`), en pleine taille : rien ne se charge sous les yeux en faisant défiler, et chaque image n'apparaît qu'une fois prête (fondu). La visionneuse s'ouvre aussitôt.
- Pas de classe `.track` pour le ruban : c'est déjà la barre de progression d'un téléchargement (8 px, contenu masqué), qui écrasait le slider.
- Sous le slider, le panneau « Plus sur… » : description (`about`) à gauche, fiche technique (genres, sortie, développeur, éditeur, temps de jeu) à droite.
- Capture : `?screen=detail&index=N&media=demo&slide=2` (images du CDN de Steam).
- A ouvre la **visionneuse** (`MediaViewer.svelte`). Une capture s'y affiche centrée, **bornée sur l'écran** (`100vw`/`100vh` moins les marges, `--viewer-inset`) : en pourcentage, dans une grille aux rangées automatiques, `max-height` ne s'appliquait pas et l'image débordait. Gauche / droite (ou L1 / R1) passent au média voisin, B referme.
- Une bande-annonce passe dans le **lecteur** (`VideoPlayer.svelte`), plein écran, façon lecteur multimédia Xbox : titre et nom en haut ; en bas la barre de progression (écoulé / durée, part déjà chargée) et **toutes les touches affichées avec leurs glyphes** — avant, il fallait tout deviner. A lecture / pause (« Revoir » à la fin), ◀ ▶ déplacent **directement le curseur** de la barre (pas de 2 s — 10 puis 5 s étaient trop ; maintenu, il défile ; le temps visé s'affiche dans une bulle au-dessus), ▲ ▼ volume (`volume_video`, le même que Réglages → Audio) dans une **jauge verticale sur le côté droit** (valeur à largeur fixe : passer à « 100 % » l'élargissait), L1 / R1 média précédent / suivant (dans la visionneuse, L1 / R1 ne changent donc pas de section), B fermer. Les commandes **s'effacent après 3 s** de lecture sans appui et reviennent au moindre appui ou à la pause ; chaque action fait apparaître son icône au centre (lecture, pause, ±10 s), comme sur YouTube. Variables `--player-*`. Capture : `?screen=detail&media=demo&slide=0&viewer=1` (une bande-annonce de démo en tête de `DEMO_MEDIA`, affiche seule).
- `steam_details` récupère `screenshots`, `movies`, `developers`, `publishers`, `about_the_game`. Une fiche en cache plus ancienne que `DETAILS_VERSION` est redemandée (et gardée si Steam ne répond pas) : sans ça, les jeux déjà vus n'auraient jamais de médias.
- **Steam ne fournit plus de fichier webm/mp4** pour les bandes-annonces récentes, seulement des flux HLS (`hls_h264`, CORS ouvert). WebKitGTK les lit seul ; sous WebView2, **hls.js** prend le relais, chargé seulement à l'ouverture d'une vidéo. Lecture avec le son, et en muet si le webview la refuse sans geste de l'utilisateur.

## Bibliothèque : en-tête et options

- L'en-tête porte deux **vrais boutons** : « Trier : <critère> » et « Synchroniser ». On les atteint en montant depuis la première rangée (`libraryZone: 'header'`), gauche / droite entre eux, bas pour revenir. Pendant ce temps, aucune jaquette n'a de contour.
- **X sur une jaquette ouvre les options du jeu**, comme sur l'accueil, dans la fenêtre `OptionsMenu.svelte` (avec le nom du jeu) — une grille ne peut pas « pousser » ses voisines comme le tiroir de la rangée d'accueil. État partagé avec la fiche : `menuOptionsOpen`.
- **Chargement par lots** (`BATCH` = 48, six rangées) : avec les bibliothèques Steam et Epic (plus de 600 jeux), toutes les jaquettes étaient construites et demandées d'un coup et le défilement saccadait. Quand la sélection approche du bas du lot (`PRELOAD_ROWS`), une rangée « Chargement des jeux suivants… » apparaît et le lot suivant arrive après `BATCH_DELAY` ; une touche maintenue qui dépasse le lot le fait rattraper aussitôt. Nouveau filtre ou tri : retour au premier lot. Le minuteur vit **hors de l'effet** : sinon chaque déplacement pendant la pause l'annulait et la grille restait bloquée sur « Chargement… ».
- Filtres (LT / RT) : **Tous · Installés · Favoris**, encadrés des glyphes LT / RT (L2 / R2) comme les périodes des statistiques : on voit tout de suite comment changer de catégorie. Pas de filtre « Récemment joué » : le tri « Dernière partie » le fait déjà sur « Tous ». Le filtre et le tri sont **mémorisés d'une session à l'autre** (`library_filter`, `library_sort` dans les réglages, `setLibraryView`).
- Le tri « dernière partie » s'affiche **« Récemment joué »**, plus clair.
- Tri : Titre · Récemment joué · Temps de jeu · **Jeux Steam** · **Jeux Epic**. Les deux derniers mettent les jeux de cette boutique en tête, puis les autres (chacun par titre) : un tri, pas un filtre, aucun jeu ne disparaît.
- View / Create reste un raccourci du tri. Capture : `?screen=library&zone=header`, `?screen=library&options=library`.

## Synchronisation de la bibliothèque

- Bouton **« Synchroniser »** dans l'en-tête de la bibliothèque (à côté de « Trier »), atteint en **montant depuis la première rangée** de jaquettes ; il relance la détection et met la bibliothèque à jour **sans fenêtre de validation** (`syncLibrary`) : jeu nouveau → ajouté ; jeu connu dont le dossier a bougé → nouveau chemin ; jeu introuvable dont l'exécutable n'existe plus (`paths_exist`) → retiré. Le bilan s'affiche en bas.
- Un jeu Steam a pour exécutable le client Steam, qui existe toujours : il n'est retiré que s'il n'est plus détecté — et jamais si le scan ne trouve **aucun** jeu Steam (Steam introuvable, pas tout désinstallé).
- Un jeu non détecté dont l'exécutable existe encore est **gardé** : la synchronisation ne doit jamais faire perdre un jeu jouable. Favoris et temps de jeu sont rangés sous l'identifiant : ils survivent à un changement de chemin.
- La détection détaillée, avec cases à cocher, reste dans Réglages → Jeux. **B l'annule tout de suite**, même pendant le scan : un numéro de scan (`scanTicket`) fait ignorer un résultat qui arrive après la fermeture ; le scan Rust finit dans son coin sans rien afficher.

## Menu d'options d'une tuile

- **X** sur l'accueil ouvre un panneau **dans la rangée**, à droite de la tuile sélectionnée : il pousse les tuiles suivantes au lieu de les recouvrir, en animant sa largeur. On voit donc toujours de quel jeu il s'agit.
- Entrées : favori, changer l'affiche, mettre à jour, vérifier les fichiers, désinstaller.
- Le panneau est **un tiroir de la tuile** : il reprend sa hauteur, son contour d'accent et ses coins, et se colle à son bord droit (marges négatives qui annulent l'espacement de la rangée). Tuile et panneau se lisent comme un seul bloc.
- Sur une **fiche de jeu**, il n'y a pas de tuile à prolonger : un troisième bouton « Options » (et la touche X) ouvre le même jeu d'actions dans `OptionsMenu.svelte`, avec des lignes identiques à celles du tiroir.
- Tout ce qui touche à l'installation est **confié à Steam** (`steam://install|validate|uninstall`) ou au launcher Epic (`com.epicgames.launcher://apps/…`), par la commande Rust `open_url` — qui n'accepte que ces deux protocoles **et seulement les caractères `[A-Za-z0-9:/?=._-]`** (`url_is_safe`, testé) : sous Windows l'adresse passe par `cmd /C start`, qui interprète `&`, `|`, `^`, `%` — `steam://x&calc` lançait une autre commande.

## PC neuf

- Dans l'application, `games` part **vide** : la bibliothèque vient de `library.json` et de la recherche des jeux installés faite à chaque démarrage (un PC neuf trouve donc ses propres jeux). `data/games.json` (13 jeux de démonstration) ne sert plus qu'hors application (navigateur, captures) — livré dans l'installeur, il faisait afficher les jeux de l'auteur sur n'importe quel PC.
- Accueil sans jeu : encart « Aucun jeu pour l'instant » ; A ouvre Réglages → Jeux (détection).
- La photo Steam d'un PC vient du cache de **son** client Steam (`config/avatarcache`), pas de l'installeur.
- Le journal (`tauri-plugin-log`, `%LOCALAPPDATA%\fr.interface.console\logs`) est actif aussi dans l'application installée : c'est là qu'on comprend un souci sur un autre PC.

## Journal des messages (`notices.svelte.ts`)

- `notify()` garde les 30 derniers messages ; Réglages → Système → **Journal** les liste (erreurs liserées de rouge). Un avertissement passé trop vite se relit là.

## Données sur le disque (`persist.ts`, `save_store`)

- Le stockage du webview (`localStorage`) **dépend de l'origine** : `tauri dev` sert `localhost:5177`, l'exécutable compilé une autre adresse. Tout ce qui n'y vivait que là (statistiques, journal, choix d'affiches) **disparaissait dans l'exe**, et l'accueil y perdait l'ordre « dernière partie ».
- Le disque est donc la référence : `persist(name, key, value)` écrit `<app data>/store/<name>.json` (commande `save_store`, nom limité à `[a-z-]`, écriture atomique) et garde le navigateur en secours ; `restore()` lit le disque, sinon le navigateur, et **recopie alors sur le disque** (migration). Magasins : `stats`, `sessions`, `art-styles`, `artwork`.
- `ScannedGame` (Rust) met `#[serde(default)]` sur ses champs facultatifs : sans ça, un seul jeu sans `executable` faisait refuser **toute** la sauvegarde de `library.json`, en silence — la bibliothèque ne vivait que dans le navigateur, et l'exe voyait tous les jeux Steam « non installés ».

## Erreurs

- Les actions qui peuvent échouer (`play`, `runPower`, `steamActions`) renvoient un `Outcome` (`{ ok, message }`) plutôt qu'une chaîne : l'appelant sait alors si c'est une confirmation ou une erreur.
- `notify()` est le seul point d'affichage : bandeau rouge liseré + pastille, son `error`, et 6 s à l'écran au lieu de 3 — le temps de lire depuis un canapé.
- `window.onerror` et `unhandledrejection` alimentent le même bandeau : une erreur non rattrapée se voit au lieu de figer l'interface en silence (c'est ce qui avait donné un écran noir muet).
- Capture : `?notice=error`. Attention, le budget de temps virtuel de Chrome fait expirer les `setTimeout` — garder `--virtual-time-budget` sous la durée du bandeau.

## Sons

- Les signaux viennent de `public/assets/sounds/` (design PlayStation fourni) : `ps5-scroll` pour le déplacement, `ps5-selection-button` pour la validation, `ps5-back-button` pour le retour, `ps5-popup-2` pour le lancement d'un jeu.
- Une direction ne sonne **que si la sélection a bougé** : `handle()` compare une empreinte de la sélection (`selectionKey()`) avant et après. Buter contre un bord reste silencieux. Un écran délégué (Réglages, Statistiques) fournit sa propre empreinte ; une fenêtre qui n'en a pas sonne à chaque fois. Les changements passés par `startViewTransition` sont différés : `navTick` les compte tout de suite.
- Les fichiers sont **décodés une fois** au démarrage (`preloadSounds()`) puis rejoués depuis la mémoire : un déplacement dans le carrousel ne doit pas attendre un chargement.
- L'**erreur** n'a pas de fichier : elle garde le signal grave de synthèse, qui ne ressemble à aucun autre son de l'interface. Cette synthèse sert aussi de secours si un fichier manque — mieux vaut un bip qu'une interface muette.
- Couper puis rallumer les sons ferme et rouvre le contexte audio : il faut alors redécoder (`preloadSounds()` à nouveau).

## Écran de veille

- Après `screensaver_minutes` sans aucune action (5 min par défaut, réglable dans Réglages → Apparence, `0` = jamais), `ScreenSaver.svelte` prend l'écran : artworks de la bibliothèque qui se relaient toutes les 12 s avec un lent panoramique, heure et date en bas à gauche.
- La première action **réveille seulement** : elle n'est pas transmise à l'écran en dessous, pour ne pas lancer un jeu en voulant rallumer l'écran.
- Pas de veille pendant l'animation de démarrage, ni s'il n'y a aucun artwork à montrer.

## Statistiques (`Stats.svelte`, `stats.ts`)

- **Pas d'onglet dans le dock** : elles s'ouvrent **seulement depuis le Profil** (tuile « Statistiques détaillées »), en **sous-page plein écran** posée par-dessus (`statsOpen`, section `profile`). B y ramène.
- Mise en page façon tableau de bord Xbox : « Bonsoir, <pseudo> » et le total, des **pastilles de faits marquants** (série record de jours d'affilée, jeu du moment sur 30 jours, plus longue partie — seulement celles qui ont une valeur), les **périodes** 7 j · 30 j · 90 j · Année · Tout encadrées des glyphes LT / RT, quatre chiffres (jeux, temps de jeu, jours actifs, genre favori), le **calendrier d'activité** de l'année, et à droite « Par genre » et « Les plus joués ».
- Calendrier (`heatmap()`) : 53 colonnes d'une semaine, lundi en haut, la dernière s'arrête à aujourd'hui ; cinq niveaux (`--heat-0` à `--heat-4` : rien, ½ h, 1 h, 2 h, 4 h et plus). Les jours hors de la période restent affichés mais s'effacent. Les dates se calculent par le calendrier, jamais en ajoutant des tranches de 24 h (changement d'heure).
- Deux zones se parcourent : le calendrier (la case sélectionnée affiche sa date et son temps de jeu — à la manette, pas de survol ; on ne tombe jamais sur un jour à venir) et le classement (A ouvre la fiche). Au bout du calendrier, droite passe au classement.
- « Tout » compte le temps Steam (`playtimeOf`) ; les autres périodes viennent du **journal** des parties (`sessions`), Steam ne donnant qu'un total. Une partie de **moins d'une minute n'est pas comptée** (`steam -applaunch` rend la main aussitôt).
- L'en-tête donne les jeux **possédés** et **installés** ; le chiffre « Jeux joués » suit la période (journal), ou, pour « Tout », les jeux qui ont du temps de jeu.
- `stats.ts` ne fait que des calculs (fonctions pures) ; le composant n'a plus qu'à dessiner.
- Capture : `?screen=stats&stats=demo&period=week|month|quarter|year|all` remplit le journal de parties fictives, jamais enregistrées.

## Réglages

- Quatre catégories : **Jeux** (détection, clé SteamGridDB, dossiers), **Apparence**, **Audio**, **Système** (affichage seulement — les tuiles d'information « Plateforme », « Moteur de rendu »… ont été retirées, elles n'apportaient rien).
- **Audio** : interrupteur des sons, puis cinq jauges par pas de 10 % — général, menus (déplacement, validation, retour), notifications (manette, erreurs), lancement d'un jeu, vidéos (bandes-annonces). Gauche / droite règlent la ligne sélectionnée (B revient aux catégories), A fait le tour, et un aperçu du son joue au nouveau volume. Réglages `volume_*` (Rust `default_volume` = 100) ; `sound.ts` multiplie le gain de chaque son par le général et celui de sa famille (`GROUP`), à 0 rien ne joue. Capture : `?screen=settings&cat=audio`. Le pseudo, la photo, les comptes et les statistiques sont dans le Profil.

- `saveSettings()` envoie **tous** les champs : la commande Rust réécrit le fichier entier et les champs absents y reprennent leur valeur par défaut. N'en envoyer qu'une partie effaçait silencieusement la clé SteamGridDB et la vidéo d'introduction au premier changement de pseudo.

## Données de jeu

- Les images viennent du CDN public de Steam. Toutes les jaquettes verticales n'existent pas : on retombe sur `header.jpg` plutôt que d'afficher une case vide.
- Fiches (note, genres, date, résumé) : `store.steampowered.com/api/appdetails` ; recherche par titre : `steamcommunity.com/actions/SearchApps`. Aucun compte, aucune clé.
- Comparer les titres en **deux passes** : nom identique d'abord, ressemblance ensuite. Sinon « Hollow Knight » tombe sur « Hollow Knight: Silksong ».
- La ressemblance passe par `titles_match()` : une simple inclusion ne suffit pas. « osu » est contenu dans des dizaines de noms et « Ball » dans « Golf Ballgame » — c'est ainsi qu'une jaquette se retrouvait sur le mauvais jeu. Il faut au moins cinq caractères et que le titre court fasse 70 % du long.
- Un exécutable générique (`game.exe`, `launcher.exe`, `start.exe`…) n'est **pas** utilisé comme variante de titre : le chercher revenait à tirer une jaquette au hasard.
- **Aucune source ne renvoie « le premier résultat venu »** : Lutris comme Steam passent par `titles_match`, y compris sur la réponse d'un slug direct (un slug peut tomber sur un homonyme). C'est la passe « premier jeu qui a une jaquette » de Lutris qui collait GOLF KEEPER sur osu!(lazer), la recherche « osu » y renvoyant n'importe quoi.
- La table statique d'appids (`match_steam_app`) ne se vérifie pas toute seule : elle contenait `osu → 1222440`, un jeu délisté dont les images CDN sont celles de GOLF KEEPER. Avant d'y ajouter une ligne, ouvrir `store.steampowered.com/app/<id>`.
- La note Metacritic est ramenée sur 5 (`score / 20`) et s'affiche en étoiles (icône Font Awesome dans `public/assets/icons/star.svg`). À 0, on n'affiche rien : une rangée éteinte ferait croire à une mauvaise note.

## Intégration système

- Scripts Linux (Gamescope, systemd, autologin) : voir `system/CLAUDE.md`. Toujours garder une porte de sortie pour ne pas se bloquer hors du système pendant les tests.

## Logo et exécutable

- Logo : monogramme « L » lumineux avec une croix directionnelle, en verre dépoli vert (généré avec Gemini). La source est `src-tauri/app-icon.png` (1024 px, coins transparents) ; `npx tauri icon src-tauri/app-icon.png` en tire toutes les tailles dans `src-tauri/icons/`.
- `npm run tauri build` produit `src-tauri/target/release/app.exe` (nom du paquet Cargo ; installé sous le nom « Lobby ») et l'installeur `src-tauri/target/release/bundle/nsis/Lobby_<version>_x64-setup.exe`. Cible limitée à NSIS (`bundle.targets`) : le `.msi` demande WiX, dont le téléchargement restait bloqué.

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

- **Plus de page Recherche** : c'est une **fenêtre** (`SearchModal.svelte`), ouverte par **Y** de partout ou par le champ du dock. Elle réutilise **le clavier virtuel des réglages** (`VirtualKeyboard.svelte`) — un seul clavier dans toute l'interface — avec les jeux correspondants juste en dessous, filtrés à la frappe.
- `VirtualKeyboard` sait donc aussi : suivre la frappe (`onInput`), laisser partir la sélection par le bas (`onLeaveBottom`), se mettre en retrait (`active`), s'élargir (`wide`) et afficher un contenu sous les touches (`children`).
- Bas sous la dernière rangée (ou « Valider ») passe aux jeux, une rangée de 7 visible à la fois ; haut depuis la première rangée revient au clavier ; A ouvre la fiche ; B referme.
- Les touches sont rendues par `Keyboard.svelte` ; la disposition vit dans `searchKeys.ts` (`textKeyboardRows(caps)`) : **AZERTY**, **chiffres en tête**. La sélection se repère en `{ row, col }` et `nearestColumn()` garde l'alignement en changeant de rangée.
- Une touche sélectionnée **inverse ses couleurs**, sans agrandissement : sur une grille serrée, il ferait sauter tout le clavier. Les touches d'action portent le glyphe du bouton manette qui fait la même chose.
- Comparaison via `normalizeForSearch` : sans accents ni ponctuation, « repo » trouve « R.E.P.O. ».
- Capture : `?search=1` ouvre la fenêtre.

## Animation de démarrage (`BootIntro.svelte`)

- D'après une vidéo Claude Design de l'utilisateur (10,5 s), **rejouée en direct** pour être personnelle : quatre traits de couleur convergent, éclat (onde verte) et les quatre pastilles de la manette en losange (Y jaune, B rouge, A vert, X bleu, `--pad-*`), **LOBBY** / CONSOLE, puis une couronne de 60 graduations qui s'allument au fil du **vrai chargement**, « N / total jeux » et l'étape réelle, puis « Bonjour / Bonsoir, <pseudo> » sous la photo cerclée d'accent ; à la sortie, le fond s'efface sur l'accueil et la photo file vers sa place dans le dock (FLIP sur `.top .profile .avatar`). Son `boot` : accord de quatre notes synthétisé (`playChime`, famille Notifications) à l'éclat.
- **Chargement réel** (`bootLoad()` dans `App.svelte`), dit tel quel sous le compteur : réglages → bibliothèque installée, statistiques, affiches → **recherche des jeux installés** (`scanAndSync`, comme « Synchroniser » : ajoutés, déplacés, désinstallés ; 15 s au plus, `SCAN_WAIT`, puis fin en arrière-plan ; bilan dans le bandeau s'il y a du changement) → comptes Steam (local + liste chiffrée) et Epic (réseau, attendu 8 s au plus, `EPIC_WAIT`) → jaquette **et** fond de chaque jeu installé, puis jaquettes du premier lot de la bibliothèque (48), décodées (`Image.decode`, 4 s au plus chacune, `IMAGE_WAIT`). Le **total grandit en direct** (`allGames` : installés + possédés) ; le compteur suit les jeux **prêts** (installé : images décodées ; possédé : liste arrivée) et ne dépasse jamais la jauge.
- La jauge ne fait jamais un tour en moins de `MIN_LOADING` (vitesse bornée) : bibliothèque en cache, le compteur sautait d'un coup au total.
- **Rien d'autre n'est visible pendant l'animation** : `body.booting` masque tout le reste de l'interface (`#app > *:not([data-intro])`, `visibility: hidden`) jusqu'à la sortie (`onReveal`), où le fond s'efface sur l'accueil. L'accueil apparaissait sinon entre le début de l'animation et le chargement des jeux.
- Une manette lue pour la première fois sert d'état de départ sans rien déclencher (`seenPad`, `gamepad.ts`), et l'animation ne se passe pas avant 1,5 s (`SKIP_GRACE`) : une gâchette au repos imparfait ou un appui au réveil la passaient aussitôt.
- Chaque phase est tracée dans le journal (`ui_log` → `Interface : animation : …`, `chargement fini : N installés, M au total`) : c'est ce qui a montré que l'animation se jouait bien en entier.
- **Aucun trou noir entre les étapes** : le point où les traits se rejoignent reste allumé à l'éclat (`.core`, éclair puis résorption) et les pastilles en sortent ; à la fin du chargement, la couronne et les pastilles se resserrent vers le centre en s'effaçant (`out:scale`), le nom et le compteur se dissolvent, pendant que la photo grandit au même endroit (`in:scale`, décalée de 150 ms). Avant, chaque étape disparaissait d'un coup avant que la suivante n'apparaisse.
- Logo **fixe au centre de l'écran**, textes posés dessous en absolu : en flux, l'apparition du nom faisait remonter les pastilles.
- Fond sombre **dès la création de la fenêtre** (`backgroundColor` dans `tauri.conf.json`, `index.html`) : plus d'éclair blanc avant l'animation.
- N'importe quelle touche la passe (sortie courte, sans vol). Réglages → Apparence → « Animation de démarrage » (`intro_enabled`). Pas de veille pendant. `?intro=0` la saute (captures).
- `coverFor(game)` (`steam.svelte.ts`) : l'image d'une jaquette, partagée par `Cover.svelte` et le préchargement — une seule logique.
- Les anciennes vidéos d'introduction (pixelisées) restent retirées.

## Feuille de route

- Ce qui est fait et ce qui reste : skill `roadmap` (`.claude/skills/roadmap/SKILL.md`). La tenir à jour quand une étape avance.

## Règles de travail pour Claude

- Lire ce fichier avant toute modification et le tenir à jour si l'architecture change.
- Avancer étape par étape : une fonctionnalité à la fois, testable.
- Après chaque changement, lancer `npx svelte-check --threshold error` et, si le rendu bouge, une capture pour vérifier de ses yeux.
- **Après chaque changement, fermer puis relancer l'application** (`npm run tauri dev`) et vérifier qu'elle démarre sans erreur : arrêter d'abord `app.exe`, la session `tauri dev` et son Vite (port 5177), sinon le port reste pris.
- Ne jamais supprimer de fichiers sans me le demander.
- Les visuels (rendu, animations, sensation manette) sont validés par moi : indiquer clairement ce que je dois tester.
- Répondre en français, de façon concise.
