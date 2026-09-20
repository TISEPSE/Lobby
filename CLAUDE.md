# Interface Console

Interface de type console ("10-foot UI") qui transforme un PC en console de jeux. Elle se lance au démarrage, s'affiche sur TV et se contrôle uniquement à la manette.

## Vision et rendu final

- Le PC démarre directement sur l'interface, sans bureau ni souris.
- Écran d'accueil avec carrousel de jaquettes, bibliothèque en grille, fiche détaillée d'un jeu.
- Style moderne et cinématique (référence : PS5, Xbox, Steam Big Picture) avec une identité originale.
- Fond = artwork flouté du jeu sélectionné, thème sombre, une seule couleur d'accent.
- Navigation 100 % manette : D-pad / stick, A = valider, B = retour, X = options, Y = recherche.
- Lancer un jeu ferme ou met en pause l'interface, puis la ramène au premier plan quand le jeu se termine.
- Cible finale : session Linux dédiée (Gamescope + systemd), comme le Steam Deck.

## Stack

- Moteur : Godot 4.x, langage GDScript (pas de C# sauf besoin justifié)
- Cible : Linux (Arch / Bazzite), Wayland via Gamescope
- Développement possible sous Windows, mais tout le code doit rester portable
- Données : fichiers JSON dans `user://`; `data/games_sample.json` porte un champ `version` : l'incrémenter ré-amorce `user://games.json` au prochain lancement
- Jaquettes & Artworks automatiques : zéro clé API requise (`CoverFetcher`). Cache local Steam, dossiers locaux, CDN Steam public 600x900 et recherche Steam Store publique.

## Structure du projet

```
res://
├── project.godot
├── scenes/
│   ├── main.tscn              # racine, gère la navigation entre écrans
│   ├── screens/               # home (hub), library (grille), game_detail, settings
│   └── components/            # game_tile, shortcut_tile, top_bar, help_bar, backdrop, sidebar, power_menu, folder_browser
├── scripts/
│   ├── autoload/              # GameLibrary, InputManager, Launcher, Settings, CoverFetcher
│   ├── screens/
│   └── components/
├── assets/                    # fonts, icons, shaders, placeholders
├── data/                      # jeux d'exemple (JSON)
└── system/                    # scripts Linux : gamescope, systemd, autologin
```

## Conventions

- Code, variables, noms de fichiers en anglais ; commentaires et textes UI en français.
- GDScript typé partout (`var x: int`, `func f() -> void`).
- Fichiers en `snake_case`, classes en `PascalCase`.
- Un script par scène, attaché à sa racine.
- Communication entre nœuds par signaux, pas par chemins `get_node` en dur.
- Singletons (autoload) uniquement pour : GameLibrary, InputManager, Launcher, Settings.
- Pas de valeurs magiques : couleurs, tailles et durées d'animation dans un fichier de thème ou de constantes.
- Toutes les constantes visuelles et les générateurs de dégradés sont dans `UITheme` (`scripts/theme/ui_theme.gd`).
- Direction artistique : tuiles carrées, accent vert, fond = artwork du jeu sélectionné en fondu enchaîné (références Xbox dans `Références-XBOX/`).
- Accueil = hub : artwork plein écran, rangée horizontale de jeux (tuile sélectionnée agrandie, titre en bandeau), rangée de raccourcis en bas.
- Valider une jaquette ouvre la fiche du jeu (`game_detail`), jamais le jeu directement : le lancement se fait depuis le bouton « Jouer » de la fiche.
- Transition entre écrans : la jaquette sélectionnée rejoint sa place sur la fiche (jaquette fantôme hors conteneur dans `game_detail`), puis les informations se révèlent ; `closing` prévient la racine pour que l'écran précédent revienne pendant l'animation de retour.
- Le rectangle d'arrivée de cette transition ne peut être lu qu'une fois la mise en page **stabilisée** (2 images mesurées) : `_settled_cover_rect()` attend qu'il ne bouge plus. Le lire trop tôt envoyait la jaquette dans le coin de l'écran.
- Le voile posé sur un artwork s'adapte à la clarté de sa moitié basse (`ImageLoader.bottom_luminance`, mesurée dans le fil de décodage) : discret sur une image sombre, appuyé sur une image claire.
- Bibliothèque : filtres (Tous / Favoris / Récemment joué) et tri cyclique, défilement vertical par lignes entières. Les raccourcis « Favoris » et « Récemment joué » de l'accueil ouvrent le même écran sur le filtre correspondant.
- `main.gd` empile les écrans : l'écran quitté est masqué et privé d'entrées, pas détruit, pour retrouver sa sélection au retour (`B`).
- Styles de sélection : `UITheme.surface_box()` au repos et `UITheme.focus_box()` au focus (contour d'accent + halo) — même langage partout, jamais d'aplat vert.
- Panneau latéral **gauche** (`sidebar`) : ouvert par la touche Options (X). Il mène à la fenêtre d'alimentation (`power_menu`, modale centrée) ; son contenu définitif reste à définir. Extinction et redémarrage réels sous Linux ; inertes sous Windows (`SystemPower.ALLOW_ON_WINDOWS`).
- Bibliothèque calquée sur celle de la PS5 : titre de page, onglets en texte simple (actif en blanc, les autres en gris), ligne « Tous : N » / « Trier par : … », grille de 5 grandes jaquettes, fond volontairement effacé (`dim_backdrop` lu par `main.gd`, cf. `UITheme.BACKDROP_DIMMED_ALPHA`).
- Le titre est écrit sur **toutes** les jaquettes, y compris celles du carrousel non sélectionnées : sans lui, un jeu n'est pas identifiable.
- Barre du haut (calquée sur celle de la Xbox) : avatar, pseudo, badge et statistique à gauche ; les 4 icônes de sections au centre ; manettes connectées et heure à droite. **Tout y vient de données réelles** (`GameLibrary` pour le nombre de jeux et le temps cumulé, `Input.get_connected_joypads()` pour les manettes) — pas d'indicateur décoratif.
- `cover` et `background` d'un jeu acceptent `res://`, `user://` ou un chemin absolu.
- Si `background` est vide, le jeu reçoit un des fonds de `assets/backgrounds/` (ou `user://backgrounds/`), choisi d'après son `id` : toujours le même pour un jeu donné. Déposer une image dans ce dossier suffit, sans toucher au code (voir `Wallpapers`).
- Les artworks sont affichés **nets**, ramenés à 1920 px de large. Devant une vraie image, voile et vignette sont fortement atténués.
- Décoder un JPEG de plusieurs mégaoctets prend ~1 s : le chargement se fait dans `WorkerThreadPool`, seule la création de la texture revient au fil principal. Les fonds partagés sont préchargés au lancement, et tant qu'une image n'est pas prête le fond précédent reste affiché (pas de clignotement).
- Sans aucune image disponible, on retombe sur les dégradés générés par `UITheme` — repli seulement, pas une fin en soi.
- `user://backgrounds/` est le dossier à privilégier : pas de réimport Godot, les images sont prises au démarrage suivant.

## Règles UI / manette

- Résolution de référence : 1920x1080, tout doit s'adapter en 16:9.
- Marges de sécurité de 5 % pour l'affichage TV.
- Texte minimum 28 px, contraste élevé.
- Le focus doit toujours être visible (agrandissement + bordure lumineuse) et jamais perdu.
- Utiliser le système de focus natif de Godot (`grab_focus`, `focus_neighbor_*`) plutôt qu'une navigation maison.
- `InputManager` ajoute la seule chose que Godot ne fait pas : maintenir une direction fait défiler la sélection. Il **déplace le focus lui-même** (`find_valid_focus_neighbor`) et ne synthétise jamais d'action. L'ancienne version envoyait un `InputEventAction` appuyé **sans relâchement** : l'action restait bloquée, Godot ajoutait sa propre répétition et la sélection partait toute seule à la manette.
- Seuils du stick : engagement à 0,65, relâchement à 0,40 (hystérésis) et `deadzone` du Input Map à 0,65 sur les directions — une manette dont le stick traîne au repos ne doit pas naviguer sans qu'on y touche.
- Actions d'input définies dans le Input Map : `ui_accept` (A), `ui_cancel` (B), `ui_options` (X), `ui_search` (Y), plus les actions de direction.
- Toute action doit être faisable sans souris ni clavier.
- Animations courtes (150 à 300 ms) avec `Tween`, pas de ralentissement perceptible.

## Vrais jeux (étape 4)

- `Settings` (autoload) garde les dossiers de jeux dans `user://settings.json`.
- `GameScanner.scan()` attend **un sous-dossier par jeu** : le titre vient du nom du dossier, et l'exécutable est celui dont le nom ressemble le plus à ce titre (profondeur 3 max). Désinstalleurs, redistribuables et outils de crash sont écartés par nom (`GameScanner.REJECTED`).
- `GameLibrary.merge_scanned()` est **non destructif** : un jeu déjà connu ne voit que son chemin et son titre rafraîchis ; favoris, temps de jeu et dernière partie sont préservés.
- Le champ `source` d'un jeu vaut `sample`, `scan` ou `manual`. `GameLibrary.remove_samples()` ne retire que les jeux de démonstration.
- Le dossier se choisit à la manette (`folder_browser`) : A entre, B remonte puis ferme, X retient le dossier courant. Godot n'expose pas la liste des lecteurs Windows : elle est reconstruite en testant les lettres A: à Z:.
- Tester le scan sans lancer l'interface : `godot --headless --script res://tools/test_scan.gd -- "D:\Jeux"`

## Détection automatique des jeux (`GameFinder`)

- On n'explore **pas** tout le disque : on interroge les sources qui savent déjà ce qui est installé.
  - **Steam** : `steamapps/libraryfolders.vdf` donne les bibliothèques (souvent sur un autre disque), puis chaque `appmanifest_*.acf` donne `appid`, `name`, `installdir`. Le lancement passe par `steam.exe -applaunch <appid>` : Steam connaît mieux que nous les arguments du jeu. Un manifeste dont le dossier `common/<installdir>` a disparu est ignoré.
  - **Epic** : un manifeste JSON par jeu dans `C:/ProgramData/Epic/EpicGamesLauncher/Data/Manifests`.
  - **Raccourcis** : Bureau (utilisateur et public) et menu Démarrer, profondeur 3. Sous Linux, les `.desktop` dont `Categories` contient `Game`.
- Les lignes d'un fichier Valve sont indentées : `_vdf_value()` cherche la clé **parmi** les fragments, sinon la tabulation de tête passe pour la clé (ce qui donnait 0 jeu Steam).
- `ShellLink` lit le format Windows `.lnk` (MS-SHLLINK) : Godot ne suit pas les raccourcis. On lit LinkInfo (chemin local) et, à défaut, `working_dir` + chemin relatif. Un raccourci illisible est ignoré, jamais deviné.
- Deux filtres : `REJECTED_SHORTCUTS` (désinstalleurs, manuels, éditeurs…) et `APP_BLOCKLIST` (navigateurs, messageries, outils…). Ils dégrossissent, ils ne décident pas.
- **C'est l'utilisateur qui valide** : `scan_results` liste les candidats, A coche, X coche tout, et seuls les jeux cochés entrent dans la bibliothèque. Steam et Epic sont cochés d'office (sources sûres), les raccourcis non. Les jeux déjà connus sont affichés « déjà ajouté », non sélectionnables.
- Voir ce que la détection trouve sur cette machine : `godot --headless --script res://tools/test_finder.gd`

## Fiches de jeu : notes, genres, résumés (`metadata_fetcher`)

- **Aucune clé d'API, aucun compte** : tout vient des points d'entrée publics de Steam.
  - `steamcommunity.com/actions/SearchApps/<titre>` donne l'appid d'un jeu trouvé hors Steam.
  - `store.steampowered.com/api/appdetails?appids=<id>&l=french` donne genres, date, résumé et note Metacritic (ramenée sur 5 : `score / 20`).
- Un jeu détecté via Steam porte déjà son appid dans son identifiant (`steam-753640`) : pas de recherche.
- La correspondance de titre se fait **en deux passes** : nom identique d'abord, ressemblance ensuite. Sans ça, « Hollow Knight » tombait sur « Hollow Knight: Silksong ».
- Les appids trouvés sont gardés dans `user://metadata_cache.json` : on ne réinterroge pas Steam à chaque lancement.
- Le composant **ne connaît pas la bibliothèque** : l'écran lui passe la liste et enregistre ensuite. Il ne télécharge aucune image — c'est `CoverFetcher` (autoload) qui s'occupe des jaquettes et des fonds. Deux services, deux responsabilités.
- Après l'ajout de jeux détectés, les fiches se complètent **toutes seules** (`_on_scan_confirmed`).
- Pièges rencontrés, tous mesurés : un `cancel_request()` juste avant un `request()` faisait échouer la requête suivante en silence ; `FileAccess.open` en écriture n'échoue pas bruyamment quand le dossier manque ; en `--script`, un nœud ajouté au root n'est dans l'arbre qu'à la frame suivante (`HTTPRequest` refuse de partir avant).
- Vérifier sans lancer l'interface : `godot --headless --script res://tools/test_metadata.gd` (≈ 600 ms par jeu), et `res://tools/test_http.gd` pour tester les adresses d'images.
- La note s'affiche en étoiles (`RatingStars`, icône Font Awesome dans `assets/icons/star.svg`) : cinq étoiles, accent pour les obtenues, `UITheme.COLOR_STAR_EMPTY` pour les autres, puis la valeur. À 0, rien ne s'affiche — une rangée éteinte ferait croire à une mauvaise note.

## Jaquettes et fonds automatiques sans clé API (`CoverFetcher`)

- Système 100 % automatique et transparent : aucune clé API, aucun compte développeur, aucune inscription requise.
- **Cache local Steam** : vérifie immédiatement `Steam/appcache/librarycache/<appid>/library_600x900.jpg`, `header.jpg` et `library_hero.jpg` pour les jeux Steam détectés.
- **Dossiers locaux** : inspection des dossiers d'exécutables pour `cover.jpg`, `cover.png`, `folder.jpg`, `boxart.jpg`.
- **CDN Steam public** : téléchargement en tâche de fond de la jaquette verticale officielle 600x900 (`cdn.cloudflare.steamstatic.com/steam/apps/<appid>/library_600x900.jpg`).
- **Recherche Store Steam publique** : pour les jeux non-Steam (Epic, raccourcis, etc.), interroge l'API publique `store.steampowered.com/api/storesearch/` sans clé d'authentification pour identifier l'AppID et obtenir la jaquette.
- **Mise en cache** : les images téléchargées sont stockées dans `user://covers/`, réutilisées hors-ligne et enregistrées dans `user://games.json`.
- `GameLibrary.game_updated` avertit l'accueil et la bibliothèque dès qu'une jaquette est prête.
- Option manuelle dans **Paramètres > Jeux > Télécharger les jaquettes manquantes**.
- Icône d'étoile : SVG FontAwesome officiel vectoriel (`assets/icons/star.svg`), teinté via `modulate = UITheme.COLOR_ACCENT`.

## Profil et saisie à la manette

- `Settings` garde le pseudo et le chemin de la photo de profil. `top_bar` et `sidebar` s'y abonnent via `Settings.changed` ; sans photo, on retombe sur l'initiale du pseudo.
- La pastille d'avatar utilise `clip_children = 2` (dessiner **et** masquer) : le mode 1 masquerait sans dessiner le fond coloré.
- `virtual_keyboard` : clavier AZERTY à l'écran, seule façon de saisir du texte sans clavier physique. Options efface le dernier caractère, B annule.
- La photo de profil **ne se cherche pas sur le PC** : elle se choisit dans une grille fournie par la console (`avatar_picker`, alimenté par `MediaCatalog`). Les visuels sont dans `assets/avatars/` (SVG importés par Godot) ; déposer une image dans `user://avatars/` l'ajoute au choix au démarrage suivant.
- La première case de la grille rend le profil à son initiale : c'est elle qui remplace un bouton « retirer la photo ».
- `AvatarView.make()` construit la pastille ronde partout pareil (carte du profil, grille de choix).
- `MediaCatalog` liste ce que la console propose (avatars, vidéos d'intro) et fabrique le flux vidéo, qu'il vienne du projet ou du disque.
- `folder_browser` ne sert plus qu'aux dossiers de jeux.
- `ControllerGlyphs` gère les symboles des boutons d'après le réglage utilisateur (`Settings.button_layout`) ou la manette branchée (détection SDL). Vrais boutons officiels vectoriels Xbox (`assets/buttons/xbox/`) et PS5 (`assets/buttons/ps5/`), rendus directement sans container ni cadre artificiel (`has_bg = false`). Les index Godot ne changent jamais, seul l'affichage s'adapte.
- Lister les manettes vues par Godot : `godot --headless --script res://tools/pads.gd`
- Mesurer la dérive des sticks : `godot --path . --script res://tools/pad_axes.gd` (manette au repos pendant 6 s). Au-delà de `InputManager.STICK_RELEASE`, la sélection se déplace toute seule.

## Écran Paramètres

- Deux niveaux : 5 catégories à gauche (Profil, Apparence, Démarrage, Jeux, Système), options de la catégorie à droite. Parcourir les catégories met le panneau à jour **sans y entrer** ; valider fait passer le focus aux options ; `B` ramène aux catégories avant de quitter l'écran.
- Fond **opaque** (`UITheme.COLOR_PAGE`), identique à la Bibliothèque : on a quitté l'accueil et le contraste est maximal.
- Défilement global : un `PageScroll` (`ScrollContainer`) englobe tout le contenu de la page avec barre de défilement discrète et élégante sur le bord de l'écran, sans sous-boîtes étriquées qui coupent les boutons.
- Structure uniforme sur les catégories : carte d'aperçu à gauche, colonne d'actions / fiches à droite (`_add_side_card`). La carte s'affiche mais ne prend jamais le focus ; `_row_parent` dit où se rangent les lignes.
- Profil : photo ronde, pseudo, nom du fichier. Sans photo, l'initiale du pseudo sur l'accent (`clip_children = CLIP_CHILDREN_AND_DRAW` pour découper la photo en rond).
- Apparence : carte Manettes & Touches avec bascule de la disposition des touches (Auto, Xbox, PlayStation) sans container artificiel (`_add_button_layout_row`).
- Démarrage : la vidéo configurée est **jouée dans la carte**, en boucle et sans son, pour voir ce qui s'affichera au lancement. Option avec interrupteur Toggle Switch visuel (`_add_toggle_row`).
- Jeux : carte avec badge de bibliothèque, total de jeux installés et nombre de dossiers suivis ; actions de scan et d'ajout à droite.
- Système : carte Console à gauche et 4 fiches télémétriques (`_add_info_row` : plateforme, moteur, manettes, configuration). Les fiches restent sélectionnables à la manette (affiche les détails dans `_status`) pour ne pas bloquer le focus.
- Les fenêtres modales (`AvatarPicker`, `BootVideoPicker`) et barres d'aide utilisent la `HelpBar` avec symboles manette réactifs (`ControllerGlyphs`), mise à jour en temps réel lors d'un changement de disposition.
- Changer un réglage reconstruit les lignes : `_refresh_rows()` retient l'index de la ligne focalisée et `_restore_row_focus()` le rend après coup — jamais pendant qu'une modale est ouverte, c'est elle qui a le focus. Les modales ne rendent pas la main à un bouton déjà détruit (`is_queued_for_deletion`). Sans ça, choisir un avatar ou une vidéo laissait l'écran **sans aucun focus**.

## Vidéo d'introduction

- **Godot 4 ne décode nativement que l'Ogg Theora (`.ogv`)** : ni MP4, ni WebM, ni MKV. Les vidéos livrées sont donc converties avant d'entrer dans `assets/boot/`.
- La vidéo **se choisit dans une liste fournie par la console** (`boot_video_picker`), jamais dans un navigateur de fichiers : les vidéos sont dans `assets/boot/`, et `user://boot_videos/` accepte les tiennes. Parcourir la liste joue l'aperçu, valider retient la vidéo ; la première entrée démarre sans vidéo.
- Convertir une vidéo : `ffmpeg -i entree.mp4 -c:v libtheora -q:v 7 -c:a libvorbis -q:a 4 sortie.ogv`
- `Settings.boot_video_path` et `boot_video_enabled` ; `has_boot_video()` vérifie aussi que le fichier existe encore.
- `boot_video` recouvre l'accueil, déjà construit derrière : si la vidéo est illisible, on n'affiche rien plutôt qu'un écran noir. A, B ou Options la passent.
- `MediaTypes` centralise les extensions reconnues, partagées entre le navigateur et les écrans.

## Modèle de données d'un jeu

Défini par `scripts/model/game_entry.gd` (champs typés) et illustré par `data/games_sample.json`.

## Lancement d'un jeu

- Utiliser `OS.create_process(path, args)` et suivre le PID avec `OS.is_process_running(pid)`.
- Tant qu'aucun vrai jeu n'est installé, `"executable": "{demo}"` dans le JSON est remplacé à l'exécution par un exécutable de test (bloc-notes sous Windows, `sleep` sous Linux) : voir `Launcher._demo_target()`.
- Pendant le jeu : couper le son de l'interface et suspendre les animations lourdes.
- À la fermeture du jeu : mettre à jour `playtime_minutes` et `last_played`, puis ré-afficher l'interface.

## Intégration système (dossier `system/`)

- `interface-console.sh` (installé en `/usr/local/bin/interface-console`) lance Gamescope en plein écran sur l'export Godot. Résolution, fréquence et chemin du binaire se règlent par variables d'environnement (`INTERFACE_CONSOLE_WIDTH`, `_HEIGHT`, `_REFRESH`, `_BIN`) — rien à modifier dans le script.
- `interface-console.service` prend `tty1` (`Conflicts=getty@tty1`), comme la session du Steam Deck. `Restart=on-failure` seulement : « Quitter l'interface » doit ramener à un terminal, pas relancer l'interface en boucle.
- `install.sh` copie le binaire dans `/opt/interface-console/`, écrit l'unité pour le bon utilisateur et son UID, recharge systemd. `autologin.conf` couvre la variante sans unité dédiée.
- `system/README.md` détaille la marche à suivre et les portes de sortie.
- `export_presets.cfg` porte le preset **Linux** (x86_64, PCK embarqué, `Références-XBOX/` et `tools/` exclus). **Les modèles d'exportation Linux manquent sur ce poste** (seuls ceux d'Android sont installés) : l'export échoue tant qu'ils ne sont pas téléchargés depuis l'éditeur.
- Windows (secondaire) : remplacement du shell via la clé `Shell` dans Winlogon (clé de registre `HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Winlogon`), à documenter mais non prioritaire.
- Toujours prévoir une porte de sortie (raccourci pour quitter vers un terminal) pour ne pas se bloquer hors du système pendant les tests.

## Commandes utiles

- Vérifier les erreurs de script sans ouvrir l'éditeur : `godot --headless --quit-after 90`
  **Le code de sortie reste 0 même en cas d'erreur de script : il faut lire la sortie**, pas seulement l'exit code.
- Après l'ajout d'un `class_name` ou d'un asset (SVG, image), lancer `godot --headless --import` : sans ça la classe reste « not declared » et l'asset « no loader found ».
- Sous Windows (poste de dev actuel), le binaire est `C:\Users\User\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`.
- Lancer le projet : `godot --path .`
- Capturer le rendu sans ouvrir l'éditeur : `godot --path . -- --capture sortie.png` (outil de dev dans `main.gd`) ; options `--focus N`, `--screen library|settings`, `--detail N`, `--power`, `--category profile|boot|games|system`, `--avatars`, `--videos`, `--accept` (simule un A), `--delay N` (en **secondes**). L'ordre est fixe : écran, catégorie, focus, puis fenêtre modale.
- Mesurer le coût des textures de fond : `godot --headless --script res://tools/bench_textures.gd`
- Export Linux : `godot --headless --export-release "Linux" build/interface-console.x86_64`
- Tester sous Gamescope : `gamescope -f -e -- godot --path .`

## Feuille de route

1. **Prototype** : grille de jeux (données d'exemple), navigation manette, lancement d'un exécutable.
2. **Écrans** : accueil (carrousel), bibliothèque (filtres, tri), fiche jeu.
3. **Habillage** : thème, fond flouté, animations, barre d'aide dynamique.
4. **Données réelles** : scan de dossiers, récupération des jaquettes (SteamGridDB) et métadonnées (IGDB).
5. **Système** : export Linux, Gamescope, systemd, boot direct.
6. **Finitions** : paramètres, son, écran de veille, gestion des erreurs.

## Dette connue

- `shortcut_tile.gd` place ses icônes et libellés avec des offsets écrits en dur (17 valeurs). À ramener dans `UITheme`, comme le reste.

## Règles de travail pour Claude

- Lire ce fichier avant toute modification et le tenir à jour si l'architecture change.
- Avancer étape par étape : une fonctionnalité à la fois, testable.
- Ne pas modifier les fichiers `.tscn` à la main sauf changement minimal et sûr ; privilégier la logique en GDScript et me dire quels nœuds créer dans l'éditeur.
- Après chaque changement de code, lancer `godot --headless --quit` pour détecter les erreurs.
- Ne jamais supprimer de fichiers sans me le demander.
- Les visuels (rendu, animations, sensation manette) sont validés par moi : indiquer clairement ce que je dois tester.
- Répondre en français, de façon concise.