extends Control

## Fond de l'interface : artwork du jeu sélectionné, en fondu enchaîné.
## Les artworks sont chargés en tâche de fond : décoder un JPEG de plusieurs
## mégaoctets prend près d'une seconde, ce qui figerait la navigation.
## Sans image disponible, on retombe sur des dégradés générés.

## Largeur maximale conservée d'un artwork : au-delà, c'est de la mémoire et du
## temps de décodage pour rien.
const ARTWORK_MAX_WIDTH: int = 1920
## Taille des dégradés de repli.
const GRADIENT_SIZE: Vector2 = Vector2(480, 270)
## Temps de stabilisation avant de changer le fond : en navigation rapide, on ne
## prépare que celui du jeu sur lequel on s'arrête.
const SETTLE_DELAY: float = 0.12
## Nombre de jeux dont les dégradés restent en mémoire.
const GRADIENT_CACHE_LIMIT: int = 16

@onready var _base: ColorRect = $Base
@onready var _vignette: TextureRect = $Vignette
@onready var _scrim: TextureRect = $Scrim

var _artworks: Dictionary = {}
var _loading: Dictionary = {}
var _gradients: Dictionary = {}
var _gradient_order: Array[String] = []

var _front: Control = null
var _back: Control = null
var _current_id: String = ""
var _pending: GameEntry = null
var _artwork_shown: bool = false
var _dimmed: bool = false
var _settle: Timer = null
var _tween: Tween = null

func _ready() -> void:
	_base.color = UITheme.COLOR_BACKGROUND
	_vignette.texture = UITheme.vignette_texture(GRADIENT_SIZE)
	_scrim.texture = UITheme.scrim_texture(GRADIENT_SIZE)
	_front = $LayerA
	_back = $LayerB
	_front.modulate.a = 0.0
	_back.modulate.a = 0.0

	_settle = Timer.new()
	_settle.one_shot = true
	_settle.wait_time = SETTLE_DELAY
	_settle.timeout.connect(_apply_pending)
	add_child(_settle)

	# Les fonds partagés sont préparés dès le lancement : le temps d'arriver au
	# premier changement de sélection, ils sont déjà prêts.
	for path: String in Wallpapers.available():
		_request_artwork(path)

## Affiche l'artwork d'un jeu. Sans effet si c'est déjà le jeu affiché.
func show_game(game: GameEntry) -> void:
	if game == null or game.id == _current_id:
		return
	_pending = game
	# Premier affichage : immédiat. Ensuite on attend que la sélection se pose.
	if _current_id.is_empty():
		_settle.stop()
		_apply_pending()
	else:
		_settle.start()

func _apply_pending() -> void:
	var game: GameEntry = _pending
	if game == null or game.id == _current_id:
		return

	var source: String = _source_for(game)
	if source.is_empty():
		_current_id = game.id
		_show_gradients(game)
		return

	if _artworks.has(source):
		_current_id = game.id
		_show_artwork(_artworks[source])
		return

	# L'image n'est pas encore prête : on garde le fond actuel plutôt que de
	# faire clignoter un dégradé, et on l'affichera dès que le chargement rend.
	_request_artwork(source)

func _source_for(game: GameEntry) -> String:
	if not game.background.is_empty():
		return game.background
	return Wallpapers.for_id(game.id)

## Décodage hors du fil principal ; seule la création de la texture, très brève,
## revient au fil principal.
func _request_artwork(path: String) -> void:
	if path.is_empty() or _artworks.has(path) or _loading.has(path):
		return
	_loading[path] = true
	WorkerThreadPool.add_task(_decode_artwork.bind(path))

func _decode_artwork(path: String) -> void:
	var image: Image = ImageLoader.load_image(path, ARTWORK_MAX_WIDTH)
	var luminance: float = ImageLoader.bottom_luminance(image)
	_on_artwork_decoded.call_deferred(path, image, luminance)

func _on_artwork_decoded(path: String, image: Image, luminance: float) -> void:
	_loading.erase(path)
	if image == null:
		return
	_artworks[path] = {
		"texture": ImageTexture.create_from_image(image),
		"luminance": luminance,
	}

	# Le jeu attendu peut avoir changé entre-temps : on n'affiche que s'il
	# correspond encore à la sélection en cours.
	var expected: GameEntry = _pending
	if expected != null and _source_for(expected) == path and expected.id != _current_id:
		_current_id = expected.id
		_show_artwork(_artworks[path])

func _show_artwork(entry: Dictionary) -> void:
	var swap: Control = _back
	(swap.get_node("Sky") as TextureRect).texture = entry["texture"]
	(swap.get_node("Glow") as TextureRect).visible = false
	(swap.get_node("Glow2") as TextureRect).visible = false
	_set_overlays(true, float(entry["luminance"]))
	_crossfade(swap)

func _show_gradients(game: GameEntry) -> void:
	var textures: Dictionary = _gradients_for(game.id)
	var swap: Control = _back
	(swap.get_node("Sky") as TextureRect).texture = textures["sky"]
	var glow: TextureRect = swap.get_node("Glow") as TextureRect
	var accent: TextureRect = swap.get_node("Glow2") as TextureRect
	glow.texture = textures["glow"]
	accent.texture = textures["accent"]
	glow.visible = true
	accent.visible = true
	_set_overlays(false, 0.0)
	_crossfade(swap)

func _crossfade(swap: Control) -> void:
	_back = _front
	_front = swap

	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_front, "modulate:a", 1.0, UITheme.ANIM_BACKDROP)
	_tween.tween_property(_back, "modulate:a", 0.0, UITheme.ANIM_BACKDROP)

## Certains écrans veulent un fond presque uni : la grille de la bibliothèque
## porte le regard, l'artwork y deviendrait du bruit.
func set_dimmed(dimmed: bool) -> void:
	if _dimmed == dimmed:
		return
	_dimmed = dimmed
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "modulate:a", UITheme.BACKDROP_DIMMED_ALPHA if dimmed else 1.0, UITheme.ANIM_BACKDROP)

## Le voile s'adapte à l'image : discret sur un artwork sombre, appuyé sur un
## artwork clair, pour que les jaquettes et les libellés restent lisibles.
func _set_overlays(has_artwork: bool, luminance: float) -> void:
	_artwork_shown = has_artwork
	if not has_artwork:
		_vignette.modulate.a = 1.0
		_scrim.modulate.a = 1.0
		return
	var clarity: float = clampf(luminance / UITheme.SCRIM_LUMINANCE_RANGE, 0.0, 1.0)
	_vignette.modulate.a = lerpf(UITheme.SCRIM_MIN, UITheme.SCRIM_MAX, clarity) * 0.6
	_scrim.modulate.a = lerpf(UITheme.SCRIM_MIN, UITheme.SCRIM_MAX, clarity)

## Les dégradés d'un jeu ne sont générés qu'une fois.
func _gradients_for(id: String) -> Dictionary:
	if _gradients.has(id):
		return _gradients[id]
	var entry: Dictionary = {
		"sky": UITheme.backdrop_texture(id, GRADIENT_SIZE),
		"glow": UITheme.glow_texture(id, GRADIENT_SIZE),
		"accent": UITheme.accent_glow_texture(id, GRADIENT_SIZE),
	}
	_gradients[id] = entry
	_gradient_order.append(id)
	while _gradient_order.size() > GRADIENT_CACHE_LIMIT:
		_gradients.erase(_gradient_order.pop_front())
	return entry
