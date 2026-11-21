extends CharacterBody3D

@export var speed: float = 3.5
@export var mouse_sensitivity: float = 0.0025
@onready var camera: Camera3D = $Camera3D
var controls_locked: bool = false
var navigation_enabled: bool = true
var spawn_transform: Transform3D

func _ready() -> void:
	spawn_transform = global_transform
	# Physical keys keep navigation in the same place with non-English layouts.
	for action: String in ["move_left", "move_right", "move_forward", "move_back", "reset_spawn"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var keys := {"move_left": KEY_A, "move_right": KEY_D, "move_forward": KEY_W,
		"move_back": KEY_S, "reset_spawn": KEY_R}
	for action: String in keys:
		var key := InputEventKey.new()
		key.physical_keycode = keys[action]
		if not InputMap.action_has_event(action, key):
			InputMap.action_add_event(action, key)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if controls_locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		set_navigation(true)
	elif event.is_action_pressed("reset_spawn"):
		reset_to_spawn()
	elif event is InputEventMouseMotion and navigation_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity, -1.45, 1.45)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not controls_locked:
		set_navigation(false)

func set_navigation(enabled: bool) -> void:
	navigation_enabled = enabled
	velocity = Vector3.ZERO
	if not enabled:
		for action: String in ["move_left", "move_right", "move_forward", "move_back"]:
			if InputMap.has_action(action):
				Input.action_release(action)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE

func reset_to_spawn() -> void:
	global_transform = spawn_transform
	camera.rotation = Vector3.ZERO
	velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	var axes := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if navigation_enabled else Vector2.ZERO
	var direction := global_basis * Vector3(axes.x, 0.0, axes.y)
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()
	if global_position.y < -5.0:
		reset_to_spawn()
