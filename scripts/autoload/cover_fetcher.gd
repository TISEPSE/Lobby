extends Node

## Service automatique de récupération des jaquettes et fonds de jeux.
## Fonctionne SANS AUCUNE CLÉ API (zéro configuration, plug-and-play).
## 
## Sources exploitées automatiquement :
## 1. Cache local Steam (immédiat, hors-ligne)
## 2. Dossier local du jeu (cover.jpg, folder.jpg, boxart.jpg)
## 3. CDN public Steam (600x900 haute résolution, libre d'accès sans clé)
## 4. API de recherche publique du Steam Store (résolution par titre sans clé)
##
## Toutes les images téléchargées sont mises en cache dans `user://covers/`.

signal cover_downloaded(game: GameEntry)
signal fetch_queue_finished()

const COVERS_DIR: String = "user://covers"
const STEAM_CDN_COVER: String = "https://cdn.cloudflare.steamstatic.com/steam/apps/%s/library_600x900.jpg"
const STEAM_CDN_HEADER: String = "https://cdn.cloudflare.steamstatic.com/steam/apps/%s/header.jpg"
const STEAM_CDN_HERO: String = "https://cdn.cloudflare.steamstatic.com/steam/apps/%s/library_hero.jpg"
const STEAM_STORE_SEARCH: String = "https://store.steampowered.com/api/storesearch/?term=%s&l=french&cc=FR"

var _http: HTTPRequest = null
var _queue: Array[Dictionary] = []
var _current_task: Dictionary = {}
var _is_busy: bool = false
var _failed_ids: Dictionary = {}
var _active_fetch_ids: Dictionary = {}

func _ready() -> void:
	_ensure_covers_directory()
	_setup_http()
	GameLibrary.library_loaded.connect(_on_library_loaded)
	# Démarrage automatique en tâche de fond après stabilisation de l'interface
	call_deferred("_initial_check")

func _ensure_covers_directory() -> void:
	if not DirAccess.dir_exists_absolute(COVERS_DIR):
		DirAccess.make_dir_recursive_absolute(COVERS_DIR)

func _setup_http() -> void:
	_http = HTTPRequest.new()
	_http.name = "CoverHttp"
	_http.timeout = 7.0
	_http.use_threads = false
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

func _initial_check() -> void:
	await get_tree().create_timer(1.2).timeout
	fetch_all_missing()

func _on_library_loaded(_games: Array) -> void:
	fetch_all_missing()

## Vérifie tous les jeux et lance la récupération pour ceux qui n'ont pas de jaquette.
func fetch_all_missing() -> void:
	_ensure_covers_directory()
	for game: GameEntry in GameLibrary.games:
		fetch_for_game(game)

## Analyse un jeu spécifique : utilise le local s'il existe, sinon l'enfile pour téléchargement.
func fetch_for_game(game: GameEntry) -> void:
	if game == null:
		return

	# 1. Si la jaquette actuelle existe déjà sur le disque, rien à faire
	if not game.cover.is_empty() and FileAccess.file_exists(game.cover):
		return

	# 2. Vérifie si une jaquette a déjà été enregistrée dans user://covers/
	var cached_cover: String = COVERS_DIR.path_join("%s.jpg" % _sanitize_id(game.id))
	if FileAccess.file_exists(cached_cover):
		game.cover = cached_cover
		var cached_hero: String = COVERS_DIR.path_join("%s_hero.jpg" % _sanitize_id(game.id))
		if game.background.is_empty() and FileAccess.file_exists(cached_hero):
			game.background = cached_hero
		GameLibrary.save_library()
		GameLibrary.game_updated.emit(game)
		return

	# 3. Vérifie le cache local Steam pour les jeux Steam installés
	if game.id.begins_with("steam-"):
		var appid: String = game.id.substr(6)
		var steam_root: String = GameFinder.steam_root()
		if not steam_root.is_empty():
			var art: Dictionary = GameFinder.steam_artwork(steam_root, appid)
			var found_any: bool = false
			if not str(art.get("cover", "")).is_empty():
				game.cover = str(art["cover"])
				found_any = true
			if not str(art.get("background", "")).is_empty() and game.background.is_empty():
				game.background = str(art["background"])
				found_any = true
			if found_any:
				GameLibrary.save_library()
				GameLibrary.game_updated.emit(game)
				return

	# 4. Vérifie dans le dossier de l'exécutable
	if not game.executable.is_empty() and game.executable != "{demo}":
		var local_cover: String = GameFinder.find_local_cover(game.executable.get_base_dir())
		if not local_cover.is_empty():
			game.cover = local_cover
			GameLibrary.save_library()
			GameLibrary.game_updated.emit(game)
			return

	# 5. Pas de jaquette locale : on l'enfile pour téléchargement en tâche de fond
	if _failed_ids.has(game.id) or _active_fetch_ids.has(game.id):
		return

	_active_fetch_ids[game.id] = true
	if game.id.begins_with("steam-"):
		var appid: String = game.id.substr(6)
		_enqueue({
			"game": game,
			"stage": "steam_cdn_cover",
			"appid": appid,
		})
	else:
		var search_term: String = _clean_title(game.title)
		if search_term.is_empty():
			_active_fetch_ids.erase(game.id)
			return
		_enqueue({
			"game": game,
			"stage": "steam_store_search",
			"term": search_term,
		})

