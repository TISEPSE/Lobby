extends Node

## Récupère la **fiche** d'un jeu — note, genres, date de sortie et résumé —
## **sans aucune clé d'API** : tout vient des points d'entrée publics de Steam.
## L'utilisateur n'a rien à configurer.
##
## - Un jeu détecté via Steam porte déjà son identifiant (`steam-753640`).
## - Pour les autres, le titre est cherché dans le catalogue Steam.
## - Les **visuels** ne sont pas de son ressort : `CoverFetcher` (autoload) s'en
##   charge déjà. Deux services, deux responsabilités, pas de doublon.

signal progress(done: int, total: int, title: String)
signal finished(updated: int, missed: int)

const SEARCH_URL: String = "https://steamcommunity.com/actions/SearchApps/%s"
const DETAILS_URL: String = "https://store.steampowered.com/api/appdetails?appids=%s&l=french"
## Ce qui a déjà été cherché, pour ne pas réinterroger Steam à chaque lancement.
const CACHE_PATH: String = "user://metadata_cache.json"

## Steam répond mal si on l'inonde : une courte pause entre deux jeux.
const PAUSE_BETWEEN_GAMES: float = 0.25
const REQUEST_TIMEOUT: float = 15.0

var is_running: bool = false

var _http: HTTPRequest = null
## Associations titre ou identifiant -> appid Steam, gardées d'une fois sur l'autre.
var _cache: Dictionary = {}

func _ready() -> void:
	_ensure_http()
	_load_cache()

## Le nœud de requête est créé à la demande : l'outil de test appelle le
## composant avant que `_ready` n'ait tourné.
func _ensure_http() -> void:
	if _http != null and is_instance_valid(_http):
		return
	_http = HTTPRequest.new()
	_http.timeout = REQUEST_TIMEOUT
	# Une jaquette 600x900 dépasse le tampon par défaut.
	_http.download_chunk_size = 65536
	add_child(_http)

## Complète les jeux passés en paramètre. Le composant ne connaît pas la
## bibliothèque : l'écran qui l'appelle lui donne la liste et enregistre ensuite.
## Un jeu qui a déjà jaquette et note n'est pas réinterrogé.
func fetch_for(games: Array[GameEntry]) -> void:
	if is_running:
		return
	var pending: Array[GameEntry] = []
	for game: GameEntry in games:
		if _needs_metadata(game):
			pending.append(game)
	if pending.is_empty():
		finished.emit(0, 0)
		return

	is_running = true

	var updated: int = 0
	var missed: int = 0
	for i: int in pending.size():
		var game: GameEntry = pending[i]
		progress.emit(i, pending.size(), game.title)
		if await _complete(game):
			updated += 1
		else:
			missed += 1
		await get_tree().create_timer(PAUSE_BETWEEN_GAMES).timeout

	_save_cache()
	is_running = false
	finished.emit(updated, missed)

## Un jeu est complet quand il a sa note et son résumé. Les jeux d'exemple
## gardent les leurs : ils servent justement à montrer une fiche remplie.
func _needs_metadata(game: GameEntry) -> bool:
	if game.source == "sample":
		return false
	return game.rating <= 0.0 or game.synopsis.is_empty()

## Remplit un jeu. Retourne false si Steam ne connaît pas ce titre.
func _complete(game: GameEntry) -> bool:
	var appid: String = await _resolve_appid(game)
	if appid.is_empty():
		return false

	var details: Dictionary = await _fetch_details(appid)
	if details.is_empty():
		return false

	if game.synopsis.is_empty():
		game.synopsis = _clean_html(str(details.get("short_description", "")))
	if game.genre.is_empty():
		var genres: PackedStringArray = PackedStringArray()
		for genre: Variant in details.get("genres", []):
			genres.append(str((genre as Dictionary).get("description", "")))
		game.genre = ", ".join(genres)
	if game.release_date.is_empty():
		var release: Dictionary = details.get("release_date", {})
		game.release_date = str(release.get("date", ""))
	if game.rating <= 0.0:
		# Metacritic note sur 100, la bibliothèque sur 5.
		var metacritic: Dictionary = details.get("metacritic", {})
		var score: float = float(metacritic.get("score", 0))
		if score > 0.0:
			game.rating = snappedf(score / 20.0, 0.1)

	return true

