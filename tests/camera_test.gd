extends Node
## Headless check of the player-controlled camera:
##   - aiming pulls the camera in over Rama's shoulder and narrows the view
##   - "forward" moves Rama the way the camera faces, wherever it's turned
## Run: Godot --headless --path . res://tests/camera_test.tscn

var _ok := true


func _ready() -> void:
	Game.checkpoint = 0  # forest path: no enemies nearby
	var level: Node = load("res://scenes/levels/siddhashrama.tscn").instantiate()
	add_child(level)
	var player := level.get_node("Player") as Player
	var rig := level.get_node("CameraRig") as CameraRig
	await get_tree().create_timer(0.6).timeout

	var far := rig.global_position.distance_to(player.global_position)
	Input.action_press("aim")
	await get_tree().create_timer(0.6).timeout
	var near := rig.global_position.distance_to(player.global_position)
	var aim_fov := rig.camera.fov
	_check(player.is_aiming, "holding aim puts Rama in aim mode")
	_check(near < far - 1.0, "aiming pulls the camera in (%.1f m -> %.1f m)" % [far, near])
	_check(aim_fov < 55.0, "aiming narrows the view (fov %.0f)" % aim_fov)
	Input.action_release("aim")
	await get_tree().create_timer(0.5).timeout

	# Turn the camera 90 degrees left and walk "forward".
	rig.yaw += PI / 2.0
	await get_tree().create_timer(0.1).timeout
	var start := player.global_position
	await get_tree().physics_frame
	Input.action_press("move_forward")
	await get_tree().create_timer(0.5).timeout
	Input.action_release("move_forward")
	var moved := player.global_position - start
	moved.y = 0.0
	var expected := rig.forward_flat()
	_check(moved.length() > 1.0 and moved.normalized().dot(expected) > 0.8, "forward follows the camera (dot %.2f)" % (moved.normalized().dot(expected) if moved.length() > 0.01 else 0.0))

	print("CAMERA TEST: ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	_ok = _ok and condition
