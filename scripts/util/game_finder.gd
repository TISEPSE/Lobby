class_name GameFinder
extends RefCounted

## Trouve les jeux installés sans rien demander à l'utilisateur, en interrogeant
## les sources qui savent déjà ce qui est installé : Steam, Epic, puis les
## raccourcis du Bureau et du menu Démarrer (les fichiers `.desktop` sous Linux).
##
## Parcourir tout le disque donnerait surtout des faux positifs : ici chaque
## entrée vient d'un endroit où seul un logiciel installé peut se trouver, et
## tout candidat dont l'exécutable a disparu est écarté.

## Profondeur de recherche des raccourcis sous le menu Démarrer.
const SHORTCUT_DEPTH: int = 3

## Raccourcis qui accompagnent un jeu sans être le jeu : on ne les garde pas.
const REJECTED_SHORTCUTS: PackedStringArray = [
	"unins", "désinstall", "desinstall", "uninstall", "readme", "lisez", "manual",
	"manuel", "support", "site web", "website", "configurat", "settings", "éditeur",
	"editor", "server", "serveur", "documentation", "aide", "help",
	"crash", "report", "benchmark", "redist", "directx", "vcredist",
]

## Applications courantes qui traînent un raccourci sur le Bureau. Aucune n'est
## un jeu : les écarter vaut mieux que de demander à l'utilisateur de faire le
## ménage dans sa bibliothèque.
const APP_BLOCKLIST: PackedStringArray = [
	"chrome", "firefox", "msedge", "iexplore", "opera", "brave", "vivaldi",
	"discord", "teams", "zoom", "slack", "skype", "whatsapp", "telegram",
	"thunderbird", "outlook", "mailflow", "proton", "spotify", "nuclear",
	"notion", "obsidian", "claude", "chatgpt", "antigravity",
	"code", "vscode", "sublime", "notepad", "cursor", "docker", "git",
	"libreoffice", "soffice", "winword", "excel", "powerpnt", "acrord",
	"obs64", "obs32", "audacity", "gimp", "krita", "inkscape", "davinci",
	"fl64", "fl studio", "ableton", "reaper",
	"winrar", "7zfm", "vlc", "easeus", "unigetui", "lghub", "nvidia app",
	"geforce", "armoury", "msiafterburner", "rivatuner", "synology",
	"radvideo", "autoclicker", "auto clicker", "luatools", "debload",
	"explorer", "cmd", "powershell", "terminal", "regedit", "taskmgr",
	"python", "idle", "node", "npm", "java", "visual studio", "installer",
	"updater", "recovery", "tailscale", "parsec", "localsend", "plex",
	"teamviewer", "anydesk", "onedrive", "dropbox", "google drive",
	"fl cloud", "bakkesmod", "wireshark", "putty", "filezilla",
]

## Dossiers système : ce qu'on y trouve n'est jamais un jeu.
const SYSTEM_PATHS: PackedStringArray = [
	"c:/windows", "/usr/bin/gnome", "/usr/bin/xdg",
]

## Toutes les sources, dédoublonnées et triées par titre.
static func find_all() -> Array[GameEntry]:
	var games: Array[GameEntry] = []
	var seen_ids: Dictionary = {}
	var seen_targets: Dictionary = {}

	# L'ordre compte : une entrée Steam décrit mieux le jeu que son raccourci,
	# et c'est la première vue qui reste.
	var candidates: Array[GameEntry] = []
	candidates.append_array(steam_games())
	candidates.append_array(epic_games())
	candidates.append_array(shortcut_games())

	for found: GameEntry in candidates:
		var target_key: String = _target_key(found)
		if seen_ids.has(found.id) or seen_targets.has(target_key):
			continue
		seen_ids[found.id] = true
		seen_targets[target_key] = true
		games.append(found)

	games.sort_custom(func(a: GameEntry, b: GameEntry) -> bool:
		return a.title.naturalnocasecmp_to(b.title) < 0
	)
	return games

# --- Steam --------------------------------------------------------------------

