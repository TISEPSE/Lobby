extends SceneTree

## Outil de développement : liste ce que la détection automatique trouve sur
## cette machine, sans lancer l'interface.
##   godot --headless --script res://tools/test_finder.gd

func _initialize() -> void:
	var start: int = Time.get_ticks_msec()
	var steam: Array[GameEntry] = GameFinder.steam_games()
	var epic: Array[GameEntry] = GameFinder.epic_games()
	var shortcuts: Array[GameEntry] = GameFinder.shortcut_games()
	var all: Array[GameEntry] = GameFinder.find_all()

	print("Steam : %s" % GameFinder.steam_root())
	print("Raccourcis cherchés dans : %s" % ", ".join(GameFinder.shortcut_folders()))
	_dump("Steam", steam)
	_dump("Epic", epic)
	_dump("Raccourcis", shortcuts)
	print("\nTotal après dédoublonnage : %d jeux en %d ms" % [all.size(), Time.get_ticks_msec() - start])
	quit()

func _dump(source: String, games: Array[GameEntry]) -> void:
	print("\n--- %s : %d ---" % [source, games.size()])
	for game: GameEntry in games:
		print("  %-45s %s %s" % [game.title, game.executable, " ".join(game.args)])
