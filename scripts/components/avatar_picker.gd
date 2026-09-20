extends Control

## Fenêtre modale de choix de la photo de profil. Les photos sont fournies par
## la console (`MediaCatalog`) : on ne parcourt pas les dossiers du PC.
## La première case rend le profil à son initiale.

signal avatar_chosen(path: String)
signal closed()

const COLUMNS: int = 5
const HELP_BAR_SCENE: PackedScene = preload("res://scenes/components/help_bar.tscn")

@onready var _scrim: ColorRect = $Scrim
@onready var _dialog: Panel = $Dialog
@onready var _margin: MarginContainer = $Dialog/Margin
@onready var _title: Label = $Dialog/Margin/Content/Title
@onready var _gap: Control = $Dialog/Margin/Content/Gap
@onready var _grid: GridContainer = $Dialog/Margin/Content/Grid
@onready var _gap2: Control = $Dialog/Margin/Content/Gap2
@onready var _help: Label = $Dialog/Margin/Content/Help

var is_open: bool = false

var _buttons: Array[Button] = []
var _paths: PackedStringArray = PackedStringArray()
var _return_focus: Control = null

func _ready() -> void:
	_style()

## Ouvre la grille en plaçant le focus sur la photo actuelle.
func open(current: String = "") -> void:
	if is_open:
		return
	is_open = true
	_return_focus = get_viewport().gui_get_focus_owner()
	visible = true
	_populate()
	var index: int = maxi(_paths.find(current), 0)
	if not _buttons.is_empty():
		_buttons[index].grab_focus()

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	# Le réglage qu'on vient de changer a pu reconstruire la ligne d'origine :
	# on ne rend pas le focus à un bouton en cours de suppression.
	if _return_focus != null and is_instance_valid(_return_focus) and not _return_focus.is_queued_for_deletion():
		_return_focus.grab_focus()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func _populate() -> void:
	for button: Button in _buttons:
		button.queue_free()
	_buttons.clear()

	# Case vide en premier : revenir à l'initiale du pseudo.
	_paths = PackedStringArray([""])
	_paths.append_array(MediaCatalog.avatars())
	for path: String in _paths:
		var button: Button = _make_cell(path)
		button.pressed.connect(_on_chosen.bind(path))
		_grid.add_child(button)
		_buttons.append(button)
	_link()

## Navigation en grille : la dernière ligne peut être incomplète, on reste
## alors sur la dernière case plutôt que de perdre le focus.
func _link() -> void:
	var count: int = _buttons.size()
	for i: int in count:
		var button: Button = _buttons[i]
		var left: int = i - 1 if i % COLUMNS > 0 else i
		var right: int = i + 1 if i % COLUMNS < COLUMNS - 1 and i + 1 < count else i
		var up: int = i - COLUMNS if i - COLUMNS >= 0 else i
		var down: int = i + COLUMNS if i + COLUMNS < count else i
		button.focus_neighbor_left = button.get_path_to(_buttons[left])
		button.focus_neighbor_right = button.get_path_to(_buttons[right])
		button.focus_neighbor_top = button.get_path_to(_buttons[up])
		button.focus_neighbor_bottom = button.get_path_to(_buttons[down])
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right

func _on_chosen(path: String) -> void:
	avatar_chosen.emit(path)
	close()

func _make_cell(path: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2.ONE * UITheme.AVATAR_CELL_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("normal", UITheme.surface_box())
	button.add_theme_stylebox_override("hover", UITheme.surface_box())
	button.add_theme_stylebox_override("pressed", UITheme.focus_box())
	button.add_theme_stylebox_override("focus", UITheme.focus_box())

	# Le centrage passe par un conteneur : poser la pastille à la main dans un
	# Button la décale dès que la case change de taille.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(AvatarView.make(path, UITheme.AVATAR_PICK_SIZE, Settings.profile_name))
	button.add_child(center)
	return button

func _style() -> void:
	_scrim.color = Color(UITheme.COLOR_BACKGROUND, UITheme.SIDEBAR_SCRIM_ALPHA)

	var box := StyleBoxFlat.new()
	box.bg_color = UITheme.COLOR_SIDEBAR
	box.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS * 2)
	box.shadow_color = Color(0, 0, 0, UITheme.MODAL_SHADOW_ALPHA)
	box.shadow_size = UITheme.MODAL_SHADOW_SIZE
	_dialog.add_theme_stylebox_override("panel", box)

	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_margin.add_theme_constant_override(side, int(UITheme.SPACING_LARGE))
	_gap.custom_minimum_size.y = UITheme.SPACING_MEDIUM
	_gap2.custom_minimum_size.y = UITheme.SPACING_MEDIUM
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", UITheme.SPACING_MEDIUM)
	_grid.add_theme_constant_override("v_separation", UITheme.SPACING_MEDIUM)

	_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_help.visible = false
	var help_bar: HBoxContainer = HELP_BAR_SCENE.instantiate()
	help_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	help_bar.set_actions(ControllerGlyphs.actions([
		{"action": "ui_accept", "label": "Choisir"},
		{"action": "ui_cancel", "label": "Fermer"},
	]))
	_help.get_parent().add_child(help_bar)
