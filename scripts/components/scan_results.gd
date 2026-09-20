extends Control

## Fenêtre modale qui présente les jeux détectés sur la machine avant de les
## ajouter. La détection propose, l'utilisateur dispose : un raccourci trouvé
## n'entre dans la bibliothèque que s'il est coché. C'est ce qui rend le scan
## fiable — aucune application ne s'invite dans la bibliothèque sans accord.

signal confirmed(games: Array[GameEntry])
signal closed()

const HELP_BAR_SCENE: PackedScene = preload("res://scenes/components/help_bar.tscn")

const ENTRY_HEIGHT: float = 78.0
const ENTRY_SEPARATION: int = 8
const MARK_ON: String = "[X]"
const MARK_OFF: String = "[  ]"
## Largeur réservée au libellé d'origine, à droite de chaque ligne.
const ORIGIN_WIDTH: float = 260.0

## Libellé lisible de chaque origine, d'après le préfixe de l'identifiant.
const SOURCE_LABELS: Dictionary = {
	"steam": "Steam",
	"epic": "Epic",
	"lnk": "Raccourci",
	"desktop": "Menu",
}

@onready var _scrim: ColorRect = $Scrim
@onready var _dialog: Panel = $Dialog
@onready var _margin: MarginContainer = $Dialog/Margin
@onready var _title: Label = $Dialog/Margin/Content/Title
@onready var _hint: Label = $Dialog/Margin/Content/Hint
@onready var _gap: Control = $Dialog/Margin/Content/Gap
@onready var _list_pad: MarginContainer = $Dialog/Margin/Content/Scroll/ListPad
@onready var _list: VBoxContainer = $Dialog/Margin/Content/Scroll/ListPad/List
@onready var _gap2: Control = $Dialog/Margin/Content/Gap2
@onready var _actions: VBoxContainer = $Dialog/Margin/Content/Actions
@onready var _help_host: Control = $Dialog/Margin/Content/Help

var is_open: bool = false

var _candidates: Array[GameEntry] = []
## Cases cochées, par identifiant de jeu.
var _selected: Dictionary = {}
var _buttons: Array[Button] = []
var _confirm: Button = null
var _return_focus: Control = null

func _ready() -> void:
	_style()

## Ouvre la liste. Les jeux déjà présents dans la bibliothèque sont montrés
## mais ni cochés ni sélectionnables : rien ne sert de les ajouter deux fois.
func open(candidates: Array[GameEntry]) -> void:
	if is_open:
		return
	is_open = true
	_candidates = candidates
	_selected.clear()
	for game: GameEntry in _candidates:
		if not _already_known(game):
			# Les jeux annoncés par Steam ou Epic sont sûrs : cochés d'office.
			_selected[game.id] = _origin(game) in ["steam", "epic"]
	_return_focus = get_viewport().gui_get_focus_owner()
	visible = true
	_populate()

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	if _return_focus != null and is_instance_valid(_return_focus) and not _return_focus.is_queued_for_deletion():
		_return_focus.grab_focus()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event.is_action_pressed("ui_options"):
		get_viewport().set_input_as_handled()
		_toggle_all()

func _populate() -> void:
	for button: Button in _buttons:
		button.queue_free()
	_buttons.clear()
	if _confirm != null:
		_confirm.queue_free()
		_confirm = null

	_title.text = "Jeux détectés  (%d)" % _candidates.size()
	_hint.text = "Coche ce qui est bien un jeu. Steam et Epic sont déjà cochés."
	if _candidates.is_empty():
		_hint.text = "Aucun jeu trouvé. Steam, Epic et les raccourcis du Bureau ont été consultés."

	for game: GameEntry in _candidates:
		var button: Button = _make_entry(game)
		button.pressed.connect(_on_entry_pressed.bind(game))
		_list.add_child(button)
		_buttons.append(button)

	_confirm = _make_button("")
	_confirm.pressed.connect(_on_confirm)
	_actions.add_child(_confirm)
	_update_confirm()
	_link()
	if not _buttons.is_empty():
		_buttons[0].grab_focus()
	else:
		_confirm.grab_focus()

