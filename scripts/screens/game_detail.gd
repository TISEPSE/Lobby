extends Control

## Fiche d'un jeu : jaquette, métadonnées, synopsis et actions.
## C'est d'ici qu'on lance le jeu, plus directement depuis une jaquette.

signal selection_changed(game: GameEntry)
signal back_requested()
## Émis dès le début de l'animation de retour, pour que l'écran précédent
## réapparaisse pendant que la jaquette rejoint sa tuile.
signal closing()

const COVER_SIZE: Vector2 = Vector2(430, 430)
const BUTTON_SIZE: Vector2 = Vector2(260, 78)
const BUTTON_SEPARATION: int = 20
const STATUS_TIMEOUT: float = 2.5
## Nombre maximal d'images attendues pour que la mise en page se stabilise.
const MAX_LAYOUT_FRAMES: int = 8

@onready var _safe: MarginContainer = $Safe
@onready var _layout: VBoxContainer = $Safe/Layout
@onready var _gap_top: Control = $Safe/Layout/GapTop
@onready var _content: HBoxContainer = $Safe/Layout/Content
@onready var _cover: TextureRect = $Safe/Layout/Content/Cover
@onready var _info: VBoxContainer = $Safe/Layout/Content/Info
@onready var _title: Label = $Safe/Layout/Content/Info/Title
@onready var _meta: Label = $Safe/Layout/Content/Info/Meta
@onready var _gap_meta: Control = $Safe/Layout/Content/Info/GapMeta
## Rangée d'étoiles, créée en code à côté de la ligne d'informations.
var _stars: HBoxContainer = null
@onready var _synopsis: Label = $Safe/Layout/Content/Info/Synopsis
@onready var _gap_actions: Control = $Safe/Layout/Content/Info/GapActions
@onready var _actions: HBoxContainer = $Safe/Layout/Content/Info/Actions
@onready var _help: HBoxContainer = $Safe/Layout/HelpBar
@onready var _ghost: TextureRect = $Ghost
@onready var _status: Label = $Status

## La fiche est faite pour être lue : le fond s'efface derrière le texte.
## Variable et non constante, la racine la lit avec `get()`.
var dim_backdrop: bool = true

var game: GameEntry = null

var _play_button: Button = null
var _favorite_button: Button = null
var _source_rect: Rect2 = Rect2()
var _closing: bool = false

func _ready() -> void:
	_apply_layout()
	_build_actions()
	GameLibrary.game_updated.connect(_on_game_updated)
	Launcher.game_started.connect(_on_game_started)
	Launcher.game_exited.connect(_on_game_exited)
	Launcher.launch_failed.connect(_on_launch_failed)
	_refresh()

## Renseigné par la racine avant l'ajout à l'arbre.
func setup(entry: GameEntry) -> void:
	game = entry
	if is_node_ready():
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not _closing:
		get_viewport().set_input_as_handled()
		close()

## Ouverture : la jaquette part de la tuile d'origine et rejoint sa place,
## puis les informations se révèlent. Sans rectangle source, tout est immédiat.
func play_open_transition(source: Rect2, texture: Texture2D) -> void:
	_source_rect = source
	if source.size.x <= 0.0:
		_play_button.grab_focus()
		return

	_info.modulate.a = 0.0
	_cover.modulate.a = 0.0
	_ghost.texture = texture if texture != null else _cover.texture
	_ghost.position = source.position
	_ghost.size = source.size
	_ghost.visible = true

	# Le rectangle d'arrivée n'existe qu'une fois la mise en page calculée, et
	# selon la longueur du titre et du synopsis cela demande plusieurs images.
	# Le lire trop tôt renvoie un rectangle vide au coin de l'écran : la jaquette
	# y filait avant de sauter à sa vraie place.
	var target: Rect2 = await _settled_cover_rect()

	var tween: Tween = create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_ghost, "position", target.position, UITheme.ANIM_TRANSITION)
	tween.tween_property(_ghost, "size", target.size, UITheme.ANIM_TRANSITION)
	tween.chain().tween_callback(_on_open_arrived)
	tween.chain().tween_property(_info, "modulate:a", 1.0, UITheme.ANIM_SCREEN_FADE)

