extends Control

## Écran Paramètres, à deux niveaux : les catégories à gauche, leurs options à
## droite. Le fond est opaque : on a quitté l'accueil, l'artwork n'a plus à
## transparaître derrière les réglages.

## Jamais émis ici : la racine connecte ce signal sur tous les écrans pour
## piloter le fond. Cet écran n'a pas de jeu sélectionné.
signal selection_changed(game: GameEntry)
signal back_requested()

const ROW_SEPARATION: int = 10
const ICON_SIZE: Vector2 = Vector2(32, 32)
const ICON_GAP: int = 20

## Catégories de la colonne de gauche.
const CATEGORIES: Array[Dictionary] = [
	{"id": "profile", "label": "Profil", "icon": "res://assets/icons/user.svg",
		"hint": "Ton pseudo et ta photo, affichés en haut de l'interface."},
	{"id": "appearance", "label": "Apparence", "icon": "res://assets/icons/controller.svg",
		"hint": "Style de l'interface et affichage des touches manette."},
	{"id": "boot", "label": "Démarrage", "icon": "res://assets/icons/video.svg",
		"hint": "Vidéo jouée au lancement de la console. Format attendu : .ogv (Ogg Theora), le seul que Godot lit nativement."},
	{"id": "games", "label": "Jeux", "icon": "res://assets/icons/library.svg",
		"hint": "Dossiers où chercher tes jeux. Un sous-dossier par jeu."},
	{"id": "system", "label": "Système", "icon": "res://assets/icons/settings.svg",
		"hint": "État et télémétrie de la console."},
]

@onready var _page: ColorRect = $Page
@onready var _safe: MarginContainer = $Safe
@onready var _page_scroll: ScrollContainer = $Safe/Layout/PageScroll
@onready var _page_content: VBoxContainer = $Safe/Layout/PageScroll/PageContent
@onready var _gap_top: Control = $Safe/Layout/PageScroll/PageContent/GapTop
@onready var _page_title: Label = $Safe/Layout/PageScroll/PageContent/PageTitle
@onready var _gap_title: Control = $Safe/Layout/PageScroll/PageContent/GapTitle
@onready var _columns: HBoxContainer = $Safe/Layout/PageScroll/PageContent/Columns
@onready var _categories: VBoxContainer = $Safe/Layout/PageScroll/PageContent/Columns/Categories
@onready var _detail: PanelContainer = $Safe/Layout/PageScroll/PageContent/Columns/Detail
@onready var _detail_margin: MarginContainer = $Safe/Layout/PageScroll/PageContent/Columns/Detail/DetailMargin
@onready var _section_title: Label = $Safe/Layout/PageScroll/PageContent/Columns/Detail/DetailMargin/DetailLayout/SectionTitle
@onready var _section_hint: Label = $Safe/Layout/PageScroll/PageContent/Columns/Detail/DetailMargin/DetailLayout/SectionHint
@onready var _gap_rows: Control = $Safe/Layout/PageScroll/PageContent/Columns/Detail/DetailMargin/DetailLayout/GapRows
@onready var _rows: VBoxContainer = $Safe/Layout/PageScroll/PageContent/Columns/Detail/DetailMargin/DetailLayout/Rows
@onready var _status: Label = $Safe/Layout/Status
@onready var _help: HBoxContainer = $Safe/Layout/HelpBar
@onready var _browser: Control = $FolderBrowser
@onready var _keyboard: Control = $Keyboard
@onready var _avatars: Control = $AvatarPicker
@onready var _videos: Control = $BootVideoPicker
@onready var _scan_results: Control = $ScanResults
@onready var _metadata: Node = $MetadataFetcher

var _category_buttons: Array[Button] = []
var _row_buttons: Array[Button] = []
## Éléments d'affichage ajoutés au panneau (carte de profil) : libérés comme les lignes.
var _row_extras: Array[Control] = []
## Conteneur qui reçoit les lignes : la colonne du panneau, ou la colonne de
## droite de la page Profil quand la carte occupe la gauche.
var _row_parent: VBoxContainer = null
## Lecteur de l'aperçu de la vidéo de démarrage, arrêté dès qu'on quitte la page.
var _boot_player: VideoStreamPlayer = null
## Ligne qui avait le focus avant une reconstruction : changer un réglage détruit
## les boutons, et le focus doit revenir à sa place, jamais se perdre.
var _focus_row: int = -1
var _current: String = "profile"

