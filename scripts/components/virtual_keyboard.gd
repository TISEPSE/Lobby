extends Control

## Clavier à l'écran, utilisable uniquement à la manette.
## Disposition AZERTY, puisque l'interface est en français.

signal validated(text: String)
signal cancelled()

const KEY_SIZE: Vector2 = Vector2(88, 72)
const KEY_SEPARATION: int = 8
const ACTION_SIZE: Vector2 = Vector2(210, 72)
const MAX_LENGTH: int = 24

## Quatre rangées de dix touches : lettres puis chiffres.
const ROWS: Array[String] = [
	"AZERTYUIOP",
	"QSDFGHJKLM",
	"WXCVBN-_'.",
	"0123456789",
]

@onready var _scrim: ColorRect = $Scrim
@onready var _dialog: Panel = $Dialog
@onready var _margin: MarginContainer = $Dialog/Margin
@onready var _title: Label = $Dialog/Margin/Content/Title
@onready var _field: Panel = $Dialog/Margin/Content/Field
@onready var _text: Label = $Dialog/Margin/Content/Field/Text
@onready var _gap: Control = $Dialog/Margin/Content/Gap
@onready var _keys: GridContainer = $Dialog/Margin/Content/Keys
@onready var _gap_actions: Control = $Dialog/Margin/Content/GapActions
@onready var _actions: HBoxContainer = $Dialog/Margin/Content/Actions
@onready var _help: Label = $Dialog/Margin/Content/Help

var is_open: bool = false

var _value: String = ""
var _uppercase: bool = true
var _key_buttons: Array[Button] = []
var _action_buttons: Array[Button] = []
var _shift_button: Button = null
var _return_focus: Control = null

func _ready() -> void:
	_style()
	_build_keys()
	_build_actions()

## Ouvre le clavier sur une valeur existante.
func open(title: String, initial: String) -> void:
	if is_open:
		return
	is_open = true
	_return_focus = get_viewport().gui_get_focus_owner()
	_title.text = title
	_value = initial
	_refresh_text()
	visible = true
	if not _key_buttons.is_empty():
		_key_buttons[0].grab_focus()

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	# Le réglage qu'on vient de changer a pu reconstruire la ligne d'origine :
	# on ne rend pas le focus à un bouton en cours de suppression.
	if _return_focus != null and is_instance_valid(_return_focus) and not _return_focus.is_queued_for_deletion():
		_return_focus.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
		close()
	elif event.is_action_pressed("ui_options"):
		# Options efface le dernier caractère : un raccourci utile quand on se
		# trompe, sans avoir à traverser le clavier jusqu'à « Effacer ».
		get_viewport().set_input_as_handled()
		_erase()

func _build_keys() -> void:
	_keys.columns = ROWS[0].length()
	_keys.add_theme_constant_override("h_separation", KEY_SEPARATION)
	_keys.add_theme_constant_override("v_separation", KEY_SEPARATION)
	for row: String in ROWS:
		for character: String in row:
			var button: Button = _make_button(character, KEY_SIZE)
			button.pressed.connect(_on_key_pressed.bind(character))
			_keys.add_child(button)
			_key_buttons.append(button)

func _build_actions() -> void:
	_actions.add_theme_constant_override("separation", KEY_SEPARATION)
	_shift_button = _make_button("Majuscules", ACTION_SIZE)
	_shift_button.pressed.connect(_toggle_case)
	var space: Button = _make_button("Espace", ACTION_SIZE)
	space.pressed.connect(_on_key_pressed.bind(" "))
	var erase: Button = _make_button("Effacer", ACTION_SIZE)
	erase.pressed.connect(_erase)
	var done: Button = _make_button("Valider", ACTION_SIZE)
	done.pressed.connect(_validate)

	for button: Button in [_shift_button, space, erase, done]:
		_actions.add_child(button)
		_action_buttons.append(button)
	_link()