## Identifiant Steam du jeu : lu sur son identifiant quand il vient de Steam,
## cherché par son titre sinon.
func _resolve_appid(game: GameEntry) -> String:
	if game.id.begins_with("steam-"):
		return game.id.trim_prefix("steam-")
	var key: String = _cache_key(game.title)
	if _cache.has(key):
		return str(_cache[key])

	var body: String = await _request(SEARCH_URL % _encode(game.title))
	var parsed: Variant = JSON.parse_string(body)
	var appid: String = ""
	if parsed is Array and (parsed as Array).size() > 0:
		# Deux passes : le titre identique d'abord, la ressemblance ensuite.
		# Sans ça, « Hollow Knight » tombait sur « Hollow Knight: Silksong ».
		var wanted: String = _normalize(game.title)
		for result: Variant in parsed:
			var entry: Dictionary = result
			if _normalize(str(entry.get("name", ""))) == wanted:
				appid = str(entry.get("appid", ""))
				break
		if appid.is_empty():
			for result: Variant in parsed:
				var entry: Dictionary = result
				if _titles_match(game.title, str(entry.get("name", ""))):
					appid = str(entry.get("appid", ""))
					break
	_cache[key] = appid
	return appid

func _fetch_details(appid: String) -> Dictionary:
	var body: String = await _request(DETAILS_URL % appid)
	var parsed: Variant = JSON.parse_string(body)
	if not parsed is Dictionary:
		return {}
	var wrapper: Dictionary = (parsed as Dictionary).get(appid, {})
	if not bool(wrapper.get("success", false)):
		return {}
	return wrapper.get("data", {})

func _request(url: String) -> String:
	return (await _request_bytes(url)).get_string_from_utf8()

## Une requête à la fois : le nœud HTTPRequest n'en supporte pas davantage.
## On n'annule pas la précédente — elle est terminée — car un `cancel_request()`
## juste avant un `request()` faisait échouer la requête suivante en silence,
## et le fond d'écran ne se téléchargeait jamais.
func _request_bytes(url: String) -> PackedByteArray:
	_ensure_http()
	var error: int = _http.request(url)
	if error == ERR_BUSY:
		await get_tree().process_frame
		error = _http.request(url)
	if error != OK:
		push_warning("Requête impossible (%s) : %s" % [error_string(error), url])
		return PackedByteArray()
	var result: Array = await _http.request_completed
	# result = [result, response_code, headers, body]
	if int(result[1]) != 200:
		return PackedByteArray()
	return result[3]

## Les résumés de Steam contiennent des balises : l'interface affiche du texte.
func _clean_html(value: String) -> String:
	var text: String = value.replace("<br>", "\n").replace("<br/>", "\n").replace("<br />", "\n")
	var regex := RegEx.new()
	regex.compile("<[^>]+>")
	text = regex.sub(text, "", true)
	return text.replace("&quot;", "\"").replace("&amp;", "&").replace("&nbsp;", " ").strip_edges()

## Comparaison tolérante : « Marvel's Spider-Man 2 » et « Spider-Man2 » doivent
## se reconnaître, mais « Spider-Man 2 » ne doit pas attraper « Spider-Man ».
func _titles_match(wanted: String, candidate: String) -> bool:
	var left: String = _normalize(wanted)
	var right: String = _normalize(candidate)
	if left.is_empty() or right.is_empty():
		return false
	return left == right or left.contains(right) or right.contains(left)

static func _normalize(value: String) -> String:
	var result: String = ""
	for character: String in value.to_lower():
		if character.is_valid_identifier() or character.is_valid_int():
			result += character
	return result

static func _cache_key(title: String) -> String:
	return "title:%s" % _normalize(title)

static func _encode(value: String) -> String:
	return value.uri_encode()

func _load_cache() -> void:
	if not FileAccess.file_exists(CACHE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE_PATH))
	if parsed is Dictionary:
		_cache = parsed

func _save_cache() -> void:
	var file: FileAccess = FileAccess.open(CACHE_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(_cache, "\t"))
	file.close()
