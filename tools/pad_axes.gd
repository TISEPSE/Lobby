extends SceneTree

## Outil de développement : mesure la dérive des sticks d'une manette.
## À lancer sans toucher à la manette, puis en poussant chaque stick à fond.
##   godot --path . --script res://tools/pad_axes.gd
##
## Sert à régler les seuils d'`InputManager` : si une valeur au repos dépasse
## STICK_RELEASE, la sélection se déplacera toute seule.

const DURATION: float = 6.0
const AXES: Array[int] = [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
const AXIS_NAMES: Array[String] = ["Stick gauche X", "Stick gauche Y", "Stick droit X", "Stick droit Y"]

var _elapsed: float = 0.0
var _maxima: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _announced: bool = false

func _process(delta: float) -> bool:
	if not _announced:
		_announced = true
		var pads: PackedInt32Array = Input.get_connected_joypads()
		if pads.is_empty():
			print("Aucune manette détectée.")
			return true
		for device: int in pads:
			print("Manette %d : %s  (%s)" % [device, Input.get_joy_name(device), Input.get_joy_guid(device)])
		print("\nMesure pendant %d secondes — ne touche à rien pour mesurer la dérive." % int(DURATION))

	var device: int = Input.get_connected_joypads()[0]
	for i: int in AXES.size():
		_maxima[i] = maxf(_maxima[i], absf(Input.get_joy_axis(device, AXES[i])))

	_elapsed += delta
	if _elapsed < DURATION:
		return false

	print("\nInclinaison maximale relevée :")
	for i: int in AXES.size():
		var flag: String = "  <-- dépasse le seuil de relâchement (0.40)" if _maxima[i] > 0.40 else ""
		print("  %-16s %.3f%s" % [AXIS_NAMES[i], _maxima[i], flag])
	return true
