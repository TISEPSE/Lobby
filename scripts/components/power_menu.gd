extends Control

## Fenêtre modale d'alimentation, centrée à l'écran.
## Premier niveau : les actions. Second niveau : la confirmation de l'action choisie.

signal closed()
signal message(text: String)

const ENTRY_HEIGHT: float = 78.0
const ENTRY_SEPARATION: int = 12

const ENTRIES: Array[Dictionary] = [
	{"label": "Éteindre la manette", "action": "controller", "confirm": false},
	{"label": "Redémarrer la console", "action": "reboot", "confirm": true},
	{"label": "Éteindre la console", "action": "shutdown", "confirm": true},
	{"label": "Quitter l'interface", "action": "quit", "confirm": true},
]

@onready var _scrim: ColorRect = $Scrim
@onready var _dialog: Panel = $Dialog
@onready var _margin: MarginContainer = $Dialog/Margin
@onready var _title: Label = $Dialog/Margin/Content/Title
@onready var _gap: Control = $Dialog/Margin/Content/Gap
@onready var _entries: VBoxContainer = $Dialog/Margin/Content/Entries

var is_open: bool = false

var _buttons: Array[Button] = []
var _pending: Dictionary = {}
var _return_focus: Control = null
var _tween: Tween = null

func _ready() -> void:
	_style()
	_show_actions()

## Ouvre la fenêtre et retient l'élément à re-sélectionner à la fermeture.
func open() -> void:
	if is_open:
		return
	is_open = true
	_return_focus = get_viewport().gui_get_focus_owner()
	visible = true
	_show_actions()
	_animate(1.0)
	if not _buttons.is_empty():
		_buttons[0].grab_focus()

func close() -> void:
	if not is_open:
		return
	is_open = false
	_animate(0.0)
	await _tween.finished
	visible = false
	if _return_focus != null and is_instance_valid(_return_focus):
		_return_focus.grab_focus()
	closed.emit()

func _animate(opacity: float) -> void:
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate:a", opacity, UITheme.ANIM_NORMAL)
	_tween.tween_property(_dialog, "scale", Vector2.ONE * (1.0 if opacity > 0.0 else 0.96), UITheme.ANIM_NORMAL)

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _pending.is_empty():
			close()
		else:
			_show_actions()

## Premier niveau : la liste des actions.
func _show_actions() -> void:
	_pending = {}
	_title.text = "Alimentation"
	_rebuild(ENTRIES.map(func(e: Dictionary) -> Dictionary: return {"label": e["label"], "data": e}))

## Second niveau : confirmer ou annuler l'action choisie.
func _show_confirm(entry: Dictionary) -> void:
	_pending = entry
	_title.text = "%s ?" % str(entry["label"])
	_rebuild([
		{"label": "Confirmer", "data": {"confirm_yes": true}},
		{"label": "Annuler", "data": {}},
	])

func _rebuild(items: Array) -> void:
	for button: Button in _buttons:
		button.queue_free()
	_buttons.clear()
	for item: Dictionary in items:
		var button: Button = _make_button(str(item["label"]))
		button.pressed.connect(_on_pressed.bind(item["data"]))
		_entries.add_child(button)
		_buttons.append(button)
	_link()
	if is_open and not _buttons.is_empty():
		_buttons[0].grab_focus()

## Le focus reste dans la fenêtre tant qu'elle est ouverte.
func _link() -> void:
	for i: int in _buttons.size():
		var button: Button = _buttons[i]
		var up: int = maxi(i - 1, 0)
		var down: int = mini(i + 1, _buttons.size() - 1)
		button.focus_neighbor_top = button.get_path_to(_buttons[up])
		button.focus_neighbor_bottom = button.get_path_to(_buttons[down])
		button.focus_neighbor_left = button.get_path_to(button)
		button.focus_neighbor_right = button.get_path_to(button)
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom

func _on_pressed(data: Dictionary) -> void:
	if data.is_empty():
		_show_actions()
		return
	if data.has("confirm_yes"):
		var action: String = str(_pending["action"])
		_pending = {}
		_run(action)
		return
	if bool(data["confirm"]):
		_show_confirm(data)
		return
	_run(str(data["action"]))

func _run(action: String) -> void:
	var error: String = ""
	match action:
		"controller":
			error = SystemPower.disconnect_controller()
		"reboot":
			error = SystemPower.reboot()
		"shutdown":
			error = SystemPower.shutdown()
		"quit":
			get_tree().quit()
			return
	close()
	if not error.is_empty():
		message.emit(error)

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = ENTRY_HEIGHT
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_BODY)
	button.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
	button.add_theme_stylebox_override("normal", UITheme.surface_box())
	button.add_theme_stylebox_override("hover", UITheme.surface_box())
	button.add_theme_stylebox_override("pressed", UITheme.focus_box())
	button.add_theme_stylebox_override("focus", UITheme.focus_box())
	return button

func _style() -> void:
	modulate.a = 0.0
	_scrim.color = Color(UITheme.COLOR_BACKGROUND, UITheme.SIDEBAR_SCRIM_ALPHA)

	var box := StyleBoxFlat.new()
	box.bg_color = UITheme.COLOR_SIDEBAR
	box.set_corner_radius_all(UITheme.TILE_CORNER_RADIUS * 2)
	box.shadow_color = Color(0, 0, 0, UITheme.MODAL_SHADOW_ALPHA)
	box.shadow_size = UITheme.MODAL_SHADOW_SIZE
	_dialog.add_theme_stylebox_override("panel", box)
	_dialog.pivot_offset = _dialog.size * 0.5

	_margin.add_theme_constant_override("margin_left", int(UITheme.SPACING_LARGE))
	_margin.add_theme_constant_override("margin_right", int(UITheme.SPACING_LARGE))
	_margin.add_theme_constant_override("margin_top", int(UITheme.SPACING_LARGE))
	_margin.add_theme_constant_override("margin_bottom", int(UITheme.SPACING_LARGE))
	_gap.custom_minimum_size.y = UITheme.SPACING_MEDIUM
	_entries.add_theme_constant_override("separation", ENTRY_SEPARATION)

	_title.add_theme_font_size_override("font_size", UITheme.FONT_SIZE_TITLE)
	_title.add_theme_color_override("font_color", UITheme.COLOR_TEXT)
