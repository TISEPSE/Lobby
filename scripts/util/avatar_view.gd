class_name AvatarView
extends RefCounted

## Pastille ronde d'une photo de profil. Même rendu partout : carte du profil,
## grille de choix, et plus tard la barre du haut.

## Construit la pastille. Sans image, l'initiale du pseudo sur l'accent.
static func make(path: String, size: float, initial: String) -> Control:
	var avatar := Panel.new()
	avatar.custom_minimum_size = Vector2(size, size)
	avatar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# CLIP_AND_DRAW : le rond de fond reste dessiné et sert de masque à la photo.
	avatar.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW

	var box := StyleBoxFlat.new()
	box.bg_color = UITheme.COLOR_ACCENT
	box.set_corner_radius_all(int(size / 2.0))
	avatar.add_theme_stylebox_override("panel", box)

	var texture: Texture2D = ImageLoader.load_texture(path) if not path.is_empty() else null
	if texture != null:
		var image := TextureRect.new()
		image.texture = texture
		image.set_anchors_preset(Control.PRESET_FULL_RECT)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar.add_child(image)
	else:
		var label := Label.new()
		label.text = initial.substr(0, 1).to_upper()
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", int(size / 2.0))
		label.add_theme_color_override("font_color", UITheme.COLOR_BACKGROUND)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		avatar.add_child(label)
	return avatar
