extends Control

## Écran d'accueil : artwork du jeu sélectionné, rangée de jeux récents,
## rangée de raccourcis. Inspiré du hub des consoles de salon.

signal selection_changed(game: GameEntry)
signal game_opened(game: GameEntry, source: Rect2, texture: Texture2D)
signal shortcut_activated(action: String)

const TILE_SCENE: PackedScene = preload("res://scenes/components/game_tile.tscn")
const SHORTCUT_SCENE: PackedScene = preload("res://scenes/components/shortcut_tile.tscn")
const STATUS_TIMEOUT: float = 2.5

## Raccourcis de la rangée basse : libellé, action émise, teinte de fond.
const SHORTCUTS: Array[Dictionary] = [
	{"label": "Parcourir les jeux", "action": "library", "color": Color("1d2430")},
	{"label": "Favoris", "action": "favorites", "color": Color("22202c")},
	{"label": "Récemment joué", "action": "recent", "color": Color("1b2622")},
	{"label": "Paramètres", "action": "settings", "color": Color("22242a")},
]

@onready var _safe: MarginContainer = $Safe
@onready var _top_bar: Control = $Safe/Layout/TopBar
@onready var _row: Control = $Safe/Layout/CarouselRow
@onready var _scroll: ScrollContainer = $Safe/Layout/CarouselRow/CarouselScroll
@onready var _carousel: HBoxContainer = $Safe/Layout/CarouselRow/CarouselScroll/Carousel
@onready var _arrow_left: TextureRect = $Safe/Layout/CarouselRow/ArrowLeft
@onready var _arrow_right: TextureRect = $Safe/Layout/CarouselRow/ArrowRight

var _gutter_left: Control = null
var _gutter_right: Control = null
@onready var _gap: Control = $Safe/Layout/GapRows
@onready var _shortcuts: HBoxContainer = $Safe/Layout/Shortcuts
@onready var _sidebar: Control = $Sidebar
@onready var _power_menu: Control = $PowerMenu
@onready var _status: Label = $Status

var _tiles: Array[Button] = []
var _scroll_tween: Tween = null
## Index de la première jaquette affichée : le défilement se fait par tuiles
## entières, seul moyen d'avoir la même marge à gauche et à droite.
var _first_visible: int = 0
var _fade_tween: Tween = null
var _shortcut_tiles: Array[Button] = []
var _last_focused: Button = null
var _handed_over: Button = null

func _ready() -> void:
	_apply_layout()
	_build_shortcuts()
	_top_bar.icon_activated.connect(_on_icon_activated)
	_sidebar.closed.connect(_on_sidebar_closed)
	_sidebar.power_requested.connect(_power_menu.open)
	_sidebar.navigate.connect(_on_sidebar_navigate)
	_power_menu.message.connect(_show_status)
	GameLibrary.library_loaded.connect(_on_library_loaded)
	GameLibrary.game_updated.connect(_on_game_updated)
	Launcher.game_started.connect(_on_game_started)
	Launcher.game_exited.connect(_on_game_exited)
	Launcher.launch_failed.connect(_on_launch_failed)
	if not GameLibrary.games.is_empty():
		_on_library_loaded(GameLibrary.games)

func _on_game_updated(updated: GameEntry) -> void:
	for tile: Button in _tiles:
		if tile.game != null and tile.game.id == updated.id:
			tile.setup(updated)

func _apply_layout() -> void:
	var margin: Vector2 = UITheme.safe_margin()
	_safe.add_theme_constant_override("margin_left", int(margin.x))
	_safe.add_theme_constant_override("margin_right", int(margin.x))
	_safe.add_theme_constant_override("margin_top", int(margin.y))
	_safe.add_theme_constant_override("margin_bottom", int(margin.y))

	_carousel.add_theme_constant_override("separation", UITheme.CAROUSEL_SEPARATION)
	_carousel.alignment = BoxContainer.ALIGNMENT_BEGIN

	# Isolation du carrousel dans un MarginContainer pour réserver l'espace du halo lumineux
	# en haut et en bas sans que le ScrollContainer ne coupe les ombres portées.
	if _carousel.get_parent() == _scroll:
		var margin_wrap := MarginContainer.new()
		margin_wrap.name = "CarouselMargin"
		margin_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
		margin_wrap.add_theme_constant_override("margin_top", int(UITheme.CAROUSEL_TOP_ROOM))
		margin_wrap.add_theme_constant_override("margin_bottom", int(UITheme.CAROUSEL_BOTTOM_ROOM))
		_scroll.remove_child(_carousel)
		margin_wrap.add_child(_carousel)
		_scroll.add_child(margin_wrap)

	_row.custom_minimum_size.y = UITheme.CAROUSEL_TILE_SIZE.y * UITheme.CAROUSEL_FOCUS_SCALE + UITheme.CAROUSEL_TOP_ROOM + UITheme.CAROUSEL_BOTTOM_ROOM
	_setup_arrows()
	_shortcuts.add_theme_constant_override("separation", UITheme.SHORTCUT_SEPARATION)
	_gap.custom_minimum_size.y = UITheme.SPACING_MEDIUM

	_status.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_status.add_theme_color_override("font_color", UITheme.COLOR_TEXT)