func _enqueue(task: Dictionary) -> void:
	_queue.append(task)
	if not _is_busy:
		_process_next()

func _process_next() -> void:
	if _queue.is_empty():
		_is_busy = false
		_current_task = {}
		fetch_queue_finished.emit()
		return

	_is_busy = true
	_current_task = _queue.pop_front()
	var stage: String = str(_current_task.get("stage", ""))

	match stage:
		"steam_cdn_cover":
			var appid: String = str(_current_task.get("appid", ""))
			var url: String = STEAM_CDN_COVER % appid
			var err: Error = _http.request(url)
			if err != OK:
				_on_task_failed()

		"steam_cdn_header":
			var appid: String = str(_current_task.get("appid", ""))
			var url: String = STEAM_CDN_HEADER % appid
			var err: Error = _http.request(url)
			if err != OK:
				_on_task_failed()

		"steam_cdn_hero":
			var appid: String = str(_current_task.get("appid", ""))
			var url: String = STEAM_CDN_HERO % appid
			var err: Error = _http.request(url)
			if err != OK:
				_advance()

		"steam_store_search":
			var term: String = str(_current_task.get("term", ""))
			var url: String = STEAM_STORE_SEARCH % term.uri_encode()
			var err: Error = _http.request(url)
			if err != OK:
				_on_task_failed()

func _on_request_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _current_task.is_empty():
		_advance()
		return

	var stage: String = str(_current_task.get("stage", ""))
	var game: GameEntry = _current_task.get("game")

	if game == null:
		_advance()
		return

	match stage:
		"steam_cdn_cover":
			if response_code == 200 and body.size() > 1000:
				var path: String = COVERS_DIR.path_join("%s.jpg" % _sanitize_id(game.id))
				if _save_file(path, body):
					game.cover = path
					ImageLoader.invalidate(path)
					GameLibrary.save_library()
					GameLibrary.game_updated.emit(game)
					cover_downloaded.emit(game)
					# Télécharger aussi le fond hero si le jeu n'en a pas
					if game.background.is_empty():
						var appid: String = str(_current_task.get("appid", ""))
						_queue.push_front({
							"game": game,
							"stage": "steam_cdn_hero",
							"appid": appid,
						})
				_advance()
			else:
				# Repli sur le header Steam (format paysage mais officiel)
				_queue.push_front({
					"game": game,
					"stage": "steam_cdn_header",
					"appid": str(_current_task.get("appid", "")),
				})
				_advance()

		"steam_cdn_header":
			if response_code == 200 and body.size() > 1000:
				var path: String = COVERS_DIR.path_join("%s.jpg" % _sanitize_id(game.id))
				if _save_file(path, body):
					game.cover = path
					ImageLoader.invalidate(path)
					GameLibrary.save_library()
					GameLibrary.game_updated.emit(game)
					cover_downloaded.emit(game)
				_advance()
			else:
				_on_task_failed()

		"steam_cdn_hero":
			if response_code == 200 and body.size() > 2000:
				var hero_path: String = COVERS_DIR.path_join("%s_hero.jpg" % _sanitize_id(game.id))
				if _save_file(hero_path, body):
					game.background = hero_path
					GameLibrary.save_library()
					GameLibrary.game_updated.emit(game)
			_advance()

		"steam_store_search":
			if response_code == 200:
				var json: Variant = JSON.parse_string(body.get_string_from_utf8())
				if json is Dictionary and json.has("items") and json["items"].size() > 0:
					var first_item: Dictionary = json["items"][0]
					var found_appid: String = str(int(first_item.get("id", 0)))
					if not found_appid.is_empty() and found_appid != "0":
						# Jeu trouvé sur Steam : on enchaîne avec le téléchargement de sa jaquette 600x900
						_queue.push_front({
							"game": game,
							"stage": "steam_cdn_cover",
							"appid": found_appid,
						})
						_advance()
						return
			_on_task_failed()

func _on_task_failed() -> void:
	var game: GameEntry = _current_task.get("game")
	if game != null:
		_failed_ids[game.id] = true
		_active_fetch_ids.erase(game.id)
	_advance()

func _advance() -> void:
	# Petite pause de 120 ms entre chaque requête pour éviter tout blocage réseau
	await get_tree().create_timer(0.12).timeout
	_process_next()

func _save_file(path: String, data: PackedByteArray) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(data)
	file.close()
	return true

func _sanitize_id(raw_id: String) -> String:
	var clean: String = ""
	for c: String in raw_id.to_lower():
		if c.is_valid_identifier() or c == "-" or c == "_":
			clean += c
		else:
			clean += "_"
	return clean

func _clean_title(title: String) -> String:
	var text: String = title
	# Supprime l'extension .exe si présente
	if text.to_lower().ends_with(".exe"):
		text = text.substr(0, text.length() - 4)
	# Supprime ce qui est entre parenthèses ou crochets (ex: "(v1.0)", "[FitGirl]", etc.)
	var regex := RegEx.new()
	if regex.compile(r"(\[[^\]]*\]|\([^\)]*\))") == OK:
		text = regex.sub(text, " ", true)
	text = text.replace("_", " ").replace(".", " ").strip_edges()
	return text