## Une ligne : la case, le titre, puis l'origine alignée à droite.
func _make_entry(game: GameEntry) -> Button:
	var known: bool = _already_known(game)
	var button: Button = _make_button("%s  %s" % [_mark(game), game.title])
	button.disabled = known
	button.focus_mode = Control.FOCUS_NONE if known else Control.FOCUS_ALL

	var origin := Label.new()
	origin.text = "déjà ajouté" if known else str(SOURCE_LABELS.get(_origin(game), "Raccourci"))
	origin.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	# Ancré à droite, mais avec une largeur : sinon le texte déborde du bouton.
	origin.offset_left = -ORIGIN_WIDTH
	origin.offset_right = -UITheme.SPACING_MEDIUM
	origin.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	origin.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	origin.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	origin.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	origin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(origin)
	return button

func _on_entry_pressed(game: GameEntry) -> void:
	_selected[game.id] = not bool(_selected.get(game.id, false))
	_refresh_marks()

## Options coche ou décoche tout ce qui peut l'être.
func _toggle_all() -> void:
	var target: bool = _selected_games().size() < _selected.size()
	for id: String in _selected.keys():
		_selected[id] = target
	_refresh_marks()

func _refresh_marks() -> void:
	for i: int in _buttons.size():
		var game: GameEntry = _candidates[i]
		if not _already_known(game):
			_buttons[i].text = "%s  %s" % [_mark(game), game.title]
	_update_confirm()

func _update_confirm() -> void:
	var count: int = _selected_games().size()
	_confirm.text = "Ajouter à la bibliothèque  (%d)" % count
	_confirm.disabled = count == 0
	_confirm.focus_mode = Control.FOCUS_NONE if count == 0 else Control.FOCUS_ALL
	_link()

func _on_confirm() -> void:
	var chosen: Array[GameEntry] = _selected_games()
	if chosen.is_empty():
		return
	confirmed.emit(chosen)
	close()

func _selected_games() -> Array[GameEntry]:
	var chosen: Array[GameEntry] = []
	for game: GameEntry in _candidates:
		if bool(_selected.get(game.id, false)):
			chosen.append(game)
	return chosen

func _mark(game: GameEntry) -> String:
	return MARK_ON if bool(_selected.get(game.id, false)) else MARK_OFF

func _already_known(game: GameEntry) -> bool:
	return GameLibrary.get_game(game.id) != null

## Origine d'un jeu, lue sur son identifiant (« steam-620 », « lnk-123… »).
func _origin(game: GameEntry) -> String:
	var parts: PackedStringArray = game.id.split("-", false, 1)
	return parts[0] if parts.size() > 0 else ""

## Le focus reste dans la fenêtre : les lignes, puis le bouton d'ajout.
func _link() -> void:
	var column: Array[Button] = []
	for button: Button in _buttons:
		if button.focus_mode != Control.FOCUS_NONE:
			column.append(button)
	if _confirm != null and _confirm.focus_mode != Control.FOCUS_NONE:
		column.append(_confirm)
	for i: int in column.size():
		var button: Button = column[i]
		button.focus_neighbor_top = button.get_path_to(column[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(column[mini(i + 1, column.size() - 1)])
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = ENTRY_HEIGHT
	button.focus_mode = Control.FOCUS_ALL
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	button.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", UITheme.COLOR_TEXT_DIM)
	var normal: StyleBoxFlat = UITheme.surface_box()
	var focused: StyleBoxFlat = UITheme.focus_box()
	var disabled: StyleBoxFlat = UITheme.surface_box()
	for box: StyleBoxFlat in [normal, focused, disabled]:
		box.content_margin_left = UITheme.SPACING_MEDIUM
		box.content_margin_right = UITheme.SPACING_MEDIUM
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("pressed", focused)
	button.add_theme_stylebox_override("focus", focused)
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
	_list.add_theme_constant_override("separation", ENTRY_SEPARATION)
	# La zone de défilement rogne ce qui dépasse : on réserve la place du halo.
	for side: String in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		_list_pad.add_theme_constant_override(side, UITheme.FOCUS_GLOW_SIZE)

	_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_hint.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_hint.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)

	var help_bar: HBoxContainer = HELP_BAR_SCENE.instantiate()
	help_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	help_bar.set_actions(ControllerGlyphs.actions([
		{"action": "ui_accept", "label": "Cocher"},
		{"action": "ui_options", "label": "Tout cocher"},
		{"action": "ui_cancel", "label": "Fermer"},
	]))
	_help_host.custom_minimum_size.y = UITheme.SETTINGS_ROW_HEIGHT * 0.5
	_help_host.add_child(help_bar)
	help_bar.set_anchors_preset(Control.PRESET_CENTER)