## Flèches de défilement : discrètes, affichées seulement s'il reste des jeux
## du côté concerné. Elles remplacent l'aperçu d'une jaquette coupée.
func _setup_arrows() -> void:
	var chevron: Texture2D = load("res://assets/icons/chevron.svg")
	var size := Vector2(UITheme.CAROUSEL_ARROW_SIZE, UITheme.CAROUSEL_ARROW_SIZE)
	var half: float = UITheme.CAROUSEL_ARROW_SIZE * 0.5
	var center_from_bottom: float = UITheme.CAROUSEL_BOTTOM_ROOM + UITheme.CAROUSEL_TILE_SIZE.y * 0.5
	for arrow: TextureRect in [_arrow_left, _arrow_right]:
		arrow.texture = chevron
		arrow.custom_minimum_size = size
		arrow.modulate = Color(UITheme.COLOR_TEXT, 0.0)
		arrow.anchor_top = 1.0
		arrow.anchor_bottom = 1.0
		arrow.offset_top = -center_from_bottom - half
		arrow.offset_bottom = -center_from_bottom + half
	_arrow_left.flip_h = true

func _build_shortcuts() -> void:
	for entry: Dictionary in SHORTCUTS:
		var tile: Button = SHORTCUT_SCENE.instantiate()
		tile.setup(str(entry["label"]), str(entry["action"]), entry["color"])
		_shortcuts.add_child(tile)
		tile.activated.connect(_on_shortcut_activated)
		tile.focus_entered.connect(func() -> void:
			_last_focused = tile
			_sidebar.set_return_target(tile)
		)
		_shortcut_tiles.append(tile)

func _on_library_loaded(games: Array) -> void:
	for tile: Button in _tiles:
		tile.queue_free()
	_tiles.clear()

	_gutter_left = _make_gutter()
	_carousel.add_child(_gutter_left)
	for i: int in games.size():
		var game: GameEntry = games[i]
		var tile: Button = TILE_SCENE.instantiate()
		tile.tile_size = UITheme.CAROUSEL_TILE_SIZE
		tile.focus_scale = UITheme.CAROUSEL_FOCUS_SCALE
		tile.grow_upwards = true
		tile.resize_on_focus = true
		# Le titre reste lisible sur toutes les jaquettes, pas seulement celle
		# qui est sélectionnée : sans lui, un jeu n'est pas identifiable.
		tile.title_on_focus = false
		tile.title_font_size = UITheme.FONT_SIZE_CAROUSEL_TITLE
		_carousel.add_child(tile)
		tile.setup(game)
		tile.activated.connect(func(entry: GameEntry) -> void: _on_tile_activated(entry, tile))
		tile.focus_entered.connect(_on_tile_focused.bind(game))
		tile.focus_entered.connect(_scroll_to_tile.bind(i))
		_tiles.append(tile)

	_gutter_right = _make_gutter()
	_carousel.add_child(_gutter_right)
	_link_neighbors()
	if not _tiles.is_empty():
		_tiles[0].grab_focus()
		# Le premier calcul a besoin d'une rangée déjà dimensionnée. Le focus a pu
		# changer d'ici là : on recalcule pour la tuile réellement sélectionnée.
		await get_tree().process_frame
		var focused: int = _tiles.find(get_viewport().gui_get_focus_owner())
		_scroll_to_tile(maxi(focused, 0))

## Voisinage explicite entre les rangées et le panneau latéral :
## pousser à gauche sur la 1ère tuile ouvre le panneau latéral.
func _link_neighbors() -> void:
	var side_entry: Control = _sidebar.first_entry()
	for i: int in _tiles.size():
		var tile: Button = _tiles[i]
		var left: int = maxi(i - 1, 0)
		var right: int = mini(i + 1, _tiles.size() - 1)
		if i == 0 and side_entry != null:
			tile.focus_neighbor_left = tile.get_path_to(side_entry)
		else:
			tile.focus_neighbor_left = tile.get_path_to(_tiles[left])
		tile.focus_neighbor_right = tile.get_path_to(_tiles[right])
		tile.focus_neighbor_top = tile.get_path_to(_icon_above(i, tile))
		if not _shortcut_tiles.is_empty():
			var below: int = mini(i / 2, _shortcut_tiles.size() - 1)
			tile.focus_neighbor_bottom = tile.get_path_to(_shortcut_tiles[below])
		tile.focus_previous = tile.focus_neighbor_left
		tile.focus_next = tile.focus_neighbor_right

	for i: int in _shortcut_tiles.size():
		var tile: Button = _shortcut_tiles[i]
		var left: int = maxi(i - 1, 0)
		var right: int = mini(i + 1, _shortcut_tiles.size() - 1)
		if i == 0 and side_entry != null:
			tile.focus_neighbor_left = tile.get_path_to(side_entry)
		else:
			tile.focus_neighbor_left = tile.get_path_to(_shortcut_tiles[left])
		tile.focus_neighbor_right = tile.get_path_to(_shortcut_tiles[right])
		tile.focus_neighbor_bottom = tile.get_path_to(tile)
		if not _tiles.is_empty():
			var above: int = mini(i * 2, _tiles.size() - 1)
			tile.focus_neighbor_top = tile.get_path_to(_tiles[above])
		tile.focus_previous = tile.focus_neighbor_left
		tile.focus_next = tile.focus_neighbor_right