## Jeux installés déclarés par Steam. Le lancement passe par Steam lui-même
## (`-applaunch`) : c'est lui qui connaît les arguments et la synchronisation.
static func steam_games() -> Array[GameEntry]:
	var games: Array[GameEntry] = []
	var root: String = steam_root()
	if root.is_empty():
		return games
	var client: String = root.path_join("steam.exe") if OS.get_name() == "Windows" else "steam"

	for library: String in _steam_libraries(root):
		var steamapps: String = library.path_join("steamapps")
		var dir: DirAccess = DirAccess.open(steamapps)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry: String = dir.get_next()
		while entry != "":
			if entry.begins_with("appmanifest_") and entry.ends_with(".acf"):
				var game: GameEntry = _steam_entry(steamapps.path_join(entry), client)
				if game != null:
					games.append(game)
			entry = dir.get_next()
		dir.list_dir_end()
	return games

## Dossier d'installation de Steam, cherché là où il se trouve d'ordinaire.
static func steam_root() -> String:
	var candidates: PackedStringArray = PackedStringArray()
	if OS.get_name() == "Windows":
		candidates.append("C:/Program Files (x86)/Steam")
		candidates.append("C:/Program Files/Steam")
		for drive: String in _drives():
			candidates.append(drive.path_join("Steam"))
	else:
		var home: String = OS.get_environment("HOME")
		candidates.append(home.path_join(".steam/steam"))
		candidates.append(home.path_join(".local/share/Steam"))
		candidates.append(home.path_join(".var/app/com.valvesoftware.Steam/.local/share/Steam"))
	for path: String in candidates:
		if DirAccess.dir_exists_absolute(path.path_join("steamapps")):
			return path
	return ""

## Bibliothèques Steam : celle du client, plus celles déclarées dans
## `libraryfolders.vdf` (les jeux vivent souvent sur un autre disque).
static func _steam_libraries(root: String) -> PackedStringArray:
	var libraries: PackedStringArray = PackedStringArray([root])
	var vdf: String = root.path_join("steamapps/libraryfolders.vdf")
	if not FileAccess.file_exists(vdf):
		return libraries
	for line: String in FileAccess.get_file_as_string(vdf).split("\n"):
		var value: String = _vdf_value(line, "path")
		if value.is_empty():
			continue
		var path: String = value.replace("\\\\", "/").replace("\\", "/")
		if DirAccess.dir_exists_absolute(path) and not libraries.has(path):
			libraries.append(path)
	return libraries

static func _steam_entry(manifest: String, client: String) -> GameEntry:
	var appid: String = ""
	var title: String = ""
	var install_dir: String = ""
	for line: String in FileAccess.get_file_as_string(manifest).split("\n"):
		if appid.is_empty():
			appid = _vdf_value(line, "appid")
		if title.is_empty():
			title = _vdf_value(line, "name")
		if install_dir.is_empty():
			install_dir = _vdf_value(line, "installdir")
	if appid.is_empty() or title.is_empty():
		return null
	# Outils et redistribuables partagent le format des jeux : on les écarte.
	if not _is_plausible_title(title):
		return null
	# Un manifeste peut survivre à une désinstallation : on vérifie les fichiers.
	var installed: String = manifest.get_base_dir().path_join("common").path_join(install_dir)
	if not install_dir.is_empty() and not DirAccess.dir_exists_absolute(installed):
		return null

	var game := GameEntry.new()
	game.id = "steam-%s" % appid
	game.title = title
	game.executable = client
	game.args = PackedStringArray(["-applaunch", appid])
	game.source = "scan"
	var art: Dictionary = steam_artwork(client.get_base_dir(), appid)
	game.cover = art.get("cover", "")
	game.background = art.get("background", "")
	return game

## Valeur d'une clé dans une ligne de fichier Valve : `"clé"		"valeur"`.
## La ligne est indentée : on cherche la clé parmi les fragments plutôt que de
## supposer sa position, sinon la tabulation de tête passe pour la clé.
static func _vdf_value(line: String, key: String) -> String:
	var parts: PackedStringArray = line.split("\"", false)
	for i: int in parts.size():
		if parts[i].strip_edges().nocasecmp_to(key) != 0:
			continue
		for j: int in range(i + 1, parts.size()):
			var value: String = parts[j].strip_edges()
			if not value.is_empty():
				return value
		return ""
	return ""

# --- Epic ---------------------------------------------------------------------