func _ready() -> void:
	_apply_layout()
	_build_categories()
	Settings.changed.connect(_refresh_rows)
	GameLibrary.library_loaded.connect(func(_games: Array) -> void:
		_update_categories_text()
		_refresh_rows()
	)
	_browser.folder_chosen.connect(_on_folder_chosen)
	_browser.cancelled.connect(func() -> void: _status.text = "Sélection annulée.")
	_keyboard.validated.connect(_on_name_validated)
	_avatars.avatar_chosen.connect(_on_avatar_chosen)
	_videos.video_chosen.connect(_on_video_chosen)
	# Une modale qui se ferme rend le focus : la ligne d'origine a pu être
	# reconstruite entre-temps.
	_avatars.closed.connect(_restore_row_focus)
	_videos.closed.connect(_restore_row_focus)
	_scan_results.confirmed.connect(_on_scan_confirmed)
	_scan_results.closed.connect(_restore_row_focus)
	_metadata.progress.connect(_on_metadata_progress)
	_metadata.finished.connect(_on_metadata_finished)
	_keyboard.cancelled.connect(_restore_row_focus)
	_keyboard.validated.connect(func(_text: String) -> void: _restore_row_focus.call_deferred())
	# L'écran reste vivant quand on le quitte : l'aperçu ne doit pas tourner
	# dans le vide derrière un autre écran.
	visibility_changed.connect(_update_preview)
	_select(_current)
	if not _category_buttons.is_empty():
		_category_buttons[0].grab_focus()

## Ouvre le navigateur de dossiers (outil de capture).
func open_browser() -> void:
	_browser.open()

## Affiche une catégorie donnée et y place le focus (outil de capture).
func select_category(id: String) -> void:
	for i: int in CATEGORIES.size():
		if str(CATEGORIES[i]["id"]) == id:
			_select(id)
			_category_buttons[i].grab_focus()
			return

## Ouvre la grille des photos de profil (outil de capture).
func open_avatars() -> void:
	_avatars.open(Settings.avatar_path)

## Lance la détection et ouvre ses résultats (outil de capture).
func open_detect() -> void:
	_on_detect_pressed()

## Lance le téléchargement des métadonnées (outil de capture).
func open_metadata() -> void:
	_on_metadata_pressed()

## Ouvre la liste des vidéos d'introduction (outil de capture).
func open_videos() -> void:
	_videos.open(Settings.boot_video_path)

## Ouvre le clavier (outil de capture).
func open_keyboard() -> void:
	_keyboard.open("Ton pseudo", Settings.profile_name)

func _unhandled_input(event: InputEvent) -> void:
	if _browser.is_open or _keyboard.is_open or _avatars.is_open or _videos.is_open or _scan_results.is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		# B ramène d'abord aux catégories, puis quitte l'écran.
		var focused: Control = get_viewport().gui_get_focus_owner()
		if focused != null and _rows.is_ancestor_of(focused) and not _category_buttons.is_empty():
			_focus_category()
			return
		back_requested.emit()

func _apply_layout() -> void:
	_page.color = UITheme.COLOR_PAGE

	var margin: Vector2 = UITheme.safe_margin()
	_safe.add_theme_constant_override("margin_left", int(margin.x))
	_safe.add_theme_constant_override("margin_right", int(margin.x))
	_safe.add_theme_constant_override("margin_top", int(margin.y))
	_safe.add_theme_constant_override("margin_bottom", int(margin.y))

	# Gaps serrés : la place gagnée va aux options, qui doivent tenir sans défiler.
	_gap_top.custom_minimum_size.y = UITheme.SPACING_SMALL
	_gap_title.custom_minimum_size.y = UITheme.SPACING_MEDIUM
	_gap_rows.custom_minimum_size.y = UITheme.SPACING_MEDIUM
	_columns.add_theme_constant_override("separation", int(UITheme.SPACING_LARGE))
	_categories.add_theme_constant_override("separation", ROW_SEPARATION)
	_rows.add_theme_constant_override("separation", ROW_SEPARATION)
	_categories.custom_minimum_size.x = UITheme.SETTINGS_CATEGORY_WIDTH

	# Barre de défilement élégante et discrète sur le bord de l'écran
	var scrollbar: VScrollBar = _page_scroll.get_v_scroll_bar()
	scrollbar.custom_minimum_size.x = 6.0
	var empty_box := StyleBoxEmpty.new()
	scrollbar.add_theme_stylebox_override("scroll", empty_box)
	scrollbar.add_theme_stylebox_override("scroll_focus", empty_box)
	var thumb := StyleBoxFlat.new()
	thumb.bg_color = Color(1.0, 1.0, 1.0, 0.20)
	thumb.set_corner_radius_all(3)
	scrollbar.add_theme_stylebox_override("grabber", thumb)
	scrollbar.add_theme_stylebox_override("grabber_highlight", thumb)
	scrollbar.add_theme_stylebox_override("grabber_pressed", thumb)

	var panel := StyleBoxFlat.new()
	panel.bg_color = UITheme.COLOR_PAGE_PANEL
	panel.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS)
	_detail.add_theme_stylebox_override("panel", panel)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_detail_margin.add_theme_constant_override(side, int(UITheme.SPACING_MEDIUM_LARGE))

	_page_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_PAGE_TITLE)
	_page_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_section_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	_section_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	for label: Label in [_section_hint, _status]:
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)

	_help.set_actions(ControllerGlyphs.actions([
		{"action": "ui_accept", "label": "Valider"},
		{"action": "ui_cancel", "label": "Retour"},
	]))

