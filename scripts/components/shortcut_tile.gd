extends Button

## Grande tuile de raccourci de la rangée basse de l'accueil.

signal activated(action: String)

@onready var _pivot: Control = $Pivot
@onready var _glow: Panel = $Pivot/Glow
@onready var _surface: Panel = $Pivot/Surface
@onready var _border: Panel = $Pivot/Border
@onready var _label: Label = $Pivot/Label

## Identifiant de l'action déclenchée, renseigné avant l'ajout à l'arbre.
var action: String = ""
var tint: Color = UITheme.COLOR_SURFACE
var label_text: String = ""

var _icon: TextureRect = null
var _subtitle: Label = null
var _tween: Tween = null

const SHORTCUT_META: Dictionary = {
	"library": {"icon": "res://assets/icons/library.svg", "sub": "Tous vos titres"},
	"favorites": {"icon": "res://assets/icons/star.svg", "sub": "Accès rapide"},
	"recent": {"icon": "res://assets/icons/clock.svg", "sub": "Dernières sessions"},
	"settings": {"icon": "res://assets/icons/settings.svg", "sub": "Console & Réseau"},
}

func _ready() -> void:
	custom_minimum_size = UITheme.SHORTCUT_SIZE
	clip_contents = false
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_pivot.pivot_offset = UITheme.SHORTCUT_SIZE * Vector2(0.5, 1.0)

	_build_extra_elements()
	_style()
	_border.modulate.a = 0.0
	_glow.modulate.a = 0.0

	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	pressed.connect(func() -> void: activated.emit(action))

func setup(text: String, action_name: String, color: Color) -> void:
	label_text = text
	action = action_name
	tint = color
	if is_node_ready():
		_style()

func _build_extra_elements() -> void:
	if _icon == null:
		_icon = TextureRect.new()
		_icon.name = "ShortcutIcon"
		_icon.offset_left = 26.0
		_icon.offset_top = 24.0
		_icon.offset_right = 58.0
		_icon.offset_bottom = 56.0
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pivot.add_child(_icon)

	if _subtitle == null:
		_subtitle = Label.new()
		_subtitle.name = "Subtitle"
		_subtitle.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_subtitle.offset_left = 26.0
		_subtitle.offset_top = -34.0
		_subtitle.offset_right = -26.0
		_subtitle.offset_bottom = -14.0
		_subtitle.add_theme_font_size_override("font_size", 18)
		_subtitle.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		_subtitle.remove_theme_color_override("font_shadow_color")
		_subtitle.remove_theme_constant_override("shadow_offset_y")
		_subtitle.remove_theme_constant_override("shadow_offset_x")
		_subtitle.remove_theme_constant_override("shadow_outline_size")
		_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pivot.add_child(_subtitle)

func _style() -> void:
	_label.text = label_text
	_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_left = 26.0
	_label.offset_top = -70.0
	_label.offset_right = -26.0
	_label.offset_bottom = -36.0

	var meta: Dictionary = SHORTCUT_META.get(action, {})
	var icon_path: String = meta.get("icon", "")
	if not icon_path.is_empty() and _icon != null:
		_icon.texture = load(icon_path)
		_icon.visible = true
	elif _icon != null:
		_icon.visible = false

	if _subtitle != null:
		_subtitle.text = meta.get("sub", "")

	# Carte moderne en verre sombre unifié
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color(0.08, 0.10, 0.15, 0.85)
	surface.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS)
	_surface.add_theme_stylebox_override("panel", surface)

	var border := StyleBoxFlat.new()
	border.bg_color = Color.TRANSPARENT
	border.set_border_width_all(UITheme.TILE_BORDER_WIDTH)
	border.border_color = UITheme.COLOR_ACCENT
	border.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS)
	_border.add_theme_stylebox_override("panel", border)

	var glow := StyleBoxFlat.new()
	glow.bg_color = UITheme.COLOR_ACCENT
	glow.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS)
	glow.shadow_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.45)
	glow.shadow_size = UITheme.FOCUS_GLOW_SIZE
	_glow.add_theme_stylebox_override("panel", glow)

	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color.WHITE)
	_label.remove_theme_color_override("font_shadow_color")
	_label.remove_theme_constant_override("shadow_offset_y")
	_label.remove_theme_constant_override("shadow_offset_x")
	_label.remove_theme_constant_override("shadow_outline_size")

	if _icon != null:
		_icon.modulate = UITheme.COLOR_ACCENT if action == "favorites" else Color(0.85, 0.88, 0.95)

func _on_focus_changed(focused: bool) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	var opacity: float = 1.0 if focused else 0.0
	_tween = create_tween().set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	_tween.tween_property(_pivot, "scale", Vector2.ONE * (1.04 if focused else 1.0), UITheme.ANIM_SELECT)
	_tween.tween_property(_border, "modulate:a", opacity, UITheme.ANIM_SELECT)
	_tween.tween_property(_glow, "modulate:a", opacity, UITheme.ANIM_SELECT)
	if _icon != null:
		var target_icon_modulate: Color = Color.WHITE if focused else (UITheme.COLOR_ACCENT if action == "favorites" else Color(0.85, 0.88, 0.95))
		_tween.tween_property(_icon, "modulate", target_icon_modulate, UITheme.ANIM_SELECT)
	z_index = UITheme.Z_TILE_FOCUSED if focused else 0
