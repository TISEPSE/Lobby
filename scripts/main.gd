extends Control

## Racine de l'interface : fond, écran courant et porte de sortie.

const HOME_SCENE: PackedScene = preload("res://scenes/screens/home.tscn")
const LIBRARY_SCENE: PackedScene = preload("res://scenes/screens/library.tscn")
const DETAIL_SCENE: PackedScene = preload("res://scenes/screens/game_detail.tscn")
const SETTINGS_SCENE: PackedScene = preload("res://scenes/screens/settings.tscn")

@onready var _backdrop: Control = $Backdrop
@onready var _screen_host: Control = $ScreenHost
@onready var _boot_video: Control = $BootVideo

## Pile d'écrans : l'écran quitté est mis en sommeil, pas détruit, pour
## retrouver sa sélection au retour.
var _stack: Array[Control] = []
var _suspended_focus: Dictionary = {}

func _ready() -> void:
	show_home()
	_play_boot_video()
	Launcher.game_started.connect(_on_game_started)
	Launcher.game_exited.connect(_on_game_exited)
	_maybe_capture()

## Introduction au démarrage : l'accueil est déjà construit derrière, la vidéo
## le recouvre. Si elle est absente ou illisible, on ne montre rien du tout.
func _play_boot_video() -> void:
	if not Settings.has_boot_video():
		return
	_boot_video.finished.connect(_on_boot_video_finished)
	if not _boot_video.play(Settings.boot_video_path):
		_boot_video.finished.disconnect(_on_boot_video_finished)

func _on_boot_video_finished() -> void:
	# Le focus a pu être capté par la vidéo : on le rend à l'écran courant.
	if not _stack.is_empty() and _stack.back().has_method("on_resumed"):
		_stack.back().on_resumed()

func show_home() -> void:
	var screen: Control = _push(HOME_SCENE)
	screen.shortcut_activated.connect(_on_shortcut_activated)
	screen.game_opened.connect(show_detail)

func show_library(filter_id: String = "all") -> void:
	var screen: Control = _push(LIBRARY_SCENE, false)
	screen.setup(filter_id)
	screen.back_requested.connect(_pop)
	screen.game_opened.connect(show_detail)

func show_settings() -> void:
	var screen: Control = _push(SETTINGS_SCENE, false)
	screen.back_requested.connect(_pop)

func show_detail(game: GameEntry, source: Rect2 = Rect2(), texture: Texture2D = null) -> void:
	var screen: Control = _push(DETAIL_SCENE, false)
	screen.setup(game)
	screen.back_requested.connect(_pop)
	# L'écran précédent s'efface pendant que la jaquette rejoint sa place, et
	# revient dès le début de l'animation de retour.
	screen.closing.connect(_reveal_previous)
	screen.play_open_transition(source, texture)

## Empile un écran. L'écran précédent est masqué et cesse de recevoir les
## entrées, sinon deux écrans réagiraient à la même touche.
func _push(scene: PackedScene, replace_root: bool = true) -> Control:
	if replace_root:
		for screen: Control in _stack:
			screen.queue_free()
		_stack.clear()
	elif not _stack.is_empty():
		_suspend(_stack.back())
		_fade(_stack.back(), 0.0)

	var screen: Control = scene.instantiate()
	screen.selection_changed.connect(_backdrop.show_game)
	_screen_host.add_child(screen)
	_stack.append(screen)
	_apply_backdrop_mode(screen)
	return screen

## Dépile : on revient à l'écran précédent, là où la sélection était restée.
func _pop() -> void:
	if _stack.size() <= 1:
		return
	var leaving: Control = _stack.pop_back()
	leaving.queue_free()
	_resume(_stack.back())
	_apply_backdrop_mode(_stack.back())

func _suspend(screen: Control) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and screen.is_ancestor_of(focused):
		_suspended_focus[screen.get_instance_id()] = focused
	# Masqué seulement une fois le fondu terminé : ses enfants restent visibles
	# le temps de la transition, mais ne répondent plus aux touches.
	screen.set_process_unhandled_input(false)

func _resume(screen: Control) -> void:
	screen.visible = true
	screen.set_process_unhandled_input(true)
	_fade(screen, 1.0)
	if screen.has_method("on_resumed"):
		screen.on_resumed()
	var key: int = screen.get_instance_id()
	var focused: Control = _suspended_focus.get(key)
	if focused != null and is_instance_valid(focused):
		focused.grab_focus()
	_suspended_focus.erase(key)

## Chaque écran décide si le fond doit s'effacer derrière lui.
func _apply_backdrop_mode(screen: Control) -> void:
	var dim: bool = screen.get("dim_backdrop") == true
	_backdrop.set_dimmed(dim)

## Ramène l'écran sous le sommet de la pile pendant une animation de retour.
func _reveal_previous() -> void:
	if _stack.size() < 2:
		return
	var below: Control = _stack[_stack.size() - 2]
	below.visible = true
	_fade(below, 1.0)
	_apply_backdrop_mode(below)