func _category_label(entry: Dictionary) -> String:
	if str(entry.get("id", "")) == "games":
		return "Jeux (%d)" % GameLibrary.games.size()
	return str(entry.get("label", ""))

func _update_categories_text() -> void:
	for i: int in CATEGORIES.size():
		if i < _category_buttons.size():
			var lbl: Label = _category_buttons[i].get_node_or_null("Row/CategoryLabel")
			if lbl != null:
				lbl.text = _category_label(CATEGORIES[i])

func _build_categories() -> void:
	for entry: Dictionary in CATEGORIES:
		var button: Button = _make_category(_category_label(entry), str(entry["icon"]))
		button.pressed.connect(_on_category_pressed.bind(str(entry["id"])))
		button.focus_entered.connect(_select.bind(str(entry["id"])))
		_categories.add_child(button)
		_category_buttons.append(button)

	for i: int in _category_buttons.size():
		var button: Button = _category_buttons[i]
		button.focus_neighbor_top = button.get_path_to(_category_buttons[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(_category_buttons[mini(i + 1, _category_buttons.size() - 1)])
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom

## Parcourir les catégories met à jour le panneau de droite sans y entrer :
## on voit ce que contient chaque section avant de s'y engager.
func _select(id: String) -> void:
	_current = id
	if _page_scroll != null:
		_page_scroll.scroll_vertical = 0
	for entry: Dictionary in CATEGORIES:
		if str(entry["id"]) == id:
			_section_title.text = _category_label(entry)
			_section_hint.text = str(entry["hint"])
	_refresh_rows()

func _on_category_pressed(id: String) -> void:
	_select(id)
	# Valider une catégorie fait passer le focus à ses options.
	for button: Button in _row_buttons:
		if button.focus_mode != Control.FOCUS_NONE:
			button.grab_focus()
			return

func _refresh_rows() -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and _rows.is_ancestor_of(focused):
		_focus_row = _row_buttons.find(focused)
	for row: Button in _row_buttons:
		row.queue_free()
	_row_buttons.clear()
	for extra: Control in _row_extras:
		extra.queue_free()
	_row_extras.clear()
	_boot_player = null
	_row_parent = _rows

	match _current:
		"profile":
			_build_profile_rows()
		"appearance":
			_build_appearance_rows()
		"boot":
			_build_boot_rows()
		"games":
			_build_games_rows()
		"system":
			_build_system_rows()
	_link_rows()
	# Les boutons viennent d'entrer dans l'arbre : on rend le focus à la frame
	# suivante, sinon `grab_focus` n'a encore rien à saisir.
	_restore_row_focus.call_deferred()

## Profil : une carte de présentation (photo ronde + pseudo) puis les actions,
## à la manière de la page « gamertag » de la Xbox.
func _build_profile_rows() -> void:
	var has_avatar: bool = not Settings.avatar_path.is_empty()
	_add_side_card(_profile_card(has_avatar))
	_add_row("Modifier le pseudo", func() -> void:
		_keyboard.open("Ton pseudo", Settings.profile_name)
	)
	_add_row("Changer la photo de profil", func() -> void:
		_avatars.open(Settings.avatar_path)
	)

## Apparence : carte d'aperçu manettes & choix de la disposition des touches.
func _build_appearance_rows() -> void:
	_add_side_card(_appearance_card())
	_add_button_layout_row()

## Carte de présentation à gauche, colonne d'actions à droite (page Profil et
## page Démarrage). La carte s'affiche mais ne prend jamais le focus : c'est un
## aperçu, pas une action. Les lignes ajoutées ensuite vont dans la colonne.
func _add_side_card(content: Control) -> void:
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", UITheme.SETTINGS_PROFILE_GAP)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(UITheme.SETTINGS_PROFILE_CARD_WIDTH, UITheme.SETTINGS_PROFILE_CARD_HEIGHT)
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var card_box: StyleBoxFlat = UITheme.surface_box()
	for side: String in ["content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		card_box.set(side, float(UITheme.SPACING_MEDIUM))
	card.add_theme_stylebox_override("panel", card_box)
	card.add_child(content)

	var actions := VBoxContainer.new()
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_theme_constant_override("separation", ROW_SEPARATION)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE

	columns.add_child(card)
	columns.add_child(actions)
	_rows.add_child(columns)
	_row_extras.append(columns)
	_row_parent = actions

## Contenu de la carte Profil : photo ronde, pseudo, nom du fichier.
func _profile_card(has_avatar: bool) -> Control:
	var identity := VBoxContainer.new()
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	identity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity.add_child(AvatarView.make(Settings.avatar_path if has_avatar else "", UITheme.SETTINGS_AVATAR_SIZE, Settings.profile_name))
	identity.add_child(_card_label(Settings.profile_name, UITheme.FONT_SIZE_TITLE, UITheme.COLOR_TEXT))
	identity.add_child(_card_label("Photo :  %s" % (Settings.avatar_path.get_file().get_basename() if has_avatar else "aucune"), UITheme.FONT_SIZE_SMALL, UITheme.COLOR_TEXT_DIM))
	return identity

## Contenu de la carte Démarrage : la vidéo elle-même, jouée en boucle et sans
## son, pour voir ce qui s'affichera au lancement de la console.
func _boot_card(has_video: bool) -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var frame := Panel.new()
	frame.custom_minimum_size = UITheme.BOOT_PREVIEW_SIZE
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var frame_box := StyleBoxFlat.new()
	frame_box.bg_color = UITheme.COLOR_BACKGROUND
	frame_box.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS)
	frame.add_theme_stylebox_override("panel", frame_box)

	var stream: VideoStream = MediaCatalog.video_stream(Settings.boot_video_path) if has_video else null
	if stream != null:
		var player := VideoStreamPlayer.new()
		player.stream = stream
		player.set_anchors_preset(Control.PRESET_FULL_RECT)
		player.expand = true
		player.loop = true
		player.volume_db = -80.0
		player.autoplay = true
		player.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(player)
		_boot_player = player
	else:
		var empty := Label.new()
		empty.text = "Aucune vidéo" if not has_video else "Vidéo illisible"
		empty.set_anchors_preset(Control.PRESET_FULL_RECT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		empty.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(empty)

	column.add_child(frame)
	column.add_child(_card_label(MediaCatalog.pretty_name(Settings.boot_video_path) if has_video else "Aperçu", UITheme.FONT_SIZE_BODY, UITheme.COLOR_TEXT))
	var state: String = "Aucune vidéo choisie"
	if has_video:
		state = "Jouée au démarrage :  %s" % ("oui" if Settings.boot_video_enabled else "non")
	column.add_child(_card_label(state, UITheme.FONT_SIZE_SMALL, UITheme.COLOR_TEXT_DIM))
	return column

func _card_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

## Démarrage : l'aperçu de la vidéo à gauche, les actions à droite.
func _build_boot_rows() -> void:
	var has_video: bool = not Settings.boot_video_path.is_empty()
	_add_side_card(_boot_card(has_video))
	_add_row("Choisir la vidéo", func() -> void:
		_videos.open(Settings.boot_video_path)
	)
	_add_toggle_row("Jouer au démarrage", Settings.boot_video_enabled, func() -> void:
		Settings.set_boot_video_enabled(not Settings.boot_video_enabled)
	, has_video)

	if has_video and not MediaCatalog.exists(Settings.boot_video_path):
		_status.text = "La vidéo configurée est introuvable."

func _build_games_rows() -> void:
	_add_row("Rechercher les jeux installés", _on_detect_pressed)
	_add_row("Compléter les fiches (notes, résumés)", _on_metadata_pressed)
	_add_row("Télécharger les jaquettes manquantes", _on_fetch_covers_pressed)
	_add_row("Ajouter un dossier", func() -> void: _browser.open())
	_add_row("Scanner la bibliothèque", _on_scan_pressed)
	for folder: String in Settings.game_folders:
		var display_name: String = folder.get_file()
		if display_name.is_empty():
			display_name = folder
		_add_row("Dossier : %s  (retirer)" % display_name, _on_folder_pressed.bind(folder))
	var has_samples: bool = false
	for game: GameEntry in GameLibrary.games:
		if game.source == "sample":
			has_samples = true
			break
	if has_samples:
		_add_row("Retirer les jeux d'exemple", _on_clean_pressed)

## Informations réelles sur la machine : présentées en fiches télémétriques avec carte console.
func _build_system_rows() -> void:
	_add_side_card(_system_card())
	_add_info_row("Plateforme", OS.get_name(), "Système d'exploitation : %s" % OS.get_name())
	var engine_ver: String = str(Engine.get_version_info()["string"])
	_add_info_row("Moteur", "Godot %s" % engine_ver, "Moteur : Godot Engine %s" % engine_ver)
	var pads_count: int = Input.get_connected_joypads().size()
	var pad_desc: String = "%d connectée(s)" % pads_count if pads_count > 0 else "Clavier / Aucun"
	_add_info_row("Manettes", pad_desc, "%d manette(s) détectée(s)" % pads_count)
	_add_info_row("Configuration", "settings.json", "Fichier : %s" % ProjectSettings.globalize_path(Settings.PATH))

func _games_card() -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_badge := Panel.new()
	icon_badge.custom_minimum_size = Vector2(120, 120)
	icon_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_box := StyleBoxFlat.new()
	icon_box.bg_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.12)
	icon_box.set_corner_radius_all(60)
	icon_box.set_border_width_all(2)
	icon_box.border_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.35)
	icon_badge.add_theme_stylebox_override("panel", icon_box)

	var icon := TextureRect.new()
	icon.texture = load("res://assets/icons/library.svg")
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 32.0
	icon.offset_top = 32.0
	icon.offset_right = -32.0
	icon.offset_bottom = -32.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = UITheme.COLOR_ACCENT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_badge.add_child(icon)

	column.add_child(icon_badge)
	column.add_child(_card_label("%d jeux installés" % GameLibrary.games.size(), UITheme.FONT_SIZE_TITLE, UITheme.COLOR_TEXT))
	column.add_child(_card_label("%d dossier(s) suivi(s)" % Settings.game_folders.size(), UITheme.FONT_SIZE_SMALL, UITheme.COLOR_TEXT_DIM))
	return column

func _system_card() -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_badge := Panel.new()
	icon_badge.custom_minimum_size = Vector2(120, 120)
	icon_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_box := StyleBoxFlat.new()
	icon_box.bg_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.12)
	icon_box.set_corner_radius_all(60)
	icon_box.set_border_width_all(2)
	icon_box.border_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.35)
	icon_badge.add_theme_stylebox_override("panel", icon_box)

	var icon := TextureRect.new()
	icon.texture = load("res://assets/icons/settings.svg")
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 32.0
	icon.offset_top = 32.0
	icon.offset_right = -32.0
	icon.offset_bottom = -32.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = UITheme.COLOR_ACCENT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_badge.add_child(icon)

	var version_info: Dictionary = Engine.get_version_info()
	var godot_short: String = "%d.%d" % [version_info["major"], version_info["minor"]]

	column.add_child(icon_badge)
	column.add_child(_card_label("Interface Console", UITheme.FONT_SIZE_TITLE, UITheme.COLOR_TEXT))
	column.add_child(_card_label("%s · Godot %s" % [OS.get_name(), godot_short], UITheme.FONT_SIZE_SMALL, UITheme.COLOR_TEXT_DIM))
	return column

