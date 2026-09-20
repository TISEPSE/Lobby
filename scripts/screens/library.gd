extends Control

## Bibliothèque : grille de jaquettes, filtres et tri.
## Le fond suit la sélection ; valider une jaquette ouvre sa fiche.

signal selection_changed(game: GameEntry)
signal back_requested()
signal game_opened(game: GameEntry, source: Rect2, texture: Texture2D)

const TILE_SCENE: PackedScene = preload("res://scenes/components/game_tile.tscn")
const STATUS_TIMEOUT: float = 2.5

## Filtres proposés, dans l'ordre d'affichage.
const FILTERS: Array[Dictionary] = [
	{"id": "all", "label": "Tous"},
	{"id": "favorites", "label": "Favoris"},
	{"id": "recent", "label": "Récemment joué"},
]

## Tris proposés : le bouton passe de l'un à l'autre à chaque validation.
const SORTS: Array[Dictionary] = [
	{"id": "name", "label": "Nom"},
	{"id": "rating", "label": "Note"},
	{"id": "playtime", "label": "Temps de jeu"},
	{"id": "recent", "label": "Dernière partie"},
]

@onready var _page: ColorRect = $Page
@onready var _safe: MarginContainer = $Safe
@onready var _gap_top: Control = $Safe/Layout/GapTop
@onready var _header_pad: MarginContainer = $Safe/Layout/HeaderPad
@onready var _header: HBoxContainer = $Safe/Layout/HeaderPad/Header
@onready var _filters: HBoxContainer = $Safe/Layout/HeaderPad/Header/Filters
@onready var _title_pad: MarginContainer = $Safe/Layout/TitlePad
@onready var _page_title: Label = $Safe/Layout/TitlePad/PageTitle
@onready var _gap_title: Control = $Safe/Layout/GapTitle
@onready var _count_pad: MarginContainer = $Safe/Layout/CountPad
@onready var _count: Label = $Safe/Layout/CountPad/CountRow/Count
@onready var _sort_button: Button = $Safe/Layout/CountPad/CountRow/Sort
@onready var _gap_grid: Control = $Safe/Layout/GapGrid
@onready var _scroll: ScrollContainer = $Safe/Layout/Scroll
@onready var _grid_pad: MarginContainer = $Safe/Layout/Scroll/GridPad
@onready var _grid: GridContainer = $Safe/Layout/Scroll/GridPad/Grid
@onready var _help: HBoxContainer = $Safe/Layout/HelpBar
@onready var _empty: Label = $Empty
@onready var _status: Label = $Status

## La grille est l'élément principal : le fond passe au second plan.
## Déclaré en variable et non en constante, car la racine le lit avec `get()`,
## qui ne voit pas les constantes.
var dim_backdrop: bool = true

var filter_id: String = "all"
var sort_index: int = 0

var _tiles: Array[Button] = []
var _filter_buttons: Array[Button] = []
var _last_focused: Button = null
var _handed_over: Button = null
var _scroll_tween: Tween = null

func _ready() -> void:
	_apply_layout()
	_build_filters()
	GameLibrary.library_loaded.connect(_on_library_changed)
	GameLibrary.game_updated.connect(_on_game_single_updated)
	Launcher.game_started.connect(_on_game_started)
	Launcher.game_exited.connect(_on_game_exited)
	Launcher.launch_failed.connect(_on_launch_failed)
	_rebuild()

## Ouvre la bibliothèque sur un filtre donné : appelé par les raccourcis de l'accueil.
func setup(initial_filter: String) -> void:
	filter_id = initial_filter
	if is_node_ready():
		_refresh_filter_styles()
		_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		back_requested.emit()

