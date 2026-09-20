extends Control

## Fenêtre modale de choix de la vidéo d'introduction. Les vidéos sont fournies
## par la console (`MediaCatalog`) : pas de navigateur de fichiers.
## Parcourir la liste lance l'aperçu, valider retient la vidéo.

signal video_chosen(path: String)
signal closed()

const ENTRY_HEIGHT: float = 84.0
const ENTRY_SEPARATION: int = 10
const HELP_BAR_SCENE: PackedScene = preload("res://scenes/components/help_bar.tscn")

@onready var _scrim: ColorRect = $Scrim
@onready var _dialog: Panel = $Dialog
@onready var _margin: MarginContainer = $Dialog/Margin
@onready var _title: Label = $Dialog/Margin/Content/Title
@onready var _gap: Control = $Dialog/Margin/Content/Gap
@onready var _columns: HBoxContainer = $Dialog/Margin/Content/Columns
@onready var _entries_pad: MarginContainer = $Dialog/Margin/Content/Columns/Scroll/EntriesPad
@onready var _entries: VBoxContainer = $Dialog/Margin/Content/Columns/Scroll/EntriesPad/Entries
@onready var _preview: Panel = $Dialog/Margin/Content/Columns/Preview
@onready var _gap2: Control = $Dialog/Margin/Content/Gap2
@onready var _help: Label = $Dialog/Margin/Content/Help

var is_open: bool = false

var _buttons: Array[Button] = []
var _paths: PackedStringArray = PackedStringArray()
var _player: VideoStreamPlayer = null
var _empty: Label = null
var _return_focus: Control = null

func _ready() -> void:
	_style()

## Ouvre la liste en plaçant le focus sur la vidéo actuelle.
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
	_player.stop()
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

	# Première entrée : démarrer sans vidéo.
	_paths = PackedStringArray([""])
	_paths.append_array(MediaCatalog.boot_videos())
	for path: String in _paths:
		var button: Button = _make_entry("Aucune vidéo" if path.is_empty() else MediaCatalog.pretty_name(path))
		button.pressed.connect(_on_chosen.bind(path))
		button.focus_entered.connect(_show_preview.bind(path))
		_entries.add_child(button)
		_buttons.append(button)
	_link()

func _link() -> void:
	for i: int in _buttons.size():
		var button: Button = _buttons[i]
		button.focus_neighbor_top = button.get_path_to(_buttons[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(_buttons[mini(i + 1, _buttons.size() - 1)])
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom

## Joue la vidéo survolée : on voit ce qu'on choisit avant de valider.
func _show_preview(path: String) -> void:
	var stream: VideoStream = MediaCatalog.video_stream(path)
	_player.stream = stream
	_player.visible = stream != null
	_empty.visible = stream == null
	if stream != null:
		_player.play()

func _on_chosen(path: String) -> void:
	video_chosen.emit(path)
	close()

func _make_entry(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = ENTRY_HEIGHT
	button.focus_mode = Control.FOCUS_ALL
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	button.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	var normal: StyleBoxFlat = UITheme.surface_box()
	var focused: StyleBoxFlat = UITheme.focus_box()
	for box: StyleBoxFlat in [normal, focused]:
		box.content_margin_left = UITheme.SPACING_MEDIUM
		box.content_margin_right = UITheme.SPACING_MEDIUM
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", normal)
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
	_columns.add_theme_constant_override("separation", int(UITheme.SPACING_LARGE))
	_entries.add_theme_constant_override("separation", ENTRY_SEPARATION)
	# La zone de défilement rogne ce qui dépasse : on réserve la place du halo.
	for side: String in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		_entries_pad.add_theme_constant_override(side, UITheme.FOCUS_GLOW_SIZE)

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

	_preview.custom_minimum_size = UITheme.BOOT_PICKER_PREVIEW_SIZE
	_preview.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_preview.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var frame := StyleBoxFlat.new()
	frame.bg_color = UITheme.COLOR_BACKGROUND
	frame.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS)
	_preview.add_theme_stylebox_override("panel", frame)

	_player = VideoStreamPlayer.new()
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.expand = true
	_player.loop = true
	_player.volume_db = -80.0
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.add_child(_player)

	_empty = Label.new()
	_empty.text = "Aucune vidéo"
	_empty.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_empty.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.add_child(_empty)