func _appearance_card() -> Control:
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", UITheme.SPACING_MEDIUM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon_badge := Panel.new()
	icon_badge.custom_minimum_size = Vector2(120, 120)
	icon_badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_box := StyleBoxFlat.new()
	icon_box.bg_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.12)
	icon_box.set_corner_radius_all(60)
	icon_box.set_border_width_all(2)
	icon_box.border_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.35)
	icon_badge.add_theme_stylebox_override("panel", icon_box)

	var icon := TextureRect.new()
	icon.texture = load("res://assets/icons/controller.svg")
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 32.0
	icon.offset_top = 32.0
	icon.offset_right = -32.0
	icon.offset_bottom = -32.0
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = UITheme.COLOR_ACCENT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_badge.add_child(icon)

	column.add_child(icon_badge)
	column.add_child(_card_label("Manettes & Touches", UITheme.FONT_SIZE_TITLE, UITheme.COLOR_TEXT))
	column.add_child(_card_label("Disposition : %s" % ControllerGlyphs.layout_name(), UITheme.FONT_SIZE_SMALL, UITheme.COLOR_TEXT_DIM))
	return column

## Ajoute une ligne. Sans action, ou désactivée, elle reste affichée mais n'est
## pas sélectionnable : une information se lit, elle ne se valide pas.
func _add_row(text: String, action: Callable, enabled: bool = true) -> void:
	var button: Button = _make_row(text)
	if action.is_valid() and enabled:
		button.pressed.connect(action)
	else:
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
	_row_parent.add_child(button)
	_row_buttons.append(button)

