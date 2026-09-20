extends SceneTree

## Mesure le coût de préparation des fonds d'écran.
## Usage : godot --headless --path . --script res://tools/bench_textures.gd

func _initialize() -> void:
	var files: PackedStringArray = Wallpapers.available()
	print("fonds disponibles : %d" % files.size())
	for path: String in files:
		var start: int = Time.get_ticks_usec()
		var texture: Texture2D = ImageLoader.load_scaled(path, 1920)
		var elapsed: float = float(Time.get_ticks_usec() - start) / 1000.0
		if texture == null:
			print("%-28s ECHEC" % path.get_file())
			continue
		print("%-28s %4dx%-4d -> %4dx%-4d  %6.1f ms" % [
			path.get_file(), texture.get_width(), texture.get_height(),
			texture.get_width(), texture.get_height(), elapsed])
	quit()
