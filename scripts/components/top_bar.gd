extends Control

## Barre supérieure : profil à gauche, icônes de sections au centre, état de la
## console et heure à droite. Tout ce qui y est affiché vient de données réelles.

signal icon_activated(action: String)

const CLOCK_INTERVAL: float = 10.0
const GROUP_SEPARATION: int = 18
const ICON_SEPARATION: int = 10
const ROW_SEPARATION: int = 10
const STAT_ICON_SIZE: Vector2 = Vector2(24, 24)
const PAD_ICON_SIZE: Vector2 = Vector2(24, 24)
const CONTROLLER_ICON: String = "res://assets/icons/controller.svg"
const CLOCK_ICON: String = "res://assets/icons/clock.svg"

## Sections de la barre : icône et action émise à la validation.
const ICONS: Array[Dictionary] = [
	{"path": "res://assets/icons/library.svg", "action": "library"},
	{"path": "res://assets/icons/store.svg", "action": "store"},
	{"path": "res://assets/icons/search.svg", "action": "search"},
	{"path": "res://assets/icons/settings.svg", "action": "settings"},
]

@onready var _left: HBoxContainer = $Left
@onready var _identity: VBoxContainer = $Left/Identity
@onready var _name_row: HBoxContainer = $Left/Identity/NameRow
@onready var _stat_row: HBoxContainer = $Left/Identity/StatRow
@onready var _center: HBoxContainer = $Center
@onready var _right: HBoxContainer = $Right
@onready var _pads: HBoxContainer = $Right/Pads
@onready var _avatar: Panel = $Left/Avatar
@onready var _avatar_image: TextureRect = $Left/Avatar/AvatarImage
@onready var _initial: Label = $Left/Avatar/Initial
@onready var _profile: Label = $Left/Identity/NameRow/Profile
@onready var _badge: PanelContainer = $Left/Identity/NameRow/Badge
@onready var _badge_label: Label = $Left/Identity/NameRow/Badge/BadgeLabel
@onready var _stat_icon: TextureRect = $Left/Identity/StatRow/StatIcon
@onready var _stat: Label = $Left/Identity/StatRow/Stat
@onready var _pad_icon: TextureRect = $Right/Pads/PadIcon
@onready var _pad_count: Label = $Right/Pads/PadCount
@onready var _clock: Label = $Right/Clock

## Miroir local du pseudo : la source de vérité est `Settings.profile_name`.
var profile_name: String = "Joueur"

var _buttons: Array[Button] = []

func _ready() -> void:
	_left.add_theme_constant_override("separation", GROUP_SEPARATION)
	_right.add_theme_constant_override("separation", GROUP_SEPARATION)
	_center.add_theme_constant_override("separation", ICON_SEPARATION)
	_identity.add_theme_constant_override("separation", 2)
	_name_row.add_theme_constant_override("separation", ROW_SEPARATION)
	_stat_row.add_theme_constant_override("separation", ROW_SEPARATION)
	_pads.add_theme_constant_override("separation", ROW_SEPARATION)

	_style()
	_build_icons()
	profile_name = Settings.profile_name
	Settings.changed.connect(func() -> void:
		profile_name = Settings.profile_name
		_refresh_profile()
	)
	_refresh_profile()
	_refresh_clock()
	_refresh_pads()
	_refresh_library_stats()

	GameLibrary.library_loaded.connect(func(_games: Array) -> void: _refresh_library_stats())
	GameLibrary.game_updated.connect(func(_game: GameEntry) -> void: _refresh_library_stats())
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: _refresh_pads())

	var timer := Timer.new()
	timer.wait_time = CLOCK_INTERVAL
	timer.timeout.connect(_refresh_clock)
	add_child(timer)
	timer.start()

func set_profile_name(value: String) -> void:
	profile_name = value
	if is_node_ready():
		_refresh_profile()

## Boutons des sections, dans l'ordre d'affichage.
func icon_buttons() -> Array[Button]:
	return _buttons

func _build_icons() -> void:
	for entry: Dictionary in ICONS:
		var button: Button = _make_icon_button(str(entry["path"]), str(entry["action"]))
		_center.add_child(button)
		_buttons.append(button)
	_link_icons()

