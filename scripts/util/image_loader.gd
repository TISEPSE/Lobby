class_name ImageLoader
extends RefCounted

## Charge une image de jeu depuis le projet (`res://`), les données utilisateur
## (`user://`) ou un chemin absolu sur le disque. Retourne null si l'image est
## absente : l'appelant retombe alors sur un visuel généré.

static var _cache: Dictionary = {}

static func load_texture(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _cache.has(path):
		return _cache[path]
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path) as Texture2D
		if tex != null:
			_cache[path] = tex
			return tex
	if FileAccess.file_exists(path):
		var image: Image = Image.load_from_file(path)
		if image != null and not image.is_empty():
			var tex: Texture2D = ImageTexture.create_from_image(image)
			_cache[path] = tex
			return tex
	push_warning("Image introuvable : %s" % path)
	return null

static func invalidate(path: String = "") -> void:
	if path.is_empty():
		_cache.clear()
	else:
		_cache.erase(path)

## Charge une image de fond sans toucher au GPU : utilisable depuis un fil
## d'exécution secondaire. Le décodage d'un JPEG de plusieurs mégaoctets prend
## près d'une seconde (mesuré), d'où l'intérêt de le sortir du fil principal.
static func load_image(path: String, max_width: int) -> Image:
	var image: Image = null
	if ResourceLoader.exists(path):
		var texture: Texture2D = load(path) as Texture2D
		if texture != null:
			image = texture.get_image()
	elif FileAccess.file_exists(path):
		image = Image.load_from_file(path)
	if image == null or image.is_empty():
		push_warning("Image illisible : %s" % path)
		return null
	if image.get_width() > max_width:
		var height: int = maxi(int(round(float(max_width) * image.get_height() / float(image.get_width()))), 1)
		image.resize(max_width, height, Image.INTERPOLATE_BILINEAR)
	return image

## Clarté moyenne de la bande basse d'une image, là où se posent les jaquettes
## et les libellés. Sert à doser le voile : une image claire en demande plus.
## Échantillonnée, pas parcourue pixel par pixel, et appelée hors fil principal.
static func bottom_luminance(image: Image, from_ratio: float = 0.55) -> float:
	if image == null or image.is_empty():
		return 0.0
	var width: int = image.get_width()
	var height: int = image.get_height()
	var start_y: int = int(float(height) * from_ratio)
	var step_x: int = maxi(width / 48, 1)
	var step_y: int = maxi((height - start_y) / 24, 1)
	var total: float = 0.0
	var count: int = 0
	var y: int = start_y
	while y < height:
		var x: int = 0
		while x < width:
			total += image.get_pixel(x, y).get_luminance()
			count += 1
			x += step_x
		y += step_y
	return 0.0 if count == 0 else total / float(count)

## Variante synchrone, pour les cas où le coût est négligeable (jaquettes).
static func load_scaled(path: String, max_width: int) -> Texture2D:
	var image: Image = load_image(path, max_width)
	return null if image == null else ImageTexture.create_from_image(image)
