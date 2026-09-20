extends SceneTree

## Liste les manettes détectées et leur nom brut.
## Usage : godot --headless --script res://tools/pads.gd

func _initialize() -> void:
	var pads: PackedInt32Array = Input.get_connected_joypads()
	print("manettes detectees : %d" % pads.size())
	for device: int in pads:
		print("  [%d] nom=%s  guid=%s" % [device, Input.get_joy_name(device), Input.get_joy_guid(device)])
	quit()
