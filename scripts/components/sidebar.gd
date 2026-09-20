extends Control

## Panneau latéral gauche, ouvert par la touche Options.
## Chaque entrée suit la même trame : une icône de taille fixe, puis le libellé
## sur une colonne unique. Sans cela, les textes ne s'alignent pas entre eux.

signal closed()
signal power_requested()
signal navigate(action: String)

const WIDTH: float = 420.0
const ENTRY_HEIGHT: float = 68.0
const ENTRY_SEPARATION: int = 6
const ICON_SIZE: Vector2 = Vector2(30, 30)
## Écart entre l'icône et le libellé : fixe, pour que tous les textes partent
## de la même abscisse.
const ICON_GAP: int = 18
const PAD_ICON_SIZE: Vector2 = Vector2(28, 28)

## Entrées du panneau : chacune a son icône, aucune n'en est dépourvue.
const ENTRIES: Array[Dictionary] = [
	{"label": "Bibliothèque", "icon": "res://assets/icons/library.svg", "action": "library"},
	{"label": "Paramètres", "icon": "res://assets/icons/settings.svg", "action": "settings"},
	{"label": "Alimentation", "icon": "res://assets/icons/power.svg", "action": "power"},
]

@onready var _scrim: ColorRect = $Scrim
@onready var _panel: Panel = $Panel
@onready var _margin: MarginContainer = $Panel/Margin
@onready var _content: VBoxContainer = $Panel/Margin/Content
@onready var _header: HBoxContainer = $Panel/Margin/Content/Header
@onready var _avatar: Panel = $Panel/Margin/Content/Header/Avatar
@onready var _avatar_image: TextureRect = $Panel/Margin/Content/Header/Avatar/AvatarImage
@onready var _initial: Label = $Panel/Margin/Content/Header/Avatar/Initial
@onready var _identity: VBoxContainer = $Panel/Margin/Content/Header/Identity
@onready var _name: Label = $Panel/Margin/Content/Header/Identity/Name
@onready var _stat: Label = $Panel/Margin/Content/Header/Identity/Stat
@onready var _gap_header: Control = $Panel/Margin/Content/GapHeader
@onready var _entries: VBoxContainer = $Panel/Margin/Content/Entries
@onready var _status: HBoxContainer = $Panel/Margin/Content/Status
@onready var _pad_icon: TextureRect = $Panel/Margin/Content/Status/PadIcon
@onready var _pad_label: Label = $Panel/Margin/Content/Status/PadLabel
@onready var _help: Label = $Panel/Margin/Content/Help

var is_open: bool = false

var _buttons: Array[Button] = []
var _return_target: Control = null
var _tween: Tween = null

func _ready() -> void:
	_style()
	_build_entries()
	# Fermé, le panneau est hors écran à gauche ; ses boutons restent focalisables
	# pour que l'ouverture puisse leur donner le focus immédiatement.
	_set_shift(WIDTH)
	_scrim.color = Color(UITheme.COLOR_BACKGROUND, 0.0)
	get_viewport().gui_focus_changed.connect(_on_focus_changed)

	Settings.changed.connect(_refresh_stats)
	GameLibrary.library_loaded.connect(func(_games: Array) -> void: _refresh_stats())
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: _refresh_stats())
	_refresh_stats()

## Élément à re-sélectionner quand le panneau se referme sur un retour explicite.
func set_return_target(target: Control) -> void:
	_return_target = target

## Premier bouton du panneau, pour lui donner le focus à l'ouverture.
func first_entry() -> Control:
	return _buttons[0] if not _buttons.is_empty() else null

func open() -> void:
	if is_open:
		return
	is_open = true
	_refresh_stats()
	_animate(0.0, UITheme.SIDEBAR_SCRIM_ALPHA)
	_focus_first()

func close() -> void:
	if not is_open:
		return
	is_open = false
	_animate(WIDTH, 0.0)
	closed.emit()

## Le panneau est ancré au bord gauche : on décale ses offsets, pas sa position
## absolue, qui serait recalculée par les ancres.
func _set_shift(shift: float) -> void:
	_panel.offset_left = -shift
	_panel.offset_right = WIDTH - shift

func _animate(shift: float, scrim_alpha: float) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	_tween.tween_property(_panel, "offset_left", -shift, UITheme.ANIM_SELECT)
	_tween.tween_property(_panel, "offset_right", WIDTH - shift, UITheme.ANIM_SELECT)
	_tween.tween_property(_scrim, "color:a", scrim_alpha, UITheme.ANIM_SELECT)