## Ajoute une ligne avec interrupteur à bascule (Toggle switch On/Off visuel).
func _add_toggle_row(label_text: String, is_on: bool, action: Callable, enabled: bool = true) -> void:
	var button: Button = _make_toggle_row(label_text, is_on)
	if action.is_valid() and enabled:
		button.pressed.connect(action)
	else:
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
	_row_parent.add_child(button)
	_row_buttons.append(button)

## Ligne d'information télémétrique (titre à gauche en gris, valeur à droite en blanc).
## Reste focalisable pour permettre à la manette d'entrer dans le panneau.
func _add_info_row(title: String, value: String, status_info: String = "") -> void:
	var button := Button.new()
	button.custom_minimum_size.y = 86.0
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", _row_box(false))
	button.add_theme_stylebox_override("hover", _row_box(false))
	button.add_theme_stylebox_override("pressed", _row_box(true))
	button.add_theme_stylebox_override("focus", _row_box(true))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UITheme.SPACING_LARGE
	row.offset_right = -UITheme.SPACING_LARGE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label_title := Label.new()
	label_title.text = title
	label_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	label_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	label_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label_title)

	var label_value := Label.new()
	label_value.text = value
	label_value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_value.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	label_value.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label_value)

	button.add_child(row)
	if not status_info.is_empty():
		button.pressed.connect(func() -> void: _status.text = status_info)
	_row_parent.add_child(button)
	_row_buttons.append(button)

