class_name MediaCatalog
extends RefCounted

## Contenus proposés par la console : photos de profil et vidéos d'introduction.
## Rien n'est cherché ailleurs sur le PC — ce qui est livré avec l'interface est
## dans `res://assets/`, ce que tu ajoutes va dans `user://`, et la liste est
## relue à chaque démarrage sans toucher au code.

const AVATAR_DIRS: PackedStringArray = ["res://assets/avatars", "user://avatars"]
const BOOT_VIDEO_DIRS: PackedStringArray = ["res://assets/boot", "user://boot_videos"]

static func avatars() -> PackedStringArray:
	return _collect(AVATAR_DIRS, MediaTypes.IMAGE_AVATAR)

static func boot_videos() -> PackedStringArray:
	return _collect(BOOT_VIDEO_DIRS, MediaTypes.VIDEO)

## Nom affiché d'un fichier : « xbox_boot_2026.ogv » devient « Xbox boot 2026 ».
static func pretty_name(path: String) -> String:
	var name: String = path.get_file().get_basename().replace("_", " ").replace("-", " ").strip_edges()
	return name.capitalize() if name.is_empty() else name.substr(0, 1).to_upper() + name.substr(1)

## Flux prêt à jouer, qu'il vienne du projet (importé) ou d'un fichier posé sur
## le disque. Null si la vidéo a disparu.
static func video_stream(path: String) -> VideoStream:
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		return load(path) as VideoStream
	if not FileAccess.file_exists(path):
		return null
	var stream := VideoStreamTheora.new()
	stream.file = path
	return stream

## Vrai si le fichier est toujours là, dans le projet ou sur le disque.
static func exists(path: String) -> bool:
	return not path.is_empty() and (ResourceLoader.exists(path) or FileAccess.file_exists(path))

static func _collect(directories: PackedStringArray, extensions: PackedStringArray) -> PackedStringArray:
	var paths: PackedStringArray = PackedStringArray()
	for directory: String in directories:
		paths.append_array(_list(directory, extensions))
	return paths

static func _list(directory: String, extensions: PackedStringArray) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(directory)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir():
			# Une fois exporté, un fichier importé s'appelle « nom.ext.import ».
			var name: String = entry.trim_suffix(".import")
			var path: String = directory.path_join(name)
			if name.get_extension().to_lower() in extensions and not found.has(path):
				found.append(path)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