## Le panneau s'ouvre dès qu'un de ses boutons prend le focus, et se referme
## dès que le focus repart ailleurs : aucune touche dédiée à retenir.
func _on_focus_changed(node: Control) -> void:
	var inside: bool = node != null and _panel.is_ancestor_of(node)
	if inside and not is_open:
		open()
	elif not inside and is_open:
		close()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		# Rendre le focus referme le panneau via `gui_focus_changed`.
		if _return_target != null and is_instance_valid(_return_target):
			_return_target.grab_focus()
		else:
			close()
		closed.emit()

func _build_entries() -> void:
	_entries.add_theme_constant_override("separation", ENTRY_SEPARATION)
	for entry: Dictionary in ENTRIES:
		var button: Button = _make_entry(str(entry["label"]), str(entry["icon"]))
		button.pressed.connect(_on_entry_pressed.bind(str(entry["action"])))
		_entries.add_child(button)
		_buttons.append(button)
	_link()

## Une ligne = un bouton contenant une icône de taille fixe et un libellé.
## L'icône est posée dans un conteneur de largeur constante, sinon les libellés
## se décaleraient les uns par rapport aux autres.
func _make_entry(label_text: String, icon_path: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size.y = ENTRY_HEIGHT
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", _entry_box(false))
	button.add_theme_stylebox_override("hover", _entry_box(false))
	button.add_theme_stylebox_override("pressed", _entry_box(true))
	button.add_theme_stylebox_override("focus", _entry_box(true))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ICON_GAP)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = UITheme.SPACING_MEDIUM
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
	label.text = label_text
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	row.add_child(icon)
	row.add_child(label)
	button.add_child(row)
	return button

func _link() -> void:
	for i: int in _buttons.size():
		var button: Button = _buttons[i]
		button.focus_neighbor_top = button.get_path_to(_buttons[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(_buttons[mini(i + 1, _buttons.size() - 1)])
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom

func _on_entry_pressed(action: String) -> void:
	if action == "power":
		power_requested.emit()
		return
	navigate.emit(action)

func _focus_first() -> void:
	if not _buttons.is_empty():
		_buttons[0].grab_focus()

## Chiffres réels : taille de la bibliothèque et manettes détectées.
func _refresh_stats() -> void:
	_name.text = Settings.profile_name
	_initial.text = Settings.profile_name.substr(0, 1).to_upper()
	# Photo de profil si elle est définie, initiale du pseudo sinon.
	var avatar: Texture2D = ImageLoader.load_texture(Settings.avatar_path) if not Settings.avatar_path.is_empty() else null
	_avatar_image.texture = avatar
	_avatar_image.visible = avatar != null
	_initial.visible = avatar == null

	var count: int = GameLibrary.games.size()
	_stat.text = "%d jeux" % count if count > 1 else "%d jeu" % count

	var pads: int = Input.get_connected_joypads().size()
	_pad_label.text = "%d manettes connectées" % pads if pads > 1 else "%d manette connectée" % pads
	var tint: Color = UITheme.COLOR_TEXT if pads > 0 else UITheme.COLOR_TEXT_DIM
	_pad_icon.modulate = tint
	_pad_label.add_theme_color_override("font_color", tint)

func _entry_box(focused: bool) -> StyleBoxFlat:
	return UITheme.focus_box() if focused else UITheme.surface_box()

func _style() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = UITheme.COLOR_SIDEBAR
	_panel.add_theme_stylebox_override("panel", box)

	var margin: Vector2 = UITheme.safe_margin()
	for side: String in ["margin_left", "margin_right"]:
		_margin.add_theme_constant_override(side, int(UITheme.SPACING_LARGE))
	_margin.add_theme_constant_override("margin_top", int(margin.y))
	_margin.add_theme_constant_override("margin_bottom", int(margin.y))

	_content.add_theme_constant_override("separation", UITheme.SPACING_SMALL)
	_header.add_theme_constant_override("separation", ICON_GAP)
	_identity.add_theme_constant_override("separation", 2)
	_status.add_theme_constant_override("separation", ICON_GAP)
	_gap_header.custom_minimum_size.y = UITheme.SPACING_LARGE

	var avatar_box := StyleBoxFlat.new()
	avatar_box.bg_color = UITheme.COLOR_ACCENT
	avatar_box.set_corner_radius_all(28)
	_avatar.add_theme_stylebox_override("panel", avatar_box)

	_initial.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_initial.add_theme_color_override("font_color", UITheme.COLOR_BACKGROUND)
	_name.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_name.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	for label: Label in [_stat, _pad_label, _help]:
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)

	_pad_icon.texture = load("res://assets/icons/controller.svg")
	_pad_icon.custom_minimum_size = PAD_ICON_SIZE