## Ligne interactive pour basculer la disposition des touches (Auto / Xbox / PlayStation)
func _add_button_layout_row() -> void:
	var button := Button.new()
	button.custom_minimum_size.y = 86.0
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", _row_box(false))
	button.add_theme_stylebox_override("hover", _row_box(false))
	button.add_theme_stylebox_override("pressed", _row_box(true))
	button.add_theme_stylebox_override("focus", _row_box(true))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UITheme.SPACING_LARGE
	row.offset_right = -UITheme.SPACING_LARGE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label_title := Label.new()
	label_title.text = "Affichage des touches"
	label_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	label_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label_title)

	var right_box := HBoxContainer.new()
	right_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	right_box.add_theme_constant_override("separation", 12)
	right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var mode_name: String = ""
	match Settings.button_layout:
		"xbox":
			mode_name = "Xbox"
		"ps5":
			mode_name = "PlayStation"
		_:
			var detected_name: String = "PS5" if ControllerGlyphs.detected_layout() == ControllerGlyphs.Layout.PLAYSTATION else "Xbox"
			mode_name = "Auto (%s)" % detected_name

	var pill := PanelContainer.new()
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pill_box := StyleBoxFlat.new()
	pill_box.bg_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.15)
	pill_box.border_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.40)
	pill_box.set_border_width_all(1)
	pill_box.set_corner_radius_all(12)
	pill_box.content_margin_left = 12.0
	pill_box.content_margin_right = 12.0
	pill_box.content_margin_top = 4.0
	pill_box.content_margin_bottom = 4.0
	pill.add_theme_stylebox_override("panel", pill_box)

	var label_value := Label.new()
	label_value.text = "%s  ▸" % mode_name
	label_value.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	label_value.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	label_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(label_value)
	right_box.add_child(pill)

	row.add_child(right_box)
	button.add_child(row)

	button.pressed.connect(func() -> void:
		var next_mode: String = "xbox"
		match Settings.button_layout:
			"auto":
				next_mode = "xbox"
			"xbox":
				next_mode = "ps5"
			"ps5":
				next_mode = "auto"
			_:
				next_mode = "auto"
		Settings.set_button_layout(next_mode)
		var readable: String = "Automatique"
		if next_mode == "xbox":
			readable = "Xbox"
		elif next_mode == "ps5":
			readable = "PlayStation (PS5)"
		_status.text = "Affichage des touches : %s" % readable
	)

	_row_parent.add_child(button)
	_row_buttons.append(button)

