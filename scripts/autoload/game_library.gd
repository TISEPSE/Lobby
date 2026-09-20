extends Node

## Autoload : charge et conserve la bibliothèque de jeux.
## Source : user://games.json, amorcé depuis res://data/games_sample.json au premier lancement.

signal library_loaded(games: Array)
signal game_updated(game: GameEntry)

const SAMPLE_PATH: String = "res://data/games_sample.json"
const USER_PATH: String = "user://games.json"

var games: Array[GameEntry] = []

## Version des données d'exemple ayant servi d'amorce : réécrite telle quelle
## dans user://games.json, sinon la bibliothèque se ré-amorcerait à chaque lancement.
var _data_version: int = 1

func _ready() -> void:
	load_library()

func load_library() -> void:
	var sample: Dictionary = _read_json(SAMPLE_PATH)
	_data_version = int(sample.get("version", 1))
	var path: String = SAMPLE_PATH
	var raw: Dictionary = sample

	if FileAccess.file_exists(USER_PATH):
		var user_data: Dictionary = _read_json(USER_PATH)
		if user_data.is_empty():
			push_warning("games.json illisible, retour sur les données d'exemple.")
		elif int(user_data.get("version", 0)) < _data_version:
			# Les données d'exemple ont évolué pendant le développement : on repart d'elles.
			push_warning("Données d'exemple plus récentes, bibliothèque ré-amorcée.")
		else:
			path = USER_PATH
			raw = user_data

	games.clear()
	for item: Variant in raw.get("games", []):
		if item is Dictionary:
			games.append(GameEntry.from_dict(item))

	if path == SAMPLE_PATH:
		save_library()
	library_loaded.emit(games)

func save_library() -> void:
	var payload: Dictionary = {"version": _data_version, "games": []}
	for game: GameEntry in games:
		payload["games"].append(game.to_dict())
	var file := FileAccess.open(USER_PATH, FileAccess.WRITE)
	if file == null:
		push_error("Écriture impossible dans %s (%s)" % [USER_PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

## Intègre le résultat d'un scan sans rien perdre : un jeu déjà connu ne voit
## que son chemin et son titre rafraîchis, ses favoris et son temps de jeu
## restent intacts. Retourne le nombre de jeux nouvellement ajoutés.
func merge_scanned(scanned: Array[GameEntry]) -> int:
	var added: int = 0
	for found: GameEntry in scanned:
		var existing: GameEntry = get_game(found.id)
		if existing == null:
			games.append(found)
			added += 1
			continue
		existing.executable = found.executable
		existing.title = found.title
		existing.source = "scan"
		if existing.cover.is_empty() and not found.cover.is_empty():
			existing.cover = found.cover
		if existing.background.is_empty() and not found.background.is_empty():
			existing.background = found.background
	save_library()
	library_loaded.emit(games)
	return added

## Retire les jeux de démonstration. Sans effet sur les jeux trouvés sur le disque.
func remove_samples() -> int:
	var kept: Array[GameEntry] = []
	for game: GameEntry in games:
		if game.source != "sample":
			kept.append(game)
	var removed: int = games.size() - kept.size()
	if removed > 0:
		games = kept
		save_library()
		library_loaded.emit(games)
	return removed

func get_game(id: String) -> GameEntry:
	for game: GameEntry in games:
		if game.id == id:
			return game
	return null

## Enregistre une session de jeu terminée : temps cumulé et date de dernière partie.
func record_session(id: String, minutes: int) -> void:
	var game: GameEntry = get_game(id)
	if game == null:
		return
	game.playtime_minutes += maxi(minutes, 0)
	game.last_played = Time.get_datetime_string_from_system(true)
	save_library()
	game_updated.emit(game)

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Fichier introuvable : %s" % path)
		return {}
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	push_error("JSON invalide dans %s" % path)
	return {}
