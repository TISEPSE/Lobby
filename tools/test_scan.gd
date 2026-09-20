extends SceneTree

## Vérifie le scan sur un dossier réel.
## Usage : godot --headless --script res://tools/test_scan.gd -- <dossier>

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: <dossier>")
		quit()
		return
	var folders := PackedStringArray([args[0]])
	var start: int = Time.get_ticks_msec()
	var games: Array[GameEntry] = GameScanner.scan(folders)
	print("%d jeu(x) trouve(s) en %d ms dans %s" % [games.size(), Time.get_ticks_msec() - start, args[0]])
	for game: GameEntry in games:
		print("  %-34s -> %s" % [game.title, game.executable])
	quit()
