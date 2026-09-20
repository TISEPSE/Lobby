extends Node

## Autoload : lance un jeu via OS.create_process et surveille sa fermeture.

signal game_started(game: GameEntry)
signal game_exited(game: GameEntry, minutes: int)
signal launch_failed(game: GameEntry, reason: String)

## Marqueur utilisé par les données d'exemple : remplacé par un exécutable de test
## présent sur la machine, le temps de l'étape 1 (aucun vrai jeu installé).
const DEMO_MARKER: String = "{demo}"
const POLL_INTERVAL: float = 1.0

var current_game: GameEntry = null

var _pid: int = -1
var _started_at: int = 0
var _timer: Timer = null

func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = POLL_INTERVAL
	_timer.timeout.connect(_poll_process)
	add_child(_timer)

func is_running() -> bool:
	return _pid != -1

## Lance le jeu. Retourne false si le processus n'a pas pu démarrer.
func launch(game: GameEntry) -> bool:
	if game == null:
		return false
	if is_running():
		launch_failed.emit(game, "Un jeu est déjà en cours.")
		return false

	var path: String = game.executable
	var args: PackedStringArray = game.args
	if path == DEMO_MARKER:
		var demo: Dictionary = _demo_target()
		path = demo["path"]
		args = demo["args"]

	if path.is_empty():
		launch_failed.emit(game, "Aucun exécutable défini.")
		return false

	var pid: int = OS.create_process(path, args)
	if pid <= 0:
		launch_failed.emit(game, "Lancement impossible : %s" % path)
		return false

	_pid = pid
	current_game = game
	_started_at = Time.get_ticks_msec()
	_timer.start()
	game_started.emit(game)
	return true

## Vrai quand le jeu n'a pas de vrai exécutable et passe par la démo.
func is_demo(game: GameEntry) -> bool:
	return game != null and game.executable == DEMO_MARKER

## Message affiché pendant le lancement, explicite pour les données d'exemple.
func launch_notice(game: GameEntry) -> String:
	if not is_demo(game):
		return "Lancement de %s…" % game.title
	var demo_name: String = _demo_target()["path"].get_file()
	return "%s n'a pas d'exécutable : démo avec %s.
Ferme cette fenêtre pour revenir à l'interface." % [game.title, demo_name]

func _poll_process() -> void:
	if not is_running():
		_timer.stop()
		return
	if OS.is_process_running(_pid):
		return
	_finish_session()

func _finish_session() -> void:
	var game: GameEntry = current_game
	var minutes: int = int(float(Time.get_ticks_msec() - _started_at) / 60000.0)
	_timer.stop()
	_pid = -1
	current_game = null
	_started_at = 0
	if game != null:
		GameLibrary.record_session(game.id, minutes)
		game_exited.emit(game, minutes)

## Exécutable de test selon la plateforme, pour valider le cycle lancement/fermeture.
func _demo_target() -> Dictionary:
	if OS.get_name() == "Windows":
		return {"path": "notepad.exe", "args": PackedStringArray()}
	if OS.get_name() == "macOS":
		return {"path": "/bin/sleep", "args": PackedStringArray(["20"])}
	return {"path": "/usr/bin/sleep", "args": PackedStringArray(["20"])}
