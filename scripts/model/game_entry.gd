class_name GameEntry
extends RefCounted

## Un jeu de la bibliothèque. Correspond au modèle de données décrit dans CLAUDE.md.

var id: String = ""
var title: String = ""
var executable: String = ""
var args: PackedStringArray = PackedStringArray()
var cover: String = ""
var background: String = ""
var genre: String = ""
var synopsis: String = ""
var release_date: String = ""
var rating: float = 0.0
var playtime_minutes: int = 0
var last_played: Variant = null
var favorite: bool = false
## Origine de l'entrée : "sample" (données de démonstration), "scan" (trouvée
## sur le disque) ou "manual" (ajoutée à la main dans le JSON).
var source: String = "manual"

static func from_dict(data: Dictionary) -> GameEntry:
	var entry := GameEntry.new()
	entry.id = str(data.get("id", ""))
	entry.title = str(data.get("title", ""))
	entry.executable = str(data.get("executable", ""))
	for a: Variant in data.get("args", []):
		entry.args.append(str(a))
	entry.cover = str(data.get("cover", ""))
	entry.background = str(data.get("background", ""))
	entry.genre = str(data.get("genre", ""))
	entry.synopsis = str(data.get("synopsis", ""))
	entry.release_date = str(data.get("release_date", ""))
	entry.rating = float(data.get("rating", 0.0))
	entry.playtime_minutes = int(data.get("playtime_minutes", 0))
	entry.last_played = data.get("last_played", null)
	entry.favorite = bool(data.get("favorite", false))
	entry.source = str(data.get("source", "manual"))
	return entry

func to_dict() -> Dictionary:
	return {
		"id": id,
		"title": title,
		"executable": executable,
		"args": Array(args),
		"cover": cover,
		"background": background,
		"genre": genre,
		"synopsis": synopsis,
		"release_date": release_date,
		"rating": rating,
		"playtime_minutes": playtime_minutes,
		"last_played": last_played,
		"favorite": favorite,
		"source": source,
	}

## Temps de jeu lisible, par exemple « 2 h 15 » ou « 40 min ».
func playtime_text() -> String:
	if playtime_minutes <= 0:
		return "Jamais joué"
	if playtime_minutes < 60:
		return "%d min" % playtime_minutes
	return "%d h %02d" % [playtime_minutes / 60, playtime_minutes % 60]
