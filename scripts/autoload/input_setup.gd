extends Node
## Registers every input action at startup (keyboard, mouse, and gamepad),
## so controls work the same in the editor, desktop builds, and web builds.

const DEADZONE := 0.25


func _enter_tree() -> void:
	_action("move_left", [KEY_A, KEY_LEFT], [], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_action("move_right", [KEY_D, KEY_RIGHT], [], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_action("move_forward", [KEY_W, KEY_UP], [], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_action("move_back", [KEY_S, KEY_DOWN], [], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_action("attack_light", [KEY_J], [MOUSE_BUTTON_LEFT], [JOY_BUTTON_X], [])
	_action("attack_heavy", [KEY_K], [MOUSE_BUTTON_MIDDLE], [JOY_BUTTON_Y], [])
	# Hold to aim the bow over Rama's shoulder; left click / RT fires while aiming.
	_action("aim", [KEY_E], [MOUSE_BUTTON_RIGHT], [], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_action("look_left", [], [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_action("look_right", [], [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_action("look_up", [], [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_action("look_down", [], [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_action("dodge", [KEY_SHIFT, KEY_L], [], [JOY_BUTTON_B], [])
	_action("jump", [KEY_SPACE], [], [JOY_BUTTON_A], [])
	# Gamepad fire button while aiming (mouse uses left click).
	_action("bow", [], [], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_action("chakra", [KEY_Q], [], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_action("sneak", [KEY_C], [], [JOY_BUTTON_LEFT_STICK], [])
	_action("interact", [KEY_F], [], [], [])
	_action("astra", [KEY_R], [], [JOY_BUTTON_LEFT_SHOULDER], [])
	_action("switch_target", [KEY_TAB], [], [JOY_BUTTON_RIGHT_STICK], [])
	# Esc can be swallowed by browsers in fullscreen, so P also pauses.
	_action("pause", [KEY_ESCAPE, KEY_P], [], [JOY_BUTTON_START], [])


func _action(action: StringName, keys: Array, mouse_buttons: Array, joy_buttons: Array, joy_axes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
	for k in keys:
		var key_event := InputEventKey.new()
		key_event.physical_keycode = k
		InputMap.action_add_event(action, key_event)
	for m in mouse_buttons:
		var mouse_event := InputEventMouseButton.new()
		mouse_event.button_index = m
		InputMap.action_add_event(action, mouse_event)
	for b in joy_buttons:
		var button_event := InputEventJoypadButton.new()
		button_event.button_index = b
		InputMap.action_add_event(action, button_event)
	for a in joy_axes:
		var axis_event := InputEventJoypadMotion.new()
		axis_event.axis = a[0]
		axis_event.axis_value = a[1]
		InputMap.action_add_event(action, axis_event)
