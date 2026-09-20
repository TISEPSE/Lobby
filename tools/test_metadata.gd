extends SceneTree

## Outil de développement : vérifie que les métadonnées Steam publiques
## répondent, sans lancer l'interface ni toucher à la bibliothèque.
##   godot --headless --script res://tools/test_metadata.gd

const FETCHER: GDScript = preload("res://scripts/components/metadata_fetcher.gd")

func _initialize() -> void:
	_run()

func _run() -> void:
	var fetcher: Node = FETCHER.new()
	root.add_child(fetcher)
	# Le nœud n'entre dans l'arbre qu'à la frame suivante : sans cette attente,
	# HTTPRequest refuse de partir (« is_inside_tree »).
	await process_frame

	var samples: Array[GameEntry] = [
		_make("steam-753640", "Outer Wilds"),
		_make("lnk-1", "Spider-Man2"),
		_make("lnk-2", "Hollow Knight"),
		_make("lnk-3", "Zzz Jeu Qui N Existe Pas"),
	]
	for game: GameEntry in samples:
		var start: int = Time.get_ticks_msec()
		var found: bool = await fetcher._complete(game)
		print("\n--- %s (%s) en %d ms ---" % [game.title, "trouvé" if found else "inconnu", Time.get_ticks_msec() - start])
		if not found:
			continue
		print("  note        : %.1f / 5" % game.rating)
		print("  genres      : %s" % game.genre)
		print("  sortie      : %s" % game.release_date)
		print("  résumé      : %s…" % game.synopsis.substr(0, 90))
	quit()

func _make(id: String, title: String) -> GameEntry:
	var game := GameEntry.new()
	game.id = id
	game.title = title
	game.source = "scan"
	return game
