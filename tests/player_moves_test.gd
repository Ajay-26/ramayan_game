extends Node
## Headless check of Rama's moveset: light combo chains to the finisher,
## heavy chain works, dodge moves him and returns to MOVE.
## Run: Godot --headless --path . res://tests/player_moves_test.tscn

var _player: Player
var _ok := true


func _ready() -> void:
	Game.checkpoint = 0  # forest path: no enemies nearby
	var level: Node = load("res://scenes/levels/siddhashrama.tscn").instantiate()
	add_child(level)
	_player = get_tree().get_first_node_in_group("player") as Player
	await get_tree().create_timer(0.3).timeout

	# The four melee strings.
	_check(await _string(["attack_light", "attack_light", "attack_light"]) == ["jab", "cross", "uppercut"], "L L L = jab, cross, uppercut")
	_check(await _string(["attack_light", "attack_heavy"]) == ["jab", "rising"], "L H = jab, rising sword slash")
	_check(await _string(["attack_light", "attack_light", "attack_heavy"]) == ["jab", "cross", "slam"], "L L H = jab, cross, sword slam")
	_check(await _string(["attack_heavy"]) == ["heavy"], "H = slow sword swing")
	_check(await _string(["attack_heavy", "attack_light"]) == ["heavy"], "nothing chains after a heavy")
	_check(not _player._hand_sword.visible and _player._hip_sword.visible, "sword is sheathed again afterwards")

	# Dodge backward (the combos lunge Rama toward the altar, so open space is behind him).
	var start := _player.global_position
	Input.action_press("move_back")
	await _tap("dodge")
	_check(_player.state == Player.State.DODGE, "dodge starts")
	_check(_player.is_invulnerable(), "dodge gives i-frames")
	await get_tree().create_timer(0.5).timeout
	Input.action_release("move_back")
	var moved := start.distance_to(_player.global_position)
	_check(moved > 3.0, "dodge travels (%.1f m)" % moved)
	_check(_player.state == Player.State.MOVE, "back to MOVE after dodge")

	# Drawing the bow roots Rama in place.
	await _wait_for_move()
	await get_tree().create_timer(0.4).timeout
	var before := _player.global_position
	await get_tree().physics_frame
	Input.action_press("aim")
	Input.action_press("bow")
	Input.action_press("move_forward")
	await get_tree().create_timer(0.6).timeout
	var drift := Vector2(_player.global_position.x - before.x, _player.global_position.z - before.z).length()
	_check(_player.bow_charge >= 0.0, "bow is drawing")
	_check(drift < 0.3, "can't walk while drawing the bow (moved %.2f m)" % drift)
	Input.action_release("move_forward")
	Input.action_release("bow")
	Input.action_release("aim")

	print("PLAYER MOVES TEST: ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


## Presses the buttons in order (each when the previous move allows a follow-up)
## and returns the list of moves Rama actually performed.
func _string(buttons: Array) -> Array:
	await _wait_for_move()
	await get_tree().create_timer(0.3).timeout
	var seen: Array = []
	for b in buttons:
		var before := seen.size()
		await _tap(b)
		# Wait until this press has started a new move and it can be followed up.
		for i in 60:
			await get_tree().physics_frame
			if _player.current_attack != "" and (seen.is_empty() or seen.back() != _player.current_attack):
				seen.append(_player.current_attack)
			if seen.size() > before and _player._phase == Player.Phase.RECOVERY:
				break
	for i in 90:
		await get_tree().physics_frame
		if _player.current_attack != "" and seen.back() != _player.current_attack:
			seen.append(_player.current_attack)
		if _player.state == Player.State.MOVE:
			break
	return seen


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


func _wait_for_move() -> void:
	for i in 120:
		if _player.state == Player.State.MOVE:
			return
		await get_tree().physics_frame


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	_ok = _ok and condition