## Le panneau demande un écran : on relaie vers la racine, qui gère la pile.
func _on_sidebar_navigate(action: String) -> void:
	_sidebar.close()
	shortcut_activated.emit(action)

## Ouvre le panneau latéral (touche Options, ou outil de capture).
func open_sidebar() -> void:
	_sidebar.open()

## Ouvre la fenêtre d'alimentation (touche X, ou outil de capture).
func open_power_menu() -> void:
	_power_menu.open()

func _unhandled_input(event: InputEvent) -> void:
	# Options bascule le panneau latéral (ouvre ou ferme).
	if event.is_action_pressed("ui_options"):
		get_viewport().set_input_as_handled()
		if _power_menu.is_open:
			_power_menu.close()
		elif _sidebar.is_open:
			_sidebar.close()
		else:
			_sidebar.open()

## Espace vide au début et à la fin de la rangée, réservé aux flèches.
func _make_gutter() -> Control:
	var gutter := Control.new()
	gutter.custom_minimum_size.x = UITheme.CAROUSEL_MIN_GUTTER
	gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gutter

## Icône visée en montant depuis la tuile i : on garde le même ordre de gauche
## à droite, pour que le focus ne traverse pas l'écran.
func _icon_above(index: int, fallback: Control) -> Control:
	var icons: Array[Button] = _top_bar.icon_buttons()
	if icons.is_empty() or _tiles.size() <= 1:
		return icons[0] if not icons.is_empty() else fallback
	var ratio: float = float(index) / float(_tiles.size() - 1)
	return icons[clampi(int(round(ratio * float(icons.size() - 1))), 0, icons.size() - 1)]

## Redescendre depuis la barre ramène sur le jeu sélectionné.
func _update_icon_return(target: Control) -> void:
	for icon: Button in _top_bar.icon_buttons():
		icon.focus_neighbor_bottom = icon.get_path_to(target)

func _on_icon_activated(action: String) -> void:
	if action in ["library", "settings"]:
		shortcut_activated.emit(action)
		return
	_show_status("Bientôt disponible")
	get_tree().create_timer(STATUS_TIMEOUT).timeout.connect(_hide_status)

## Le panneau rend la main : on revient sur le dernier élément sélectionné.
func _on_sidebar_closed() -> void:
	_restore_focus()

func _on_tile_focused(game: GameEntry) -> void:
	_last_focused = get_viewport().gui_get_focus_owner() as Button
	if _last_focused != null:
		_update_icon_return(_last_focused)
		_sidebar.set_return_target(_last_focused)
	selection_changed.emit(game)

## Fait défiler la rangée par tuiles entières, de sorte que la marge avant la
## première jaquette et celle après la dernière soient toujours identiques.
func _scroll_to_tile(index: int) -> void:
	# Au tout premier focus la rangée n'est pas encore dimensionnée.
	var view: float = _scroll.size.x
	if view <= 0.0:
		return

	var width: float = UITheme.CAROUSEL_TILE_SIZE.x
	var separation: float = UITheme.CAROUSEL_SEPARATION
	var step: float = width + separation
	var focused_width: float = width * UITheme.CAROUSEL_FOCUS_SCALE

	# Nombre de jaquettes entières qui tiennent, l'une d'elles étant agrandie,
	# en gardant au moins la place d'une flèche de chaque côté.
	var free_space: float = view - 2.0 * (UITheme.CAROUSEL_MIN_GUTTER + separation)
	var count: int = int(floor((free_space - focused_width) / step)) + 1
	count = clampi(count, 1, _tiles.size())

	# Le reste de la largeur est réparti également entre les deux bords.
	var content: float = float(count - 1) * step + focused_width
	var gutter: float = maxf((view - content) * 0.5, UITheme.CAROUSEL_MIN_GUTTER)
	_gutter_left.custom_minimum_size.x = gutter - separation
	_gutter_right.custom_minimum_size.x = gutter - separation
	_place_arrows(gutter)

	# La fenêtre glisse juste assez pour contenir la tuile sélectionnée.
	_first_visible = clampi(_first_visible, index - count + 1, index)
	_first_visible = clampi(_first_visible, 0, maxi(_tiles.size() - count, 0))

	if _scroll_tween != null and _scroll_tween.is_running():
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_scroll_tween.tween_property(_scroll, "scroll_horizontal", int(_first_visible * step), UITheme.ANIM_CAROUSEL)

	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_fade_partial_tiles(count)
	_update_arrows(_first_visible > 0, _first_visible + count < _tiles.size())

