extends Control

## Vidéo d'introduction jouée avant l'accueil.
## Godot 4 ne décode nativement que l'Ogg Theora (.ogv) : tout autre conteneur
## échouera silencieusement, d'où la vérification avant lecture.

signal finished()

const HINT_DELAY: float = 1.2

@onready var _background: ColorRect = $Background
@onready var _player: VideoStreamPlayer = $Player
@onready var _hint: Label = $Hint

var is_playing: bool = false

func _ready() -> void:
	_background.color = Color.BLACK
	_hint.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_SMALL)
	_hint.add_theme_color_override("font_color", UITheme.COLOR_TEXT_DIM)
	_hint.modulate.a = 0.0
	_player.finished.connect(_on_finished)

## Lance la vidéo. Retourne false si elle est illisible : l'appelant enchaîne
## alors directement sur l'interface plutôt que de rester sur un écran noir.
func play(path: String) -> bool:
	var stream: VideoStream = MediaCatalog.video_stream(path)
	if stream == null:
		return false
	_player.stream = stream
	_player.play()
	if not _player.is_playing():
		push_warning("Vidéo illisible (Ogg Theora attendu) : %s" % path)
		return false

	is_playing = true
	visible = true
	# L'invite n'apparaît qu'après un instant : elle gênerait les premières images.
	var tween: Tween = create_tween()
	tween.tween_interval(HINT_DELAY)
	tween.tween_property(_hint, "modulate:a", 1.0, UITheme.ANIM_SLOW)
	return true

func skip() -> void:
	if not is_playing:
		return
	_player.stop()
	_on_finished()

func _unhandled_input(event: InputEvent) -> void:
	if not is_playing:
		return
	# N'importe quelle validation passe l'introduction.
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_options"):
		get_viewport().set_input_as_handled()
		skip()

func _on_finished() -> void:
	if not is_playing:
		return
	is_playing = false
	visible = false
	finished.emit()
