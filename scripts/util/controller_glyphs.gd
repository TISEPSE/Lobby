class_name ControllerGlyphs
extends RefCounted

## Symboles des boutons d'action, adaptés à la manette branchée ou au choix de l'utilisateur.
## Godot normalise les index (0 = bouton du bas, 1 = droite, 2 = gauche,
## 3 = haut) : seul l'affichage change d'une marque à l'autre.

enum Layout { AUTO, XBOX, PLAYSTATION }

## Fragments présents dans le nom d'une manette Sony, tel que le rapporte SDL.
const SONY_MARKERS: PackedStringArray = [
	"ps3", "ps4", "ps5", "playstation", "dualshock", "dualsense", "sony", "wireless controller",
]

## Vrais boutons Xbox officiels vectoriels
const XBOX_GLYPHS: Dictionary = {
	"ui_accept": {"label": "A", "icon": "res://assets/buttons/xbox/a.svg", "color": Color("6bb700"), "has_bg": false, "modulate_icon": false},
	"ui_cancel": {"label": "B", "icon": "res://assets/buttons/xbox/b.svg", "color": Color("e34b4b"), "has_bg": false, "modulate_icon": false},
	"ui_options": {"label": "X", "icon": "res://assets/buttons/xbox/x.svg", "color": Color("3a8cff"), "has_bg": false, "modulate_icon": false},
	"ui_search": {"label": "Y", "icon": "res://assets/buttons/xbox/y.svg", "color": Color("f2c14e"), "has_bg": false, "modulate_icon": false},
	"ui_menu": {"label": "Menu", "icon": "res://assets/buttons/xbox/menu.svg", "color": Color.WHITE, "has_bg": false, "modulate_icon": false},
	"ui_view": {"label": "Affichage", "icon": "res://assets/buttons/xbox/view.svg", "color": Color.WHITE, "has_bg": false, "modulate_icon": false},
}

## Vrais boutons PS5 officiels vectoriels
const PLAYSTATION_GLYPHS: Dictionary = {
	"ui_accept": {"label": "✕", "icon": "res://assets/buttons/ps5/cross.svg", "color": Color.WHITE, "has_bg": false, "modulate_icon": false},
	"ui_cancel": {"label": "○", "icon": "res://assets/buttons/ps5/circle.svg", "color": Color.WHITE, "has_bg": false, "modulate_icon": false},
	"ui_options": {"label": "□", "icon": "res://assets/buttons/ps5/square.svg", "color": Color.WHITE, "has_bg": false, "modulate_icon": false},
	"ui_search": {"label": "△", "icon": "res://assets/buttons/ps5/triangle.svg", "color": Color.WHITE, "has_bg": false, "modulate_icon": false},
	"ui_menu": {"label": "Options", "icon": "res://assets/buttons/ps5/options.svg", "color": Color.WHITE, "has_bg": false, "modulate_icon": false},
	"ui_create": {"label": "Créer", "icon": "res://assets/buttons/ps5/create.svg", "color": Color.WHITE, "has_bg": false, "modulate_icon": false},
}

## Disposition active d'après le réglage utilisateur ou la détection automatique.
static func active_layout() -> Layout:
	var pref: String = Settings.button_layout.to_lower()
	if pref == "xbox":
		return Layout.XBOX
	elif pref == "ps5" or pref == "playstation":
		return Layout.PLAYSTATION
	return detected_layout()

## Détection automatique d'après les manettes branchées.
static func detected_layout() -> Layout:
	for device: int in Input.get_connected_joypads():
		var name: String = Input.get_joy_name(device).to_lower()
		for marker: String in SONY_MARKERS:
			if name.contains(marker):
				return Layout.PLAYSTATION
	return Layout.XBOX

## Nom lisible de la disposition active
static func layout_name() -> String:
	match active_layout():
		Layout.PLAYSTATION:
			return "PlayStation (PS5)"
		_:
			return "Xbox"

## Glyphe d'une action : dictionnaire complet.
static func glyph(action: String) -> Dictionary:
	var table: Dictionary = PLAYSTATION_GLYPHS if active_layout() == Layout.PLAYSTATION else XBOX_GLYPHS
	return table.get(action, table.get("ui_accept", {}))

## Raccourci pour construire une barre d'aide : une entrée par action, dans
## l'ordre donné, avec son libellé. Conserve l'action d'origine pour pouvoir
## se recalculer dynamiquement au changement de disposition.
static func actions(entries: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		var action_name: String = str(entry.get("action", ""))
		var data: Dictionary = glyph(action_name)
		result.append({
			"action": action_name,
			"button": data.get("label", ""),
			"icon": data.get("icon", ""),
			"color": data.get("color", Color.WHITE),
			"has_bg": data.get("has_bg", false),
			"modulate_icon": data.get("modulate_icon", false),
			"label": entry.get("label", ""),
		})
	return result