## Jeux installés par l'Epic Games Launcher : un manifeste JSON par jeu.
static func epic_games() -> Array[GameEntry]:
	var games: Array[GameEntry] = []
	var manifests: String = "C:/ProgramData/Epic/EpicGamesLauncher/Data/Manifests"
	var dir: DirAccess = DirAccess.open(manifests)
	if dir == null:
		return games
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.ends_with(".item"):
			var game: GameEntry = _epic_entry(manifests.path_join(entry))
			if game != null:
				games.append(game)
		entry = dir.get_next()
	dir.list_dir_end()
	return games

static func _epic_entry(path: String) -> GameEntry:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return null
	var data: Dictionary = parsed
	var title: String = str(data.get("DisplayName", ""))
	var location: String = str(data.get("InstallLocation", "")).replace("\\", "/")
	var executable: String = str(data.get("LaunchExecutable", "")).replace("\\", "/")
	if title.is_empty() or location.is_empty() or executable.is_empty():
		return null
	var full: String = location.path_join(executable)
	if not FileAccess.file_exists(full) or not _is_plausible_title(title):
		return null

	var game := GameEntry.new()
	game.id = "epic-%s" % str(data.get("AppName", title)).to_lower()
	game.title = title
	game.executable = full
	game.source = "scan"
	game.cover = find_local_cover(location)
	if game.cover.is_empty():
		game.cover = find_local_cover(executable.get_base_dir())
	return game

# --- Raccourcis ---------------------------------------------------------------

## Raccourcis du Bureau et du menu Démarrer (`.lnk`), ou entrées de menu
## déclarées comme jeux sous Linux (`.desktop`).
static func shortcut_games() -> Array[GameEntry]:
	var games: Array[GameEntry] = []
	for folder: String in shortcut_folders():
		_collect_shortcuts(folder, 0, games)
	return games

static func shortcut_folders() -> PackedStringArray:
	var folders: PackedStringArray = PackedStringArray()
	if OS.get_name() == "Windows":
		var appdata: String = OS.get_environment("APPDATA").replace("\\", "/")
		var public_dir: String = OS.get_environment("PUBLIC").replace("\\", "/")
		var program_data: String = OS.get_environment("ProgramData").replace("\\", "/")
		folders.append(OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP))
		if not public_dir.is_empty():
			folders.append(public_dir.path_join("Desktop"))
		if not appdata.is_empty():
			folders.append(appdata.path_join("Microsoft/Windows/Start Menu/Programs"))
		if not program_data.is_empty():
			folders.append(program_data.path_join("Microsoft/Windows/Start Menu/Programs"))
	else:
		var home: String = OS.get_environment("HOME")
		folders.append(home.path_join(".local/share/applications"))
		folders.append("/usr/share/applications")
		folders.append("/var/lib/flatpak/exports/share/applications")

	var kept: PackedStringArray = PackedStringArray()
	for folder: String in folders:
		if not folder.is_empty() and DirAccess.dir_exists_absolute(folder) and not kept.has(folder):
			kept.append(folder)
	return kept

static func _collect_shortcuts(folder: String, depth: int, games: Array[GameEntry]) -> void:
	if depth > SHORTCUT_DEPTH:
		return
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var path: String = folder.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_collect_shortcuts(path, depth + 1, games)
		elif entry.to_lower().ends_with(".lnk"):
			var from_link: GameEntry = _shortcut_entry(path)
			if from_link != null:
				games.append(from_link)
		elif entry.to_lower().ends_with(".desktop"):
			var from_desktop: GameEntry = _desktop_entry(path)
			if from_desktop != null:
				games.append(from_desktop)
		entry = dir.get_next()
	dir.list_dir_end()

static func _shortcut_entry(path: String) -> GameEntry:
	var title: String = path.get_file().get_basename()
	if not _is_plausible_title(title):
		return null
	var link: ShellLink = ShellLink.parse(path)
	if link == null:
		return null
	var target: String = link.target
	if target.get_extension().to_lower() != "exe" or not FileAccess.file_exists(target):
		return null
	if _is_system_path(target) or not _is_plausible_title(target.get_file().get_basename()):
		return null
	if _is_application(title, target):
		return null

	var game := GameEntry.new()
	game.id = "lnk-%s" % str(target.to_lower().hash())
	game.title = title.strip_edges()
	game.executable = target
	if not link.arguments.strip_edges().is_empty():
		game.args = PackedStringArray(link.arguments.split(" ", false))
	game.source = "scan"
	game.cover = find_local_cover(target.get_base_dir())
	return game

