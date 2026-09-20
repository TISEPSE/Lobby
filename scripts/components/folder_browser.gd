extends Control

## Navigateur de dossiers à la manette : A entre dans un dossier, B remonte
## (et ferme à la racine), X retient le dossier courant.

signal folder_chosen(path: String)
signal file_chosen(path: String)
signal cancelled()

const ENTRY_HEIGHT: float = 62.0
const ENTRY_SEPARATION: int = 6
## Racine virtuelle : la liste des lecteurs sous Windows, « / » ailleurs.
const ROOT: String = ""

@onready var _scrim: ColorRect = $Scrim
@onready var _dialog: Panel = $Dialog
@onready var _margin: MarginContainer = $Dialog/Margin
@onready var _title: Label = $Dialog/Margin/Content/Title
@onready var _current_path: Label = $Dialog/Margin/Content/CurrentPath
@onready var _gap: Control = $Dialog/Margin/Content/Gap
@onready var _entries: VBoxContainer = $Dialog/Margin/Content/Scroll/Entries
@onready var _empty: Label = $Dialog/Margin/Content/Empty
@onready var _help_bar: HBoxContainer = $Dialog/Margin/Content/HelpBar

var is_open: bool = false

## Extensions de fichiers à proposer. Vide : on ne montre que les dossiers.
var file_filter: PackedStringArray = PackedStringArray()
var _path: String = ROOT
var _buttons: Array[Button] = []
var _return_focus: Control = null

func _ready() -> void:
	_style()

## Ouvre le navigateur, en repartant du dossier donné s'il existe encore.
## `extensions` vide : on choisit un dossier. Sinon, les fichiers correspondants
## sont listés et les valider termine la sélection.
func open(start_path: String = ROOT, extensions: PackedStringArray = PackedStringArray(), title: String = "") -> void:
	if is_open:
		return
	is_open = true
	file_filter = extensions
	_title.text = title if not title.is_empty() else ("Choisir un fichier" if not extensions.is_empty() else "Choisir un dossier de jeux")
	_return_focus = get_viewport().gui_get_focus_owner()
	visible = true
	_path = start_path if _exists(start_path) else ROOT
	_populate()

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
		_go_up()
	elif event.is_action_pressed("ui_options"):
		get_viewport().set_input_as_handled()
		_choose_current()

## B remonte d'un cran ; à la racine, il ferme le navigateur.
func _go_up() -> void:
	if _path == ROOT:
		cancelled.emit()
		close()
		return
	var parent: String = _path.get_base_dir()
	# Un chemin de lecteur (« D:/ ») a pour parent lui-même : on revient à la racine.
	_path = ROOT if parent == _path or parent.is_empty() else parent
	_populate()

func _choose_current() -> void:
	if _path == ROOT:
		return
	folder_chosen.emit(_path)
	close()

func _populate() -> void:
	for button: Button in _buttons:
		button.queue_free()
	_buttons.clear()

	_current_path.text = "Lecteurs" if _path == ROOT else _path
	var names: PackedStringArray = _drives() if _path == ROOT else _subfolders(_path)
	if not file_filter.is_empty() and _path != ROOT:
		names.append_array(_files(_path))
	for name: String in names:
		var button: Button = _make_entry(name)
		_entries.add_child(button)
		_buttons.append(button)

	_empty.visible = _buttons.is_empty()
	_empty.text = "Aucun sous-dossier ici." if _path != ROOT else "Aucun lecteur accessible."
	if _path == ROOT:
		_help_bar.set_actions(ControllerGlyphs.actions([
			{"action": "ui_accept", "label": "Ouvrir"},
			{"action": "ui_cancel", "label": "Fermer"},
		]))
	elif not file_filter.is_empty():
		_help_bar.set_actions(ControllerGlyphs.actions([
			{"action": "ui_accept", "label": "Choisir"},
			{"action": "ui_cancel", "label": "Remonter"},
		]))
	else:
		_help_bar.set_actions(ControllerGlyphs.actions([
			{"action": "ui_accept", "label": "Ouvrir"},
			{"action": "ui_options", "label": "Choisir ce dossier"},
			{"action": "ui_cancel", "label": "Remonter"},
		]))
	_link()
	if not _buttons.is_empty():
		_buttons[0].grab_focus()

func _make_entry(name: String) -> Button:
	var button := Button.new()
	button.text = name
	button.custom_minimum_size.y = ENTRY_HEIGHT
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.clip_text = true
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	button.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _entry_box(false))
	button.add_theme_stylebox_override("hover", _entry_box(false))
	button.add_theme_stylebox_override("pressed", _entry_box(true))
	button.add_theme_stylebox_override("focus", _entry_box(true))
	button.pressed.connect(_on_entry_pressed.bind(name))
	return button

func _on_entry_pressed(name: String) -> void:
	var target: String = name if _path == ROOT else _path.path_join(name)
	# En mode fichier, valider un fichier termine la sélection.
	if not file_filter.is_empty() and FileAccess.file_exists(target):
		file_chosen.emit(target)
		close()
		return
	_path = target
	_populate()

## Fichiers du dossier courant correspondant au filtre.
func _files(path: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.get_extension().to_lower() in file_filter:
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names

func _link() -> void:
	for i: int in _buttons.size():
		var button: Button = _buttons[i]
		button.focus_neighbor_top = button.get_path_to(_buttons[maxi(i - 1, 0)])
		button.focus_neighbor_bottom = button.get_path_to(_buttons[mini(i + 1, _buttons.size() - 1)])
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom

## Lecteurs montés : Godot n'expose pas la liste, on teste les lettres une à une.
func _drives() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if OS.get_name() != "Windows":
		found.append("/")
		return found
	for code: int in range(65, 91):
		var drive: String = "%s:/" % char(code)
		if DirAccess.dir_exists_absolute(drive):
			found.append(drive)
	return found

func _subfolders(path: String) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return names
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names

func _exists(path: String) -> bool:
	return not path.is_empty() and DirAccess.dir_exists_absolute(path)

func _entry_box(focused: bool) -> StyleBoxFlat:
	var box: StyleBoxFlat = UITheme.focus_box() if focused else UITheme.surface_box()
	box.content_margin_left = UITheme.SPACING_MEDIUM
	box.content_margin_right = UITheme.SPACING_MEDIUM
	return box

func _style() -> void:
	_scrim.color = Color(UITheme.COLOR_BACKGROUND, UITheme.SIDEBAR_SCRIM_ALPHA)

	var box := StyleBoxFlat.new()
	box.bg_color = UITheme.COLOR_SIDEBAR
	box.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS * 2)
	_dialog.add_theme_stylebox_override("panel", box)

	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_margin.add_theme_constant_override(side, int(UITheme.SPACING_LARGE))
	_gap.custom_minimum_size.y = UITheme.SPACING_MEDIUM
	_entries.add_theme_constant_override("separation", ENTRY_SEPARATION)

	_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	for label: Label in [_current_path, _empty]:
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
		label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