## Attend que le rectangle de la jaquette ne bouge plus d'une image à l'autre.
func _settled_cover_rect() -> Rect2:
	var safe_margin: Vector2 = UITheme.safe_margin()
	# Position de secours théorique : sous la TopBar dans la marge de sécurité
	var default_target := Rect2(Vector2(safe_margin.x, safe_margin.y + 108.0), COVER_SIZE)

	var previous: Rect2 = _cover.get_global_rect()
	for _i: int in MAX_LAYOUT_FRAMES:
		await get_tree().process_frame
		var current: Rect2 = _cover.get_global_rect()
		# La jaquette est sous l'en-tête : sa position Y globale est toujours > 50 px
		if current.size.x > 0.0 and current.position.y > 50.0 and current.position.x > 0.0:
			if current.is_equal_approx(previous):
				return current
		previous = current

	if previous.size.x > 0.0 and previous.position.y > 50.0:
		return previous
	return default_target

func _on_open_arrived() -> void:
	_cover.modulate.a = 1.0
	_ghost.visible = false
	_play_button.grab_focus()

## Fermeture : l'inverse, la jaquette retourne se poser sur sa tuile.
func close() -> void:
	if _closing:
		return
	_closing = true
	closing.emit()
	if _source_rect.size.x <= 0.0:
		back_requested.emit()
		return

	var cover_rect: Rect2 = _cover.get_global_rect()
	if cover_rect.size.x <= 0.0 or cover_rect.position.y <= 0.0:
		var safe_margin: Vector2 = UITheme.safe_margin()
		cover_rect = Rect2(Vector2(safe_margin.x, safe_margin.y + 108.0), COVER_SIZE)

	_ghost.position = cover_rect.position
	_ghost.size = cover_rect.size
	_ghost.visible = true
	_cover.modulate.a = 0.0

	var tween: Tween = create_tween().set_parallel(true)
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_safe, "modulate:a", 0.0, UITheme.ANIM_SCREEN_FADE)
	tween.tween_property(_ghost, "position", _source_rect.position, UITheme.ANIM_TRANSITION)
	tween.tween_property(_ghost, "size", _source_rect.size, UITheme.ANIM_TRANSITION)
	tween.chain().tween_callback(func() -> void: back_requested.emit())

func _apply_layout() -> void:
	var margin: Vector2 = UITheme.safe_margin()
	_safe.add_theme_constant_override("margin_left", int(margin.x))
	_safe.add_theme_constant_override("margin_right", int(margin.x))
	_safe.add_theme_constant_override("margin_top", int(margin.y))
	_safe.add_theme_constant_override("margin_bottom", int(margin.y))

	_gap_top.custom_minimum_size.y = UITheme.SPACING_LARGE
	_gap_meta.custom_minimum_size.y = UITheme.SPACING_MEDIUM
	_gap_actions.custom_minimum_size.y = UITheme.SPACING_LARGE
	_content.add_theme_constant_override("separation", int(UITheme.SPACING_LARGE))
	_info.add_theme_constant_override("separation", UITheme.SPACING_SMALL)
	_actions.add_theme_constant_override("separation", BUTTON_SEPARATION)
	_cover.custom_minimum_size = COVER_SIZE

	_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_HERO)
	_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_meta.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_meta.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_synopsis.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_synopsis.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	_status.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	_status.add_theme_color_override("font_color", UITheme.COLOR_TEXT)

	_help.set_actions(ControllerGlyphs.actions([
		{"action": "ui_accept", "label": "Valider"},
		{"action": "ui_cancel", "label": "Retour"},
	]))