## Chaque icône est posée dans une pastille ronde opaque, pour la détacher de
## l'artwork quelle que soit l'image de fond.
func _make_icon_button(path: String, action: String) -> Button:
	var size: float = UITheme.ICON_BADGE_SIZE
	var button := Button.new()
	button.custom_minimum_size = Vector2(size, size)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.focus_mode = Control.FOCUS_ALL
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, _badge_box(false))
	button.add_theme_stylebox_override("focus", _badge_box(true))

	# Ancré sur tout le rectangle avec une marge : le glyphe reste centré quelle
	# que soit la taille de la pastille.
	var padding: float = (size - UITheme.ICON_GLYPH_SIZE) * 0.5
	var icon := TextureRect.new()
	icon.texture = load(path)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = padding
	icon.offset_top = padding
	icon.offset_right = -padding
	icon.offset_bottom = -padding
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = UITheme.COLOR_TEXT
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)

	button.pressed.connect(func() -> void: icon_activated.emit(action))
	return button

## Navigation horizontale entre icônes ; le voisin du bas est fixé par l'écran.
func _link_icons() -> void:
	for i: int in _buttons.size():
		var button: Button = _buttons[i]
		var left: int = maxi(i - 1, 0)
		var right: int = mini(i + 1, _buttons.size() - 1)
		button.focus_neighbor_left = button.get_path_to(_buttons[left])
		button.focus_neighbor_right = button.get_path_to(_buttons[right])
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right

## Photo de profil si elle est définie, initiale du pseudo sinon.
func _apply_avatar() -> void:
	var texture: Texture2D = ImageLoader.load_texture(Settings.avatar_path) if not Settings.avatar_path.is_empty() else null
	if texture == null:
		_avatar_image.visible = false
		_initial.visible = true
		return
	_avatar_image.texture = texture
	_avatar_image.visible = true
	_initial.visible = false

func _refresh_profile() -> void:
	_profile.text = profile_name
	_initial.text = profile_name.substr(0, 1).to_upper()
	_apply_avatar()

func _refresh_clock() -> void:
	var now: Dictionary = Time.get_time_dict_from_system()
	_clock.text = "%02d:%02d" % [now["hour"], now["minute"]]

## Nombre de manettes réellement connectées : l'icône s'éteint s'il n'y en a pas.
func _refresh_pads() -> void:
	var count: int = Input.get_connected_joypads().size()
	_pads.visible = count > 0
	_pad_count.text = str(count)
	_pad_icon.modulate = UITheme.COLOR_TEXT_DIM
	_pad_count.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)

## Badge et statistique dérivés de la bibliothèque : nombre de jeux et temps de
## jeu cumulé. Rien d'inventé, tout vient de `GameLibrary`.
func _refresh_library_stats() -> void:
	_badge.visible = false
	_stat_row.visible = false

func _style() -> void:
	var avatar_box := StyleBoxFlat.new()
	avatar_box.bg_color = UITheme.COLOR_ACCENT
	avatar_box.set_corner_radius_all(23)
	_avatar.custom_minimum_size = Vector2(46, 46)
	_avatar.add_theme_stylebox_override("panel", avatar_box)

	_badge.visible = false
	_stat_row.visible = false

	_initial.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_initial.add_theme_color_override("font_color", Color.WHITE)

	_profile.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_profile.add_theme_color_override("font_color", Color.WHITE)
	_clock.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_clock.add_theme_color_override("font_color", Color.WHITE)

	_pad_count.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_pad_count.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	for label: Label in [_profile, _clock, _stat, _pad_count, _badge_label, _initial]:
		label.remove_theme_constant_override("shadow_offset_x")

	_pad_icon.texture = load(CONTROLLER_ICON)
	_pad_icon.custom_minimum_size = PAD_ICON_SIZE

## Pastille des icônes : fond opaque au repos, contour d'accent au focus, comme
## les jaquettes. Le même langage de sélection partout.
func _badge_box(focused: bool) -> StyleBoxFlat:
	var radius: int = int(UITheme.ICON_BADGE_SIZE * 0.5)
	var box: StyleBoxFlat = UITheme.focus_box(radius) if focused else UITheme.surface_box(radius)
	box.bg_color = UITheme.COLOR_ICON_BADGE
	return box
