extends Node

## Autoload : préférences de la console, conservées dans user://settings.json.

signal changed()

const PATH: String = "user://settings.json"
const VERSION: int = 1

## Dossiers où chercher les jeux. Chacun contient en principe un sous-dossier
## par jeu, mais un exécutable posé directement dedans est également reconnu.
var game_folders: PackedStringArray = PackedStringArray()
var profile_name: String = "Joueur"
## Chemin de la photo de profil. Vide : on affiche l'initiale du pseudo.
var avatar_path: String = ""
## Vidéo jouée au démarrage, avant l'accueil. Vide : on va droit à l'interface.
var boot_video_path: String = ""
## Permet de garder la vidéo configurée tout en la désactivant.
var boot_video_enabled: bool = true
## Disposition des touches manette : "auto" (détectée), "xbox" ou "ps5".
var button_layout: String = "auto"

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var text: String = FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("settings.json illisible, réglages par défaut conservés.")
		return

	var data: Dictionary = parsed
	profile_name = str(data.get("profile_name", profile_name))
	avatar_path = str(data.get("avatar_path", avatar_path))
	boot_video_path = str(data.get("boot_video_path", boot_video_path))
	boot_video_enabled = bool(data.get("boot_video_enabled", boot_video_enabled))
	button_layout = str(data.get("button_layout", button_layout))
	game_folders = PackedStringArray()
	for folder: Variant in data.get("game_folders", []):
		game_folders.append(str(folder))
	changed.emit()

func save_settings() -> void:
	var payload: Dictionary = {
		"version": VERSION,
		"profile_name": profile_name,
		"avatar_path": avatar_path,
		"boot_video_path": boot_video_path,
		"boot_video_enabled": boot_video_enabled,
		"button_layout": button_layout,
		"game_folders": Array(game_folders),
	}
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		push_error("Écriture impossible dans %s (%s)" % [PATH, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

## Ajoute un dossier s'il n'est pas déjà suivi. Retourne false s'il l'était.
func add_folder(path: String) -> bool:
	var clean: String = path.trim_suffix("/").trim_suffix("\\")
	if clean.is_empty() or game_folders.has(clean):
		return false
	game_folders.append(clean)
	save_settings()
	changed.emit()
	return true

## Change le pseudo et prévient l'interface.
func set_profile_name(value: String) -> void:
	var clean: String = value.strip_edges()
	if clean.is_empty() or clean == profile_name:
		return
	profile_name = clean
	save_settings()
	changed.emit()

## Change la photo de profil. Chemin vide : retour à l'initiale.
func set_avatar(path: String) -> void:
	if path == avatar_path:
		return
	avatar_path = path
	save_settings()
	changed.emit()

## Choisit la vidéo d'introduction. Chemin vide : plus de vidéo au démarrage.
func set_boot_video(path: String) -> void:
	if path == boot_video_path:
		return
	boot_video_path = path
	save_settings()
	changed.emit()

func set_boot_video_enabled(enabled: bool) -> void:
	if enabled == boot_video_enabled:
		return
	boot_video_enabled = enabled
	save_settings()
	changed.emit()

func set_button_layout(value: String) -> void:
	if value == button_layout:
		return
	button_layout = value
	save_settings()
	changed.emit()

## Vrai quand une vidéo est configurée, activée et toujours présente sur le disque.
func has_boot_video() -> bool:
	return boot_video_enabled and MediaCatalog.exists(boot_video_path)

func remove_folder(path: String) -> void:
	var index: int = game_folders.find(path)
	if index == -1:
		return
	game_folders.remove_at(index)
	save_settings()
	changed.emit()
