extends SceneTree

## Outil de développement : vérifie ce que Godot reçoit réellement sur les
## adresses d'images de Steam (taille et code de réponse).
##   godot --headless --script res://tools/test_http.gd

const URLS: Array[String] = [
	"https://cdn.cloudflare.steamstatic.com/steam/apps/753640/library_600x900_2x.jpg",
	"https://cdn.cloudflare.steamstatic.com/steam/apps/753640/library_hero.jpg",
	"https://cdn.cloudflare.steamstatic.com/steam/apps/753640/page_bg_generated_v6b.jpg",
]

func _initialize() -> void:
	_run()

func _run() -> void:
	var http := HTTPRequest.new()
	http.download_chunk_size = 65536
	root.add_child(http)
	await process_frame

	for url: String in URLS:
		var error: int = http.request(url)
		if error != OK:
			print("%-70s requête refusée : %s" % [url.get_file(), error_string(error)])
			continue
		var result: Array = await http.request_completed
		print("%-40s résultat=%d  code=%d  octets=%d" % [url.get_file(), int(result[0]), int(result[1]), (result[3] as PackedByteArray).size()])
	quit()