func _build_actions() -> void:
	_play_button = _make_button("Jouer")
	_favorite_button = _make_button("Favori")
	_play_button.pressed.connect(_on_play_pressed)
	_favorite_button.pressed.connect(_on_favorite_pressed)
	_actions.add_child(_play_button)
	_actions.add_child(_favorite_button)

	# Voisinage explicite : le focus ne quitte jamais la ligne d'actions.
	var buttons: Array[Button] = [_play_button, _favorite_button]
	for i: int in buttons.size():
		var button: Button = buttons[i]
		var left: Button = buttons[maxi(i - 1, 0)]
		var right: Button = buttons[mini(i + 1, buttons.size() - 1)]
		button.focus_neighbor_left = button.get_path_to(left)
		button.focus_neighbor_right = button.get_path_to(right)
		button.focus_neighbor_top = button.get_path_to(button)
		button.focus_neighbor_bottom = button.get_path_to(button)
		button.focus_previous = button.focus_neighbor_left
		button.focus_next = button.focus_neighbor_right

func _refresh() -> void:
	if game == null:
		return
	_title.text = game.title
	var facts: PackedStringArray = PackedStringArray()
	for fact: String in [game.genre, game.release_date.substr(0, 4), game.playtime_text()]:
		if not fact.strip_edges().is_empty():
			facts.append(fact)
	_meta.text = "  ·  ".join(facts)
	_refresh_stars()
	_synopsis.text = game.synopsis

	var cover: Texture2D = ImageLoader.load_texture(game.cover)
	_cover.texture = cover if cover != null else UITheme.cover_texture(game.id, COVER_SIZE)
	_refresh_favorite()
	selection_changed.emit(game)

## La note s'affiche en étoiles, à côté des informations du jeu. Elles sont
## reconstruites à chaque affichage : la note arrive parfois après coup, quand
## les métadonnées ont fini d'être téléchargées.
func _refresh_stars() -> void:
	if _stars != null and is_instance_valid(_stars):
		_stars.queue_free()
	_stars = RatingStars.make(game.rating, UITheme.STAR_SIZE)
	var parent: Node = _meta.get_parent()
	parent.add_child(_stars)
	parent.move_child(_stars, _meta.get_index() + 1)

func _refresh_favorite() -> void:
	_favorite_button.text = "Retirer des favoris" if game.favorite else "Ajouter aux favoris"

func _on_play_pressed() -> void:
	Launcher.launch(game)

func _on_favorite_pressed() -> void:
	game.favorite = not game.favorite
	GameLibrary.save_library()
	GameLibrary.game_updated.emit(game)

func _on_game_updated(updated: GameEntry) -> void:
	if game != null and updated.id == game.id:
		_refresh_favorite()

func _on_game_started(started: GameEntry) -> void:
	_show_status(Launcher.launch_notice(started))
	_set_enabled(false)

func _on_game_exited(exited: GameEntry, minutes: int) -> void:
	_hide_status()
	_set_enabled(true)
	print("[Launcher] %s terminé après %d min (total : %s)" % [exited.title, minutes, exited.playtime_text()])
	_refresh()
	_play_button.grab_focus()

func _on_launch_failed(failed: GameEntry, reason: String) -> void:
	_show_status("%s : %s" % [failed.title, reason])
	get_tree().create_timer(STATUS_TIMEOUT).timeout.connect(_hide_status)

func _set_enabled(enabled: bool) -> void:
	for button: Button in [_play_button, _favorite_button]:
		button.disabled = not enabled
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = BUTTON_SIZE
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	button.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	button.add_theme_stylebox_override("normal", UITheme.surface_box())
	button.add_theme_stylebox_override("hover", UITheme.surface_box())
	button.add_theme_stylebox_override("pressed", UITheme.focus_box())
	button.add_theme_stylebox_override("focus", UITheme.focus_box())
	return button

func _show_status(text: String) -> void:
	_status.text = text
	_status.visible = true

func _hide_status() -> void:
	_status.visible = false
