extends Node
## Headless check of the Tataka fight, stage by stage. Rama is kept alive
## (invulnerable) while Tataka runs her real AI for a while in each stage,
## so every attack gets exercised; then the stage-specific rules are checked.
## Run: Godot --headless --path . res://tests/tataka_test.tscn

const LEVEL := "res://scenes/levels/siddhashrama.tscn"

var level: Node3D
var player: Player
var tataka: Tataka
var _ok := true
var _seen := {}


func _ready() -> void:
	Game.checkpoint = Game.CHECKPOINT_BOSS
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player") as Player
	tataka = level.get_node("Sections/S5/Boss/Tataka") as Tataka
	for i in 100:
		await _wait(0.1)
		if tataka.state == Tataka.State.IDLE:
			break
	_check(tataka.stage == 1 and tataka.state == Tataka.State.IDLE, "Tataka enters and starts stage 1")

	print("[stage 1: the demoness]")
	await _run(14.0)
	_check(_seen_any(["WINDUP", "ACTIVE", "LEAP"]), "she attacks on the ground (%s)" % _seen_list())
	_check(not tataka.airborne, "stage 1 stays on the ground")

	print("[stage 2: storm-rider]")
	await _push_to_next_stage()
	_check(tataka.stage == 2, "stage 2 begins")
	await _wait_for(func() -> bool: return tataka.state == Tataka.State.HOVER, 8.0)
	_check(tataka.airborne and tataka.is_targetable(), "she flies, and can be shot")
	_check(tataka.global_position.y > 5.0, "she hovers high above the arena (%.1f m)" % tataka.global_position.y)
	_check(not tataka.is_in_group("enemies"), "blades can't target her in the sky")
	await _run(24.0)
	_check(_seen_any(["AIR_WINDUP"]) and _seen_any(["DIVE", "SWOOP", "AIR_ACTIVE", "AIR_RECOVER"]), "she attacks from the air (%s)" % _seen_list())
	# Arrows bring her down.
	await _wait_for(func() -> bool: return tataka.state == Tataka.State.HOVER, 30.0)
	var before := tataka.health
	var arrow := (player.arrow_scene as PackedScene).instantiate() as Projectile
	level.add_child(arrow)
	var from := player.global_position + Vector3.UP * 1.4
	arrow.launch(from, tataka.aim_point() - from, player)
	for i in 60:
		await get_tree().physics_frame
	_check(tataka.health < before, "a real arrow hits her in the sky")
	for i in 6:
		tataka.take_damage(30.0, player.global_position, 0.0, "charged")
	await _wait_for(func() -> bool: return tataka.state == Tataka.State.CRASHED, 4.0)
	_check(tataka.state == Tataka.State.CRASHED and not tataka.airborne, "enough arrows knock her out of the sky")
	var hp := tataka.health
	tataka.take_damage(10.0, tataka.global_position + Vector3.BACK * 2.0, 0.0, "light")
	_check(hp - tataka.health > 10.0, "she takes extra damage after crashing (%.0f)" % (hp - tataka.health))
	_check(before > tataka.health, "arrow damage counted")

	print("[stage 3: the brood]")
	await _push_to_next_stage()
	_check(tataka.stage == 3, "stage 3 begins")
	await _run(10.0)
	var adds := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node != tataka:
			adds += 1
	_check(adds > 0, "she summons rakshasas (%d)" % adds)
	_check(_herbs() > 0, "healing herbs sprout for stage 3")

	print("[stage 4: maya]")
	await _push_to_next_stage()
	_check(tataka.stage == 4, "stage 4 begins")
	await _wait_for(func() -> bool: return tataka.hidden, 8.0)
	_check(tataka.hidden and not tataka.is_targetable(), "she hides in the clouds, untargetable")
	_check(not tataka.take_damage(50.0, player.global_position, 0.0, "charged"), "hidden, she can't be hit")
	_check(adds == 0 or _living_adds() == 0, "her brood is gone")
	await _wait_for(func() -> bool: return not tataka.hidden and tataka.state == Tataka.State.HOVER, 12.0)
	_check(not tataka.hidden and tataka.is_targetable(), "lightning reveals her")
	await _run(20.0)
	_check(_seen_any(["DIVE", "SWOOP", "AIR_ACTIVE"]), "she strikes from the storm (%s)" % _seen_list())

	print("[stage 5: fury]")
	await _push_to_next_stage()
	_check(tataka.stage == 5, "stage 5 begins")
	await _run(20.0)
	_check(_seen_any(["WINDUP", "ACTIVE", "CHARGE", "LEAP", "TAKEOFF", "DIVE"]), "she fights on (%s)" % _seen_list())
	await _push_to_next_stage()
	await _wait_for(func() -> bool: return tataka.state == Tataka.State.FINISHER, 6.0)
	_check(tataka.state == Tataka.State.FINISHER and not tataka.is_dead(), "at zero health she kneels for the final blow")
	var defeated := [false]
	level.get_node("Sections/S5/Boss").defeated.connect(func() -> void: defeated[0] = true)
	player._invuln_left = 0.0
	player.teleport(tataka.global_position + tataka.facing() * -3.0, tataka.facing())
	await _wait(0.2)
	_check(player.takedown_candidate == tataka, "Rama can strike the final blow")
	await _tap("attack_light")
	await _wait_for(func() -> bool: return defeated[0], 6.0)
	_check(defeated[0], "Tataka is slain")

	print("TATAKA TEST: ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


## Let the fight play for a while with Rama untouchable, noting her states.
func _run(seconds: float) -> void:
	_seen.clear()
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	var step := 0
	while Time.get_ticks_msec() < end:
		player._invuln_left = 1.0
		player.heal(100.0)
		_seen[Tataka.State.keys()[tataka.state]] = true
		# Rama wanders so dives and swoops have somewhere to go.
		step += 1
		if step % 40 == 0:
			var spot := Vector3(randf_range(-12, 12), 0, randf_range(-282, -248))
			player.teleport(spot, Vector3.FORWARD)
		await get_tree().physics_frame


func _push_to_next_stage() -> void:
	var target := tataka.stage + 1
	for i in 400:
		player._invuln_left = 1.0
		if tataka.stage >= target or tataka.state == Tataka.State.FINISHER:
			break
		if tataka.hidden:
			tataka._reveal_cooldown = 0.0
		if tataka._accepts_damage("arrow", tataka.global_position):
			tataka.take_damage(tataka.max_health, player.global_position, 0.0, "arrow")
		await _wait(0.1)
	await _wait_for(func() -> bool: return tataka.state != Tataka.State.TRANSITION and tataka.state != Tataka.State.LANDING, 6.0)


func _wait_for(condition: Callable, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end and not condition.call():
		player._invuln_left = 1.0
		await get_tree().physics_frame


func _seen_any(states: Array) -> bool:
	for s in states:
		if _seen.has(s):
			return true
	return false


func _seen_list() -> String:
	return ", ".join(_seen.keys())


func _living_adds() -> int:
	var n := 0
	for node in get_tree().get_nodes_in_group("enemies"):
		if node != tataka:
			n += 1
	return n


func _herbs() -> int:
	return level.get_node("Sections/S5/Boss").find_children("*", "Area3D", true, false).size()


func _tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _check(condition: bool, label: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + label)
	_ok = _ok and condition
