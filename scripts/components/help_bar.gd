extends HBoxContainer

## Barre d'aide : bouton manette officiel (Xbox / PS5) puis libellé de l'action.
## Les symboles s'adaptent dynamiquement au réglage ou à la manette connectée.

const ENTRY_SEPARATION: int = 36
const LABEL_SEPARATION: int = 12

var _entries: Array[Dictionary] = []

func _ready() -> void:
	add_theme_constant_override("separation", ENTRY_SEPARATION)
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: _rebuild())
	Settings.changed.connect(_rebuild)
	if get_child_count() == 0:
		set_actions(default_actions())

## Actions par défaut, celles de l'écran d'accueil.
static func default_actions() -> Array[Dictionary]:
	return ControllerGlyphs.actions([
		{"action": "ui_accept", "label": "Jouer"},
		{"action": "ui_cancel", "label": "Retour"},
		{"action": "ui_options", "label": "Options"},
		{"action": "ui_search", "label": "Recherche"},
	])

func set_actions(actions: Array[Dictionary]) -> void:
	_entries = actions
	_rebuild()

func _rebuild() -> void:
	for child: Node in get_children():
		child.queue_free()
	for item: Dictionary in _entries:
		var action_name: String = str(item.get("action", ""))
		var data: Dictionary = item
		if not action_name.is_empty():
			var g: Dictionary = ControllerGlyphs.glyph(action_name)
			data = {
				"action": action_name,
				"button": g.get("label", ""),
				"icon": g.get("icon", ""),
				"color": g.get("color", Color.WHITE),
				"has_bg": g.get("has_bg", false),
				"modulate_icon": g.get("modulate_icon", false),
				"label": item.get("label", ""),
			}
		add_child(_make_entry(data))

func _make_entry(action: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", LABEL_SEPARATION)

	var glyph_container := Control.new()
	glyph_container.custom_minimum_size = Vector2(UITheme.BADGE_SIZE, UITheme.BADGE_SIZE)
	glyph_container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph_container.add_child(_make_glyph(action))

	var label := Label.new()
	label.text = str(action["label"])
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	label.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)

	row.add_child(glyph_container)
	row.add_child(label)
	return row

func _make_glyph(action: Dictionary) -> Control:
	var icon_path: String = str(action.get("icon", ""))
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if action.get("modulate_icon", false):
			icon.modulate = action.get("color", Color.WHITE)
		return icon

	var letter := Label.new()
	letter.text = str(action.get("button", "A"))
	letter.set_anchors_preset(Control.PRESET_FULL_RECT)
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	letter.add_theme_color_override("font_color", Color.WHITE)
	letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return letter
