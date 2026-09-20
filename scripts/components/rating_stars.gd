class_name RatingStars
extends RefCounted

## Note d'un jeu affichée en étoiles. Même langage partout : cinq étoiles, les
## obtenues en accent, les autres en retrait, puis la valeur chiffrée.

const STAR_ICON: Texture2D = preload("res://assets/icons/star.svg")
const COUNT: int = 5
## Une demi-étoile compte comme obtenue : 4,3 sur 5 allume la quatrième.
const HALF: float = 0.5

## Construit la rangée. `rating` va de 0 à 5 ; à 0, on n'affiche rien plutôt
## qu'une rangée éteinte qui ferait croire à une mauvaise note.
static func make(rating: float, size: float, with_value: bool = true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(size * 0.25))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if rating <= 0.0:
		return row

	for i: int in COUNT:
		var star := TextureRect.new()
		star.texture = STAR_ICON
		star.custom_minimum_size = Vector2(size, size)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		star.modulate = UITheme.COLOR_ACCENT if rating >= float(i) + HALF else UITheme.COLOR_STAR_EMPTY
		star.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(star)

	if with_value:
		var value := Label.new()
		value.text = "%.1f" % rating
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value.add_theme_font_size_override("font_size", int(size * 1.1))
		value.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(value)
	return row