## Chaque flèche est centrée dans sa gouttière.
func _place_arrows(gutter: float) -> void:
	var half: float = UITheme.CAROUSEL_ARROW_SIZE * 0.5
	var center: float = gutter * 0.5
	_arrow_left.offset_left = center - half
	_arrow_left.offset_right = center + half
	_arrow_right.offset_left = -center - half
	_arrow_right.offset_right = -center + half

## Seules les jaquettes de la fenêtre courante sont visibles : aucune n'est
## montrée à moitié, et aucune ne passe sous une flèche.
func _fade_partial_tiles(count: int) -> void:
	for j: int in _tiles.size():
		var inside: bool = j >= _first_visible and j < _first_visible + count
		var alpha: float = 1.0 if inside else UITheme.CAROUSEL_CLIPPED_ALPHA
		if not is_equal_approx(_tiles[j].modulate.a, alpha):
			_fade_tween.tween_property(_tiles[j], "modulate:a", alpha, UITheme.ANIM_CAROUSEL)

func _update_arrows(show_left: bool, show_right: bool) -> void:
	_fade_tween.tween_property(_arrow_left, "modulate:a", UITheme.CAROUSEL_ARROW_ALPHA if show_left else 0.0, UITheme.ANIM_CAROUSEL)
	_fade_tween.tween_property(_arrow_right, "modulate:a", UITheme.CAROUSEL_ARROW_ALPHA if show_right else 0.0, UITheme.ANIM_CAROUSEL)

func _on_shortcut_activated(action: String) -> void:
	# Ces trois raccourcis mènent à la bibliothèque, sur le filtre correspondant.
	if action in ["library", "favorites", "recent", "settings"]:
		shortcut_activated.emit(action)
		return
	_show_status("Bientôt disponible")
	get_tree().create_timer(STATUS_TIMEOUT).timeout.connect(_hide_status)

func _on_tile_activated(game: GameEntry, tile: Button = null) -> void:
	if tile == null:
		tile = get_viewport().gui_get_focus_owner() as Button
	if tile == null:
		return
	_last_focused = tile
	if tile.focus_mode != Control.FOCUS_NONE:
		tile.grab_focus()
	# La jaquette d'origine s'efface : à partir d'ici c'est le fantôme de la
	# fiche qui la représente. Sans cela elle poursuivrait son agrandissement
	# derrière lui, et l'on verrait deux jaquettes diverger.
	_handed_over = tile
	tile.modulate.a = 0.0
	game_opened.emit(game, tile.cover_rect(), tile.cover_texture())

## Appelé par la racine quand l'écran redevient actif : le fantôme est revenu
## se poser, la vraie jaquette peut reprendre sa place.
func on_resumed() -> void:
	if _handed_over != null and is_instance_valid(_handed_over):
		_handed_over.modulate.a = 1.0
	_handed_over = null

func _on_game_started(game: GameEntry) -> void:
	_show_status(Launcher.launch_notice(game))
	_set_enabled(false)

func _on_game_exited(game: GameEntry, minutes: int) -> void:
	_hide_status()
	_set_enabled(true)
	print("[Launcher] %s terminé après %d min (total : %s)" % [game.title, minutes, game.playtime_text()])
	_restore_focus()

func _on_launch_failed(game: GameEntry, reason: String) -> void:
	_show_status("%s : %s" % [game.title, reason])
	get_tree().create_timer(STATUS_TIMEOUT).timeout.connect(_hide_status)

func _set_enabled(enabled: bool) -> void:
	for tile: Button in _tiles + _shortcut_tiles + _top_bar.icon_buttons():
		tile.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		tile.disabled = not enabled

## Le focus ne doit jamais être perdu : on revient sur la dernière tuile, sinon la première.
func _restore_focus() -> void:
	if _last_focused != null and is_instance_valid(_last_focused):
		_last_focused.grab_focus()
	elif not _tiles.is_empty():
		_tiles[0].grab_focus()

func _show_status(text: String) -> void:
	_status.text = text
	_status.visible = true

func _hide_status() -> void:
	_status.visible = false