func _link_rows() -> void:
	var column: Array[Button] = _focusable_rows()
	for i: int in column.size():
		var button: Button = column[i]
		button.focus_neighbor_top = button.get_path_to(column[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(column[mini(i + 1, column.size() - 1)])
		button.focus_neighbor_right = button.get_path_to(button)
		# Revenir vers la gauche ramène à la catégorie courante.
		button.focus_neighbor_left = button.get_path_to(_current_category_button())
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom

	# Depuis les catégories, aller à droite entre dans les options.
	for button: Button in _category_buttons:
		button.focus_neighbor_right = button.get_path_to(column[0] if not column.is_empty() else button)

## Rend le focus à la ligne qui l'avait, après qu'un réglage a reconstruit le
## panneau. Ne fait rien tant qu'une fenêtre modale est ouverte : c'est elle qui
## a le focus, et elle le rendra en se fermant.
func _restore_row_focus() -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	if _browser.is_open or _keyboard.is_open or _avatars.is_open or _videos.is_open or _scan_results.is_open:
		return
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused) and not focused.is_queued_for_deletion():
		return
	var column: Array[Button] = _focusable_rows()
	if column.is_empty():
		_focus_category()
		return
	var index: int = clampi(_focus_row, 0, column.size() - 1)
	column[index].grab_focus()

func _focusable_rows() -> Array[Button]:
	var column: Array[Button] = []
	for button: Button in _row_buttons:
		if button.focus_mode != Control.FOCUS_NONE:
			column.append(button)
	return column

func _current_category_button() -> Control:
	for i: int in CATEGORIES.size():
		if str(CATEGORIES[i]["id"]) == _current:
			return _category_buttons[i]
	return _category_buttons[0]

func _focus_category() -> void:
	_current_category_button().grab_focus()

## Met l'aperçu en pause quand l'écran passe en arrière-plan.
func _update_preview() -> void:
	if _boot_player != null and is_instance_valid(_boot_player):
		_boot_player.paused = not is_visible_in_tree()

func _on_avatar_chosen(path: String) -> void:
	Settings.set_avatar(path)
	_status.text = "Photo de profil retirée." if path.is_empty() else "Photo de profil mise à jour."

func _on_video_chosen(path: String) -> void:
	Settings.set_boot_video(path)
	_status.text = "Aucune vidéo au démarrage." if path.is_empty() else "Vidéo d'introduction enregistrée."

func _on_name_validated(text: String) -> void:
	Settings.set_profile_name(text)
	_status.text = "Pseudo enregistré."


func _on_folder_pressed(folder: String) -> void:
	Settings.remove_folder(folder)
	_status.text = "Dossier retiré : %s" % folder

func _on_folder_chosen(path: String) -> void:
	if Settings.add_folder(path):
		_status.text = "Dossier ajouté : %s" % path
		_on_scan_pressed()
	else:
		_status.text = "Ce dossier est déjà suivi."

## Détection automatique : Steam, Epic et les raccourcis. Rien n'entre dans la
## bibliothèque sans passer par la fenêtre de validation.
func _on_detect_pressed() -> void:
	_status.text = "Recherche en cours…"
	var found: Array[GameEntry] = GameFinder.find_all()
	if found.is_empty():
		_status.text = "Aucun jeu détecté (Steam, Epic, raccourcis)."
		return
	_status.text = "%d jeu(x) détecté(s)." % found.size()
	_scan_results.open(found)

func _on_scan_confirmed(games: Array[GameEntry]) -> void:
	var added: int = GameLibrary.merge_scanned(games)
	_status.text = "%d jeu(x) ajouté(s) à la bibliothèque." % added
	# Enchaînement automatique : un jeu ajouté doit arriver avec sa jaquette,
	# sans que l'utilisateur ait à demander quoi que ce soit.
	_metadata.fetch_for(games)

## Notes, genres, dates et résumés, depuis les données publiques de Steam :
## aucune clé, aucun compte, rien à configurer. Les jaquettes, elles, sont du
## ressort de `CoverFetcher`.
func _on_metadata_pressed() -> void:
	if _metadata.is_running:
		_status.text = "Téléchargement déjà en cours…"
		return
	_metadata.fetch_for(GameLibrary.games)

func _on_metadata_progress(done: int, total: int, title: String) -> void:
	_status.text = "Fiches : %d / %d  —  %s" % [done + 1, total, title]

func _on_metadata_finished(updated: int, missed: int) -> void:
	if updated > 0:
		GameLibrary.save_library()
		GameLibrary.library_loaded.emit(GameLibrary.games)
	if updated == 0 and missed == 0:
		_status.text = "Toutes les fiches sont déjà complètes."
	else:
		_status.text = "%d fiche(s) complétée(s), %d jeu(x) inconnu(s) chez Steam." % [updated, missed]
	CoverFetcher.fetch_all_missing()

func _on_fetch_covers_pressed() -> void:
	_status.text = "Récupération automatique des jaquettes en cours (sans clé API)…"
	CoverFetcher.fetch_all_missing()

func _on_scan_pressed() -> void:
	if Settings.game_folders.is_empty():
		_status.text = "Ajoute d'abord un dossier de jeux."
		return
	var found: Array[GameEntry] = GameScanner.scan(Settings.game_folders)
	var added: int = GameLibrary.merge_scanned(found)
	_status.text = "%d jeu(x) trouvé(s), dont %d nouveau(x)." % [found.size(), added]

func _on_clean_pressed() -> void:
	var removed: int = GameLibrary.remove_samples()
	_status.text = "%d jeu(x) d'exemple retiré(s)." % removed if removed > 0 else "Aucun jeu d'exemple à retirer."

## Catégorie : icône de taille fixe puis libellé, alignés sur une colonne.
func _make_category(label_text: String, icon_path: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(UITheme.SETTINGS_CATEGORY_WIDTH, UITheme.SETTINGS_CATEGORY_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", UITheme.surface_box())
	button.add_theme_stylebox_override("hover", UITheme.surface_box())
	button.add_theme_stylebox_override("pressed", UITheme.focus_box())
	button.add_theme_stylebox_override("focus", UITheme.focus_box())

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", ICON_GAP)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UITheme.SPACING_LARGE
	row.offset_right = -UITheme.SPACING_MEDIUM
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var icon := TextureRect.new()
	icon.texture = load(icon_path)
	icon.custom_minimum_size = ICON_SIZE
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = UITheme.COLOR_TEXT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.name = "CategoryLabel"
	label.text = label_text
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	row.add_child(icon)
	row.add_child(label)
	button.add_child(row)
	return button

func _make_row(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = UITheme.SETTINGS_ROW_HEIGHT
	button.focus_mode = Control.FOCUS_ALL
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	button.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", UITheme.COLOR_TEXT_DIM)
	button.add_theme_stylebox_override("normal", _row_box(false))
	button.add_theme_stylebox_override("hover", _row_box(false))
	button.add_theme_stylebox_override("disabled", _row_box(false))
	button.add_theme_stylebox_override("pressed", _row_box(true))
	button.add_theme_stylebox_override("focus", _row_box(true))
	return button

func _make_toggle_row(label_text: String, is_on: bool) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = UITheme.SETTINGS_ROW_HEIGHT
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", _row_box(false))
	button.add_theme_stylebox_override("hover", _row_box(false))
	button.add_theme_stylebox_override("disabled", _row_box(false))
	button.add_theme_stylebox_override("pressed", _row_box(true))
	button.add_theme_stylebox_override("focus", _row_box(true))

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UITheme.SPACING_LARGE
	row.offset_right = -UITheme.SPACING_LARGE
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := Label.new()
	label.text = label_text
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	var switch := Panel.new()
	switch.custom_minimum_size = Vector2(72, 40)
	switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	switch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var switch_box := StyleBoxFlat.new()
	switch_box.set_corner_radius_all(20)
	if is_on:
		switch_box.bg_color = UITheme.COLOR_ACCENT
	else:
		switch_box.bg_color = Color("222733")
		switch_box.set_border_width_all(2)
		switch_box.border_color = Color("384152")
	switch.add_theme_stylebox_override("panel", switch_box)

	var knob := Panel.new()
	knob.custom_minimum_size = Vector2(30, 30)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var knob_box := StyleBoxFlat.new()
	knob_box.set_corner_radius_all(15)
	knob_box.bg_color = Color.WHITE if is_on else Color("7a869a")
	knob.add_theme_stylebox_override("panel", knob_box)
	knob.set_anchors_preset(Control.PRESET_TOP_LEFT)
	if is_on:
		knob.offset_left = 37.0
		knob.offset_top = 5.0
		knob.offset_right = 67.0
		knob.offset_bottom = 35.0
	else:
		knob.offset_left = 5.0
		knob.offset_top = 5.0
		knob.offset_right = 35.0
		knob.offset_bottom = 35.0
	switch.add_child(knob)

	row.add_child(switch)
	button.add_child(row)
	return button

func _row_box(focused: bool) -> StyleBoxFlat:
	var box: StyleBoxFlat = UITheme.focus_box() if focused else UITheme.surface_box()
	box.content_margin_left = UITheme.SPACING_LARGE
	box.content_margin_right = UITheme.SPACING_MEDIUM
	return box
