extends SceneTree

func _initialize() -> void:
	var extension = load("res://native/ebon_hawk.gdextension")
	if extension == null or not ClassDB.class_exists("EbonHawkNative"):
		push_error("Native extension did not load/register")
		quit(1)
		return
	var bridge = ClassDB.instantiate("EbonHawkNative")
	var state: Dictionary = bridge.status()
	var permissions: Dictionary = bridge.permissions()
	if state.state != "unassigned" or state.interacting or not permissions.has_all(["capture", "accessibility", "listen"]):
		push_error("Unexpected native initial/permission state")
		quit(1)
		return
	if bridge.begin_interaction(0, 62):
		push_error("Cannot acquire input without a selected live source")
		bridge.stop()
		quit(1)
		return
	bridge.end_interaction()
	bridge.end_interaction()
	bridge.stop()
	var info: String = bridge.build_info()
	print(info)
	if not info.begins_with("M1 / macOS "):
		push_error("Unexpected native build information")
		quit(1)
	else:
		print("Native load and Objective-C++ call: PASS")
		quit(0)