func _apply_layout() -> void:
	_page.color = UITheme.COLOR_PAGE
	var margin: Vector2 = UITheme.safe_margin()
	_safe.add_theme_constant_override("margin_left", int(margin.x))
	_safe.add_theme_constant_override("margin_right", int(margin.x))
	_safe.add_theme_constant_override("margin_top", int(margin.y))
	_safe.add_theme_constant_override("margin_bottom", int(margin.y))

	_gap_top.custom_minimum_size.y = UITheme.SPACING_SMALL
	_gap_title.custom_minimum_size.y = UITheme.SPACING_SMALL
	_gap_grid.custom_minimum_size.y = UITheme.SPACING_SMALL
	_header.add_theme_constant_override("separation", int(UITheme.SPACING_MEDIUM))
	_filters.add_theme_constant_override("separation", UITheme.SPACING_SMALL)

	# La zone de défilement rogne ce qui dépasse : on lui réserve, sur les quatre
	# côtés, de quoi afficher l'agrandissement et le halo de la jaquette
	# sélectionnée. L'en-tête est décalé d'autant pour rester aligné sur elle.
	var overflow: int = int(UITheme.TILE_SIZE.x * (UITheme.TILE_FOCUS_SCALE - 1.0) * 0.5 + UITheme.FOCUS_GLOW_SIZE)
	for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_grid_pad.add_theme_constant_override(side, overflow)
	for pad: MarginContainer in [_title_pad, _header_pad, _count_pad]:
		pad.add_theme_constant_override("margin_left", overflow)
		pad.add_theme_constant_override("margin_right", overflow)

	_grid.columns = UITheme.GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", int(UITheme.TILE_SEPARATION.x))
	_grid.add_theme_constant_override("v_separation", int(UITheme.TILE_SEPARATION.y))

	_page_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	_page_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	for label: Label in [_count, _empty, _status]:
		label.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_count.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_empty.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_status.add_theme_color_override("font_color", UITheme.COLOR_TEXT)

	_style_tab(_sort_button)
	_sort_button.pressed.connect(_on_sort_pressed)
	_refresh_sort_label()

	_help.set_actions(ControllerGlyphs.actions([
		{"action": "ui_accept", "label": "Ouvrir"},
		{"action": "ui_cancel", "label": "Retour"},
	]))

func _build_filters() -> void:
	for entry: Dictionary in FILTERS:
		var button := Button.new()
		button.text = str(entry["label"])
		_style_tab(button)
		button.pressed.connect(_on_filter_pressed.bind(str(entry["id"])))
		_filters.add_child(button)
		_filter_buttons.append(button)
	_refresh_filter_styles()

## Les filtres et le tri forment une ligne : on y circule à gauche et à droite.
func _link_header() -> void:
	var row: Array[Button] = _filter_buttons.duplicate()
	row.append(_sort_button)
	for i: int in row.size():
		var button: Button = row[i]
		button.focus_neighbor_left = button.get_path_to(row[maxi(i - 1, 0)])
		button.focus_neighbor_right = button.get_path_to(row[mini(i + 1, row.size() - 1)])
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(_tiles[0] if not _tiles.is_empty() else button)
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right

func _rebuild() -> void:
	for tile: Button in _tiles:
		tile.queue_free()
	_tiles.clear()

	var games: Array[GameEntry] = _visible_games()
	for game: GameEntry in games:
		var tile: Button = TILE_SCENE.instantiate()
		tile.tile_size = UITheme.TILE_SIZE
		_grid.add_child(tile)
		tile.setup(game)
		tile.activated.connect(func(entry: GameEntry) -> void: _on_tile_activated(entry, tile))
		tile.focus_entered.connect(_on_tile_focused.bind(game))
		_tiles.append(tile)

	_count.text = "Tous : %d" % games.size()
	_empty.text = "Aucun jeu dans « %s »" % _filter_label(filter_id)
	_empty.visible = games.is_empty()
	_link_neighbors()
	_link_header()
	if not _tiles.is_empty():
		_tiles[0].grab_focus()
	elif not _filter_buttons.is_empty():
		_filter_buttons[0].grab_focus()

## Applique le filtre puis le tri courant.
func _visible_games() -> Array[GameEntry]:
	var games: Array[GameEntry] = []
	for game: GameEntry in GameLibrary.games:
		match filter_id:
			"favorites":
				if game.favorite:
					games.append(game)
			"recent":
				if game.last_played != null:
					games.append(game)
			_:
				games.append(game)

	var mode: String = str(SORTS[sort_index]["id"])
	games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
		match mode:
			"rating":
				return a.rating > b.rating
			"playtime":
				return a.playtime_minutes > b.playtime_minutes
			"recent":
				return str(a.last_played) > str(b.last_played)
			_:
				return a.title.naturalnocasecmp_to(b.title) < 0
	)
	return games

## Voisinage explicite : le focus ne sort jamais de la grille, sauf vers l'en-tête.
func _link_neighbors() -> void:
	var columns: int = _grid.columns
	var count: int = _tiles.size()
	for i: int in count:
		var tile: Button = _tiles[i]
		var row: int = i / columns
		var column: int = i % columns
		var left: int = i - 1 if column > 0 else i
		var right: int = i + 1 if column < columns - 1 and i + 1 < count else i
		var down: int = i + columns if i + columns < count else i
		tile.focus_neighbor_left = tile.get_path_to(_tiles[left])
		tile.focus_neighbor_right = tile.get_path_to(_tiles[right])
		tile.focus_neighbor_bottom = tile.get_path_to(_tiles[down])
		if row > 0:
			tile.focus_neighbor_top = tile.get_path_to(_tiles[i - columns])
		else:
			# Depuis la première ligne, on remonte vers le filtre le plus proche.
			var target: int = mini(column * _filter_buttons.size() / maxi(columns, 1), _filter_buttons.size() - 1)
			tile.focus_neighbor_top = tile.get_path_to(_filter_buttons[target])
		tile.focus_previous = tile.focus_neighbor_left
		tile.focus_next = tile.focus_neighbor_right

