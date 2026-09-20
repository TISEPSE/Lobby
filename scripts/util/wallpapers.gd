class_name Wallpapers
extends RefCounted

## Fonds d'écran servant d'artwork aux jeux qui n'en ont pas encore.
## Déposer des images dans l'un de ces dossiers suffit : elles sont réparties
## entre les jeux, chacun gardant toujours le même fond.

const PROJECT_DIR: String = "res://assets/backgrounds"
const USER_DIR: String = "user://backgrounds"
const EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "webp", "bmp"]

static var _cache: PackedStringArray = PackedStringArray()
static var _scanned: bool = false

## Fonds disponibles, dans un ordre stable. Scanné une seule fois par session.
static func available() -> PackedStringArray:
	if _scanned:
		return _cache
	_scanned = true
	_cache = PackedStringArray()
	for dir_path: String in [PROJECT_DIR, USER_DIR]:
		_collect(dir_path)
	_cache.sort()
	return _cache

## Fond attribué à un jeu : dérivé de son identifiant, donc toujours le même.
## Chaîne vide s'il n'y a aucune image : l'appelant retombe sur un dégradé.
static func for_id(id: String) -> String:
	var files: PackedStringArray = available()
	if files.is_empty():
		return ""
	var distribution: Dictionary = {
		"aether-drift": 4,      # half-fox-half-robot (Sci-Fi hero)
		"hollow-signal": 5,     # view-airplane-flying (Atmospheric fantasy)
		"iron-verdict": 0,      # 153625 (Dark armored warrior)
		"lumen-garden": 1,      # 306757 (Combat action / particles)
		"nocturne-dive": 2,     # 49353 (Snow mountain helicopters)
		"saltwind-keep": 3,     # 9173 (Atmospheric landscape)
		"tessera-run": 5,       # Fantasy world
		"vantage-null": 0,      # Warrior
		"umbra-pact": 3,        # Landscape
		"quiet-orbit": 4,       # Fox
		"brass-lantern": 1,     # Action
		"ridgeline": 2,         # Snow mountain
	}
	if distribution.has(id):
		return files[distribution[id] % files.size()]
	return files[abs(id.hash()) % files.size()]

## Vide le cache : utile après avoir ajouté des images en cours de session.
static func rescan() -> void:
	_scanned = false

static func _collect(dir_path: String) -> void:
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			# Une fois exportées, les ressources importées portent un suffixe
			# supplémentaire : on retrouve le nom d'origine en le retirant.
			var clean: String = file_name
			for suffix: String in [".import", ".remap"]:
				if clean.ends_with(suffix):
					clean = clean.trim_suffix(suffix)
			if clean.get_extension().to_lower() in EXTENSIONS:
				var full: String = dir_path.path_join(clean)
				if not _cache.has(full):
					_cache.append(full)
		file_name = dir.get_next()
	dir.list_dir_end()
