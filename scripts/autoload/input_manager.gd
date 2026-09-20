extends Node

## Gestionnaire global d'entrées : maintenir une direction (stick ou D-pad)
## fait défiler la sélection, au lieu de n'avancer que d'un cran.
##
## La répétition **déplace le focus elle-même** (`find_valid_focus_neighbor`).
## Synthétiser une action appuyée, comme on le faisait avant, laissait l'action
## bloquée à « pressée » : Godot ajoutait sa propre répétition par-dessus et la
## sélection partait toute seule.

const INITIAL_REPEAT_DELAY: float = 0.35
const REPEAT_INTERVAL: float = 0.12

## Inclinaison à atteindre pour qu'une direction compte, et seuil plus bas sous
## lequel elle est relâchée. Cet écart évite qu'un stick usé, qui traîne autour
## du seuil au repos, fasse défiler la sélection sans qu'on y touche.
const STICK_ENGAGE: float = 0.65
const STICK_RELEASE: float = 0.40

var _active_action: String = ""
var _next_repeat: float = 0.0
var _hold_time: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	var held: String = _detect_held_direction()

	if held.is_empty():
		_active_action = ""
		_hold_time = 0.0
		return

	# Nouvelle direction : le premier déplacement vient du système, on attend
	# avant de prendre le relais.
	if held != _active_action:
		_active_action = held
		_hold_time = 0.0
		_next_repeat = INITIAL_REPEAT_DELAY
		return

	_hold_time += delta
	if _hold_time >= _next_repeat:
		_move_focus(_active_action)
		_next_repeat += REPEAT_INTERVAL

## Direction maintenue, stick gauche ou D-pad. Chaîne vide si rien n'est tenu.
func _detect_held_direction() -> String:
	var device: int = _first_joypad()
	if device >= 0:
		var stick := Vector2(
			Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
			Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
		)
		# Tant qu'une direction est engagée, elle le reste jusqu'au seuil bas :
		# sans cette hystérésis, un stick qui oscille autour du seuil relance la
		# temporisation en boucle et la sélection défile toute seule.
		var threshold: float = STICK_RELEASE if not _active_action.is_empty() else STICK_ENGAGE
		if absf(stick.x) > threshold or absf(stick.y) > threshold:
			# Priorité à l'axe le plus incliné : pas de diagonale involontaire.
			if absf(stick.x) >= absf(stick.y):
				return "ui_right" if stick.x > 0.0 else "ui_left"
			return "ui_down" if stick.y > 0.0 else "ui_up"

	for action: String in ["ui_left", "ui_right", "ui_up", "ui_down"]:
		if Input.is_action_pressed(action):
			return action
	return ""

## Première manette branchée. Sans elle, seul le clavier parle.
func _first_joypad() -> int:
	var pads: PackedInt32Array = Input.get_connected_joypads()
	return pads[0] if pads.size() > 0 else -1

## Déplace la sélection d'un cran, en suivant les voisins déclarés par l'écran.
## On ne touche pas à l'état des actions : rien ne peut rester « appuyé ».
func _move_focus(action_name: String) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused == null or not is_instance_valid(focused):
		return
	var side: Side = SIDE_LEFT
	match action_name:
		"ui_right":
			side = SIDE_RIGHT
		"ui_up":
			side = SIDE_TOP
		"ui_down":
			side = SIDE_BOTTOM
	var neighbor: Control = focused.find_valid_focus_neighbor(side)
	if neighbor != null and neighbor != focused:
		neighbor.grab_focus()
