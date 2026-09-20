class_name GameScanner
extends RefCounted

## Parcourt les dossiers de jeux et en tire des entrées de bibliothèque.
## Convention attendue : un sous-dossier par jeu. Un exécutable posé directement
## dans le dossier suivi est également reconnu.

## Profondeur de recherche sous un dossier de jeu. Au-delà, on tombe dans les
## dossiers de ressources, qui contiennent souvent des outils annexes.
const MAX_DEPTH: int = 3

## Extensions considérées comme lançables, par plateforme.
const WINDOWS_EXTENSIONS: PackedStringArray = ["exe"]
const LINUX_EXTENSIONS: PackedStringArray = ["x86_64", "x86", "sh", "AppImage"]

## Fragments de noms à écarter : désinstalleurs, dépendances redistribuables et
## outils de rapport d'erreur portent des noms trop reconnaissables pour être
## confondus avec le jeu lui-même.
const REJECTED: PackedStringArray = [
	"unins", "uninstall", "setup", "install", "redist", "vcredist", "directx",
	"dxsetup", "dotnet", "crashreport", "crashhandler", "crashpad", "report",
	"config", "settings", "editor", "server", "benchmark", "touchup", "helper",
]

## Scanne tous les dossiers suivis. Les jeux sont triés par titre.
static func scan(folders: PackedStringArray) -> Array[GameEntry]:
	var games: Array[GameEntry] = []
	var seen: Dictionary = {}
	for folder: String in folders:
		for game: GameEntry in _scan_folder(folder):
			if seen.has(game.id):
				continue
			seen[game.id] = true
			games.append(game)
	games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
		return a.title.naturalnocasecmp_to(b.title) < 0
	)
	return games

static func _scan_folder(folder: String) -> Array[GameEntry]:
	var games: Array[GameEntry] = []
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		push_warning("Dossier de jeux introuvable : %s" % folder)
		return games

	# Un exécutable directement dans le dossier suivi compte pour un jeu.
	for file_name: String in _list(dir, false):
		if _is_executable(file_name) and _is_plausible(file_name):
			games.append(_make_entry(folder.path_join(file_name), file_name.get_basename()))

	# Sinon, chaque sous-dossier est un jeu dont on cherche l'exécutable principal.
	for sub_name: String in _list(dir, true):
		var sub_path: String = folder.path_join(sub_name)
		var executable: String = _find_executable(sub_path, sub_name, 0)
		if not executable.is_empty():
			games.append(_make_entry(executable, sub_name))
	return games

## Cherche l'exécutable le plus plausible sous un dossier de jeu : d'abord celui
## dont le nom ressemble à celui du dossier, sinon le premier candidat crédible.
static func _find_executable(path: String, game_name: String, depth: int) -> String:
	if depth > MAX_DEPTH:
		return ""
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return ""

	var fallback: String = ""
	for file_name: String in _list(dir, false):
		if not _is_executable(file_name) or not _is_plausible(file_name):
			continue
		var candidate: String = path.path_join(file_name)
		if _matches(file_name.get_basename(), game_name):
			return candidate
		if fallback.is_empty():
			fallback = candidate

	for sub_name: String in _list(dir, true):
		var found: String = _find_executable(path.path_join(sub_name), game_name, depth + 1)
		if not found.is_empty():
			if _matches(found.get_file().get_basename(), game_name):
				return found
			if fallback.is_empty():
				fallback = found
	return fallback

static func _list(dir: DirAccess, want_directories: bool) -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray()
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not entry.begins_with("."):
			if dir.current_is_dir() == want_directories:
				names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	names.sort()
	return names

static func _is_executable(file_name: String) -> bool:
	var extensions: PackedStringArray = WINDOWS_EXTENSIONS if OS.get_name() == "Windows" else LINUX_EXTENSIONS
	var extension: String = file_name.get_extension()
	if extension.is_empty():
		# Sous Linux, un binaire n'a souvent pas d'extension.
		return OS.get_name() != "Windows"
	for allowed: String in extensions:
		if extension.nocasecmp_to(allowed) == 0:
			return true
	return false

static func _is_plausible(file_name: String) -> bool:
	var lowered: String = file_name.to_lower()
	for fragment: String in REJECTED:
		if lowered.contains(fragment):
			return false
	return true

## Deux noms se ressemblent quand l'un contient l'autre, une fois débarrassés de
## la ponctuation : « Hollow Knight » et « hollow_knight.exe », par exemple.
static func _matches(a: String, b: String) -> bool:
	var left: String = _normalize(a)
	var right: String = _normalize(b)
	if left.is_empty() or right.is_empty():
		return false
	return left.contains(right) or right.contains(left)

static func _normalize(value: String) -> String:
	var result: String = ""
	for character: String in value.to_lower():
		if character.is_valid_identifier() or character.is_valid_int():
			result += character
	return result

static func _make_entry(executable: String, title: String) -> GameEntry:
	var game := GameEntry.new()
	game.id = "scan-%s" % str(executable.to_lower().hash())
	game.title = title.replace("_", " ").replace(".", " ").strip_edges()
	game.executable = executable
	game.source = "scan"
	var exec_dir: String = executable.get_base_dir()
	var cover: String = GameFinder.find_local_cover(exec_dir)
	if cover.is_empty():
		cover = GameFinder.find_local_cover(exec_dir.get_base_dir())
	game.cover = cover
	return game