func _fade(screen: Control, target: float) -> void:
	var tween: Tween = screen.create_tween()
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(screen, "modulate:a", target, UITheme.ANIM_SCREEN_FADE)
	if is_equal_approx(target, 0.0):
		tween.tween_callback(func() -> void: screen.visible = false)

func _on_shortcut_activated(action: String) -> void:
	# « Parcourir les jeux », « Favoris » et « Récemment joué » ouvrent le même
	# écran, sur des filtres différents.
	match action:
		"library":
			show_library()
		"favorites":
			show_library("favorites")
		"recent":
			show_library("recent")
		"settings":
			show_settings()

func _unhandled_input(event: InputEvent) -> void:
	# Porte de sortie pour les tests : Ctrl+Alt+Q quitte l'interface.
	if event.is_action_pressed("ui_quit_shell"):
		get_viewport().set_input_as_handled()
		get_tree().quit()

## Pendant le jeu : son coupé et animations suspendues.
func _on_game_started(_game: GameEntry) -> void:
	AudioServer.set_bus_mute(0, true)

func _on_game_exited(_game: GameEntry, _minutes: int) -> void:
	AudioServer.set_bus_mute(0, false)

## Outil de développement : `godot --path . -- --capture sortie.png`
## enregistre une capture de l'interface puis quitte. Sans l'argument, ne fait rien.
## `--focus N` sélectionne la Nième tuile, `--screen library` ouvre la grille,
## `--detail N` ouvre la fiche du Nième jeu, `--power` la fenêtre d'alimentation,
## `--category profile|boot|games|system`, `--avatars`, `--videos`, `--detect` et `--metadata` ciblent l'écran de
## réglages, `--accept` simule une validation, `--delay N` attend N secondes.
func _maybe_capture() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find("--capture")
	if index == -1 or index + 1 >= args.size():
		return
	var path: String = args[index + 1]
	_boot_video.skip()

	# Ordre fixe : on ouvre l'écran, on y place le focus, puis seulement on
	# ouvre une fenêtre modale — sinon elle s'ouvrirait depuis la mauvaise ligne.
	var screen_index: int = args.find("--screen")
	if screen_index != -1 and screen_index + 1 < args.size():
		match args[screen_index + 1]:
			"library":
				show_library()
			"settings":
				show_settings()
				var cat_index: int = args.find("--category")
				if cat_index != -1 and cat_index + 1 < args.size():
					_stack.back().select_category(args[cat_index + 1])

	var detail_index: int = args.find("--detail")
	if detail_index != -1 and detail_index + 1 < args.size():
		var i: int = int(args[detail_index + 1])
		if i >= 0 and i < GameLibrary.games.size():
			show_detail(GameLibrary.games[i])

	var focus_index: int = args.find("--focus")
	if focus_index != -1 and focus_index + 1 < args.size():
		_focus_nth_tile(int(args[focus_index + 1]))

	if not _stack.is_empty():
		var screen: Control = _stack.back()
		if args.has("--browse") and screen.has_method("open_browser"):
			screen.open_browser()
		if args.has("--keyboard") and screen.has_method("open_keyboard"):
			screen.open_keyboard()
		if args.has("--avatars") and screen.has_method("open_avatars"):
			screen.open_avatars()
		if args.has("--videos") and screen.has_method("open_videos"):
			screen.open_videos()
		if args.has("--detect") and screen.has_method("open_detect"):
			screen.open_detect()
		if args.has("--metadata") and screen.has_method("open_metadata"):
			screen.open_metadata()
		if args.has("--sidebar") and screen.has_method("open_sidebar"):
			screen.open_sidebar()
		if args.has("--power") and screen.has_method("open_power_menu"):
			screen.open_power_menu()

	# `--accept` simule une validation avant la capture : de quoi vérifier ce
	# qu'un écran devient après un A, sans manette branchée.
	if args.has("--accept"):
		await get_tree().create_timer(0.6).timeout
		var press := InputEventAction.new()
		press.action = "ui_accept"
		press.pressed = true
		Input.parse_input_event(press)
		var release := InputEventAction.new()
		release.action = "ui_accept"
		release.pressed = false
		Input.parse_input_event(release)

	var delay: float = 1.0
	var delay_index: int = args.find("--delay")
	if delay_index != -1 and delay_index + 1 < args.size():
		delay = float(args[delay_index + 1])
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var error: int = image.save_png(path)
	if error != OK:
		push_error("Capture impossible : %s" % error_string(error))
	get_tree().quit()

## Donne le focus à la Nième tuile focalisable, pour capturer un autre état de l'écran.
func _focus_nth_tile(index: int) -> void:
	var buttons: Array[Node] = []
	for node: Node in _screen_host.find_children("*", "Button", true, false):
		if node.focus_mode != Control.FOCUS_NONE:
			buttons.append(node)
	if index >= 0 and index < buttons.size():
		(buttons[index] as Control).grab_focus()
