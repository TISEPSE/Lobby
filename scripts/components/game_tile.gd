extends Button

## Tuile de jeu : jaquette carrée générée en dégradé, titre lisible,
## focus visible (agrandissement + bordure d'accent).

signal activated(game: GameEntry)

@onready var _pivot: Control = $Pivot
@onready var _glow: Panel = $Pivot/Glow
@onready var _mask: Panel = $Pivot/Mask
@onready var _cover: TextureRect = $Pivot/Mask/Cover
@onready var _shade: TextureRect = $Pivot/Mask/Shade
@onready var _border: Panel = $Pivot/Border
@onready var _title: Label = $Pivot/Title
@onready var _favorite: Panel = $Pivot/Favorite
@onready var _star: Control = $Pivot/Favorite/Star

var game: GameEntry = null

## Réglages à fixer avant l'ajout à l'arbre : la grille et le carrousel
## utilisent la même tuile avec des dimensions et un ancrage différents.
var tile_size: Vector2 = UITheme.TILE_SIZE
var focus_scale: float = UITheme.TILE_FOCUS_SCALE
## Vrai pour le carrousel : la tuile grandit vers le haut, la rangée reste alignée en bas.
var grow_upwards: bool = false
## Vrai pour le carrousel : la tuile occupe réellement plus de place quand elle est
## sélectionnée, ce qui écarte ses voisines au lieu de passer par-dessus elles.
var resize_on_focus: bool = false
## Vrai pour le carrousel : le titre n'apparaît que sur la tuile sélectionnée.
var title_on_focus: bool = false
## Taille du titre AVANT agrandissement : sur une petite tuite très agrandie,
## une police plus petite reste au-dessus des 28 px une fois à l'écran.
var title_font_size: int = UITheme.FONT_SIZE_SMALL

var _tween: Tween = null

func _ready() -> void:
	custom_minimum_size = tile_size
	clip_contents = false
	if resize_on_focus:
		# La tuile est ancrée en bas de la rangée : elle s'étire donc vers le haut.
		size_flags_vertical = Control.SIZE_SHRINK_END
	_strip_button_style()
	_style_mask()
	_style_border()
	_style_glow()
	_style_labels()
	_style_favorite()
	_pivot.pivot_offset = Vector2(tile_size.x * 0.5, tile_size.y if grow_upwards else tile_size.y * 0.5)
	_layout_title()
	_border.modulate.a = 0.0
	_glow.modulate.a = 0.0
	_shade.texture = UITheme.tile_shade_texture(tile_size * Vector2(1.0, 0.55))
	if title_on_focus:
		_title.modulate.a = 0.0
		_shade.modulate.a = 0.0

	focus_entered.connect(_on_focus_changed.bind(true))
	focus_exited.connect(_on_focus_changed.bind(false))
	pressed.connect(_on_pressed)
	_refresh()

## Rectangle occupé par la jaquette à l'écran, mise à l'échelle du focus incluse.
## Sert de point de départ à la transition vers la fiche du jeu.
func cover_rect() -> Rect2:
	var xform: Transform2D = _mask.get_global_transform()
	return Rect2(xform.origin, _mask.size * xform.get_scale())

## Texture réellement affichée, pour que la transition reprenne la même image.
func cover_texture() -> Texture2D:
	return _cover.texture

## Associe un jeu à la tuile. Peut être appelé avant ou après l'entrée dans l'arbre.
func setup(entry: GameEntry) -> void:
	game = entry
	if is_node_ready():
		_refresh()

func _refresh() -> void:
	if game == null:
		return
	_title.text = game.title
	_favorite.visible = game.favorite
	var cover: Texture2D = ImageLoader.load_texture(game.cover)
	if cover == null:
		var wp_path: String = Wallpapers.for_id(game.id)
		if not wp_path.is_empty():
			cover = ImageLoader.load_texture(wp_path)
	var generated: bool = cover == null
	_cover.texture = cover if not generated else UITheme.cover_texture(game.id, tile_size)
	_title.visible = true
	_shade.visible = true

func _on_pressed() -> void:
	if game != null:
		activated.emit(game)

func _on_focus_changed(focused: bool) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	var opacity: float = 1.0 if focused else 0.0
	_tween = create_tween().set_parallel(true)

	# Le carrousel change la taille réelle des tuiles et pousse les voisines :
	# un démarrage progressif (EASE_IN_OUT) évite l'impression de glissement sec.
	# La grille se contente d'un agrandissement sur place, plus bref.
	var duration: float = UITheme.ANIM_CAROUSEL if resize_on_focus else UITheme.ANIM_SELECT
	if resize_on_focus:
		_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
		var target: Vector2 = tile_size * (focus_scale if focused else 1.0)
		_tween.tween_property(self, "custom_minimum_size", target, duration)
	else:
		_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		var target_scale: float = focus_scale if focused else 1.0
		_tween.tween_property(_pivot, "scale", Vector2.ONE * target_scale, duration)
		z_index = UITheme.Z_TILE_FOCUSED if focused else 0

	_tween.tween_property(_border, "modulate:a", opacity, duration)
	_tween.tween_property(_glow, "modulate:a", opacity, duration)
	if title_on_focus:
		_tween.tween_property(_title, "modulate:a", opacity, duration)
		_tween.tween_property(_shade, "modulate:a", opacity, duration)

## Le rendu est entièrement géré par les enfants : on neutralise le style du Button.
func _strip_button_style() -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(state, StyleBoxEmpty.new())

## Le masque arrondit les coins de la jaquette sans se dessiner lui-même.
func _style_mask() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.WHITE
	box.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS)
	_mask.add_theme_stylebox_override("panel", box)

func _style_border() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color.TRANSPARENT
	box.set_border_width_all(UITheme.TILE_BORDER_WIDTH)
	box.border_color = UITheme.COLOR_ACCENT
	box.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS)
	_border.add_theme_stylebox_override("panel", box)

## Halo placé derrière la jaquette : il ne déborde que sur le pourtour de la tuile.
func _style_glow() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = UITheme.COLOR_ACCENT
	box.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS)
	box.shadow_color = Color(UITheme.COLOR_ACCENT.r, UITheme.COLOR_ACCENT.g, UITheme.COLOR_ACCENT.b, 0.40)
	box.shadow_size = UITheme.FOCUS_GLOW_SIZE
	_glow.add_theme_stylebox_override("panel", box)

func _style_labels() -> void:
	_title.add_theme_font_size_override("font_size", title_font_size)
	_title.remove_theme_constant_override("shadow_offset_x")
	_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	if _star is Label:
		_star.add_theme_font_size_override("font_size", title_font_size)
		_star.remove_theme_constant_override("shadow_offset_x")
		_star.add_theme_color_override("font_color", UITheme.COLOR_ACCENT)
	elif _star != null:
		_star.modulate = UITheme.COLOR_ACCENT

## Le bandeau de titre est proportionnel à la tuile : la même scène sert
## à la grille (260 px) et au carrousel (180 px).
func _layout_title() -> void:
	var band_height: float = maxi(int(tile_size.y * 0.32), title_font_size * 2)
	var padding: float = tile_size.x * 0.06
	_title.offset_left = padding
	_title.offset_right = -padding
	_title.offset_top = -band_height
	_title.offset_bottom = -padding

## Pastille sombre : l'étoile reste lisible sur une jaquette claire.
func _style_favorite() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.07, 0.10, 0.85)
	box.border_color = Color(1.0, 1.0, 1.0, 0.18)
	box.set_border_width_all(1)
	box.set_corner_radius_all(14)
	_favorite.add_theme_stylebox_override("panel", box)