## Voisinage explicite : la grille de touches, puis la rangée d'actions.
func _link() -> void:
	var columns: int = _keys.columns
	var count: int = _key_buttons.size()
	for i: int in count:
		var button: Button = _key_buttons[i]
		var column: int = i % columns
		var row: int = i / columns
		button.focus_neighbor_left = button.get_path_to(_key_buttons[i - 1 if column > 0 else i])
		button.focus_neighbor_right = button.get_path_to(_key_buttons[i + 1 if column < columns - 1 and i + 1 < count else i])
		button.focus_neighbor_top = button.get_path_to(_key_buttons[i - columns] if row > 0 else button)
		if i + columns < count:
			button.focus_neighbor_bottom = button.get_path_to(_key_buttons[i + columns])
		else:
			# Dernière rangée : on descend vers l'action la plus proche.
			var target: int = mini(column * _action_buttons.size() / columns, _action_buttons.size() - 1)
			button.focus_neighbor_bottom = button.get_path_to(_action_buttons[target])
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right

	for i: int in _action_buttons.size():
		var button: Button = _action_buttons[i]
		button.focus_neighbor_left = button.get_path_to(_action_buttons[maxi(i - 1, 0)])
		button.focus_neighbor_right = button.get_path_to(_action_buttons[mini(i + 1, _action_buttons.size() - 1)])
		button.focus_neighbor_bottom = button.get_path_to(button)
		var above: int = mini(count - columns + i * columns / maxi(_action_buttons.size(), 1), count - 1)
		button.focus_neighbor_top = button.get_path_to(_key_buttons[maxi(above, 0)])
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right

func _on_key_pressed(character: String) -> void:
	if _value.length() >= MAX_LENGTH:
		return
	_value += character if _uppercase or character == " " else character.to_lower()
	_refresh_text()

func _toggle_case() -> void:
	_uppercase = not _uppercase
	_shift_button.text = "Majuscules" if _uppercase else "Minuscules"
	for i: int in _key_buttons.size():
		var character: String = _character_at(i)
		_key_buttons[i].text = character if _uppercase else character.to_lower()

func _character_at(index: int) -> String:
	var flat: String = ""
	for row: String in ROWS:
		flat += row
	return flat.substr(index, 1)

func _erase() -> void:
	if _value.is_empty():
		return
	_value = _value.substr(0, _value.length() - 1)
	_refresh_text()

func _validate() -> void:
	validated.emit(_value.strip_edges())
	close()

func _refresh_text() -> void:
	_text.text = _value if not _value.is_empty() else "…"
	_text.add_theme_color_override("font_color", UITheme.COLOR_TEXT if not _value.is_empty() else UITheme.COLOR_TEXT_DIM)

func _make_button(text: String, size: Vector2) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	button.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	button.add_theme_stylebox_override("normal", UITheme.surface_box())
	button.add_theme_stylebox_override("hover", UITheme.surface_box())
	button.add_theme_stylebox_override("pressed", UITheme.focus_box())
	button.add_theme_stylebox_override("focus", UITheme.focus_box())
	return button

func _style() -> void:
	_scrim.color = Color(UITheme.COLOR_BACKGROUND, UITheme.SIDEBAR_SCRIM_ALPHA)

	var dialog_box := StyleBoxFlat.new()
	dialog_box.bg_color = UITheme.COLOR_SIDEBAR
	dialog_box.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS * 2)
	_dialog.add_theme_stylebox_override("panel", dialog_box)

	var field_box: StyleBoxFlat = UITheme.surface_box()
	field_box.content_margin_left = UITheme.SPACING_MEDIUM
	field_box.content_margin_right = UITheme.SPACING_MEDIUM
	_field.add_theme_stylebox_override("panel", field_box)

	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_margin.add_theme_constant_override(side, int(UITheme.SPACING_LARGE))
	_gap.custom_minimum_size.y = UITheme.SPACING_MEDIUM
	_gap_actions.custom_minimum_size.y = UITheme.SPACING_MEDIUM

	_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_text.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_help.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_help.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_help.text = "Options : effacer      B : annuler"