## Entrée de menu Linux. On ne garde que ce qui se déclare comme jeu : les
## fichiers `.desktop` décrivent aussi bien un traitement de texte.
static func _desktop_entry(path: String) -> GameEntry:
	var title: String = ""
	var exec_line: String = ""
	var is_game: bool = false
	for raw: String in FileAccess.get_file_as_string(path).split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("Name=") and title.is_empty():
			title = line.substr(5)
		elif line.begins_with("Exec=") and exec_line.is_empty():
			exec_line = line.substr(5)
		elif line.begins_with("Categories=") and line.to_lower().contains("game"):
			is_game = true
		elif line.begins_with("NoDisplay=true"):
			return null
	if not is_game or title.is_empty() or exec_line.is_empty():
		return null

	# « Exec=jeu %U » : les champs de la spécification ne se transmettent pas.
	var parts: PackedStringArray = exec_line.split(" ", false)
	var command: String = parts[0].replace("\"", "")
	var args: PackedStringArray = PackedStringArray()
	for i: int in range(1, parts.size()):
		if not parts[i].begins_with("%"):
			args.append(parts[i])

	var game := GameEntry.new()
	game.id = "desktop-%s" % str(path.to_lower().hash())
	game.title = title.strip_edges()
	game.executable = command
	game.args = args
	game.source = "scan"
	if command.contains("/"):
		game.cover = find_local_cover(command.get_base_dir())
	return game

# --- Détection de jaquettes & fonds -------------------------------------------

const COVER_FILENAMES: PackedStringArray = [
	"library_600x900.jpg", "cover.jpg", "cover.png", "folder.jpg", "folder.png",
	"boxart.jpg", "boxart.png", "poster.jpg", "poster.png", "header.jpg"
]

static func find_local_cover(folder: String) -> String:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):
		return ""
	for name: String in COVER_FILENAMES:
		var file_path: String = folder.path_join(name)
		if FileAccess.file_exists(file_path):
			return file_path
	return ""

static func steam_artwork(root: String, appid: String) -> Dictionary:
	var result: Dictionary = {"cover": "", "background": ""}
	if root.is_empty() or appid.is_empty():
		return result
	var cache_dir: String = root.path_join("appcache/librarycache").path_join(appid)
	if DirAccess.dir_exists_absolute(cache_dir):
		var cover_600: String = cache_dir.path_join("library_600x900.jpg")
		if FileAccess.file_exists(cover_600):
			result["cover"] = cover_600
		elif FileAccess.file_exists(cache_dir.path_join("header.jpg")):
			result["cover"] = cache_dir.path_join("header.jpg")

		var hero: String = cache_dir.path_join("library_hero.jpg")
		if FileAccess.file_exists(hero):
			result["background"] = hero
	return result

# --- Outils communs -----------------------------------------------------------

static func _is_plausible_title(value: String) -> bool:
	var lowered: String = value.to_lower()
	for fragment: String in REJECTED_SHORTCUTS:
		if lowered.contains(fragment):
			return false
	return true

## Un raccourci est écarté quand son titre **ou** son exécutable porte le nom
## d'une application connue. Comparaison sur le nom seul : un jeu installé dans
## « C:/Program Files/Docker/... » n'existe pas, mais un dossier peut contenir
## un mot de la liste par hasard.
static func _is_application(title: String, executable: String) -> bool:
	var names: PackedStringArray = PackedStringArray([title.to_lower(), executable.get_file().get_basename().to_lower()])
	for name: String in names:
		for fragment: String in APP_BLOCKLIST:
			if name == fragment or name.begins_with(fragment + " ") or name.begins_with(fragment + "-") or name.begins_with(fragment + "_"):
				return true
			if name.contains(fragment) and fragment.length() >= 6:
				return true
	return false

static func _is_system_path(path: String) -> bool:
	var lowered: String = path.to_lower()
	for fragment: String in SYSTEM_PATHS:
		if lowered.begins_with(fragment):
			return true
	return false

## Deux sources peuvent décrire le même jeu : on compare ce qui sera lancé.
static func _target_key(game: GameEntry) -> String:
	return ("%s %s" % [game.executable, " ".join(game.args)]).to_lower()

## Lecteurs montés sous Windows : Godot n'expose pas la liste.
static func _drives() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for code: int in range(67, 91):
		var drive: String = "%s:/" % char(code)
		if DirAccess.dir_exists_absolute(drive):
			found.append(drive)
	return found