## Défilement par lignes entières, jamais une jaquette coupée.
func _scroll_to_row(index: int) -> void:
	var view: float = _scroll.size.y
	if view <= 0.0 or index < 0:
		return
	var step: float = UITheme.TILE_SIZE.y + UITheme.TILE_SEPARATION.y
	var row: int = index / _grid.columns
	var top: float = float(row) * step + float(_grid_pad.get_theme_constant("margin_top"))
	var bottom: float = top + UITheme.TILE_SIZE.y
	var target: float = float(_scroll.scroll_vertical)
	if bottom > target + view:
		target = bottom - view
	if top < target:
		target = top

	if _scroll_tween != null and _scroll_tween.is_running():
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_scroll_tween.tween_property(_scroll, "scroll_vertical", int(maxf(target, 0.0)), UITheme.ANIM_CAROUSEL)

func _on_filter_pressed(id: String) -> void:
	if filter_id == id:
		return
	filter_id = id
	_refresh_filter_styles()
	_rebuild()

func _on_sort_pressed() -> void:
	sort_index = (sort_index + 1) % SORTS.size()
	_refresh_sort_label()
	_rebuild()
	_sort_button.grab_focus()

func _refresh_sort_label() -> void:
	_sort_button.text = "Trier par : %s" % str(SORTS[sort_index]["label"])

## L'onglet actif est en blanc, les autres en gris : pas d'aplat de couleur.
func _refresh_filter_styles() -> void:
	for i: int in _filter_buttons.size():
		var active: bool = str(FILTERS[i]["id"]) == filter_id
		_filter_buttons[i].add_theme_color_override("font_color", UITheme.COLOR_TEXT if active else UITheme.COLOR_TEXT_DIM)

func _filter_label(id: String) -> String:
	for entry: Dictionary in FILTERS:
		if str(entry["id"]) == id:
			return str(entry["label"])
	return id

## Onglet : du texte, rien d'autre. Seul le focus ajoute un contour.
func _style_tab(button: Button) -> void:
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	button.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = UITheme.SPACING_MEDIUM
	flat.content_margin_right = UITheme.SPACING_MEDIUM
	flat.content_margin_top = UITheme.SPACING_SMALL
	flat.content_margin_bottom = UITheme.SPACING_SMALL
	var focus: StyleBoxFlat = UITheme.focus_box(UITheme.TILE_CORNER_RADIUS, false)
	focus.content_margin_left = UITheme.SPACING_MEDIUM
	focus.content_margin_right = UITheme.SPACING_MEDIUM
	focus.content_margin_top = UITheme.SPACING_SMALL
	focus.content_margin_bottom = UITheme.SPACING_SMALL
	button.add_theme_stylebox_override("normal", flat)
	button.add_theme_stylebox_override("hover", flat)
	button.add_theme_stylebox_override("pressed", focus)
	button.add_theme_stylebox_override("focus", focus)

func _on_tile_focused(game: GameEntry) -> void:
	var tile: Button = get_viewport().gui_get_focus_owner() as Button
	_last_focused = tile
	_scroll_to_row(_tiles.find(tile))
	selection_changed.emit(game)

func _on_tile_activated(game: GameEntry, tile: Button = null) -> void:
	if tile == null:
		tile = get_viewport().gui_get_focus_owner() as Button
	if tile == null:
		for t: Button in _tiles:
			if t.game == game:
				tile = t
				break
	if tile == null:
		return
	_last_focused = tile
	if tile.focus_mode != Control.FOCUS_NONE:
		tile.grab_focus()
	_handed_over = tile
	tile.modulate.a = 0.0
	game_opened.emit(game, tile.cover_rect(), tile.cover_texture())

## Appelé par la racine quand l'écran redevient actif : le fantôme est revenu
## se poser, la vraie jaquette peut reprendre sa place.
func on_resumed() -> void:
	if _handed_over != null and is_instance_valid(_handed_over):
		_handed_over.modulate.a = 1.0
	_handed_over = null

func _on_library_changed(_games: Array) -> void:
	_rebuild()

## Un favori retiré doit disparaître de la vue « Favoris ».
func _on_game_single_updated(_game: GameEntry) -> void:
	if filter_id == "all":
		for tile: Button in _tiles:
			tile.setup(tile.game)
		return
	_rebuild()

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
	for button: Button in _tiles + _filter_buttons + [_sort_button]:
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
		button.disabled = not enabled

## Le focus ne doit jamais être perdu.
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
