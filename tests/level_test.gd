extends Node
## End-to-end check of the Siddhashrama level, one section at a time, loading
## the level at each checkpoint like a respawn would.
## Run: Godot --headless --path . res://tests/level_test.tscn

const LEVEL := "res://scenes/levels/siddhashrama.tscn"

var level: Node3D
var player: Player
var _ok := true


func _ready() -> void:
	await _test_start()
	await _test_sentries()
	await _test_camp()
	await _test_ravine()
	await _test_shrine()
	await _test_yagna_and_boss()
	print("LEVEL TEST: ", "PASS" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)


# --- Sections ---------------------------------------------------------------

func _test_start() -> void:
	print("[forest]")
	await _load(0)
	_check(player.global_position.distance_to(_section(0).spawn_point().global_position) < 0.5, "Rama spawns at the forest start")
	await _walk_to(Vector3(0, 0, -9))
	await _wait(0.3)
	var hud := level.get_node("HUD")
	_check(hud._caption_box.visible, "intro captions appear")


func _test_sentries() -> void:
	print("[sentries]")
	await _load(1)
	var enc := _section(1).get_node("Sentries") as Encounter
	var sentries := _enemies_in(enc)
	_check(sentries.size() == 3, "3 sentries placed")
	_check(sentries.all(func(e: Enemy) -> bool: return not e.aware), "sentries start unaware")
	# Sneak up behind the standing sentry and take it down.
	var victim := sentries[1]
	player.is_sneaking = true
	player.teleport(victim.global_position - victim.facing() * 1.6, victim.facing())
	await _wait(0.2)
	_check(player.takedown_candidate == victim, "takedown offered from behind")
	await _tap("attack_light")
	await _wait(0.8)
	_check(not is_instance_valid(victim) or victim.is_dead(), "takedown kills the sentry")
	var others_unaware := true
	for e in _enemies_in(enc):
		if e.aware:
			others_unaware = false
	_check(others_unaware, "other sentries didn't notice")
	# Being seen alerts a sentry.
	var watcher := _enemies_in(enc)[0]
	player.is_sneaking = false
	player.teleport(watcher.global_position + watcher.facing() * 6.0, -watcher.facing())
	await _wait(1.5)
	_check(watcher.aware, "sentry spots Rama standing in front of it")
	await _kill_all(enc)
	await _wait(2.0)
	_check(enc.is_complete(), "sentry area cleared")
	_check(_section(1).get_node("ExitGate").is_open, "exit gate opens")


func _test_camp() -> void:
	print("[camp]")
	await _load(2)
	var enc := _section(2).get_node("CampFight") as Encounter
	await _walk_to(Vector3(0, 0, -93))
	await _wait(1.5)
	_check(enc.is_started(), "camp ambush triggers")
	_check(_enemies_in(enc).size() == 4, "wave 1: 4 rakshasas (got %d)" % _enemies_in(enc).size())
	await _kill_all(enc)
	await _wait(3.0)
	_check(_enemies_in(enc).size() == 5, "wave 2: 5 rakshasas (got %d)" % _enemies_in(enc).size())
	await _kill_all(enc)
	await _wait(2.0)
	_check(enc.is_complete() and _section(2).get_node("ExitGate").is_open, "camp cleared, gate opens")


func _test_ravine() -> void:
	print("[ravine]")
	await _load(3)
	var enc := _section(3).get_node("Ravine") as Encounter
	await _walk_to(Vector3(0, 0, -140))
	await _wait(0.5)
	var archers := _enemies_in(enc).filter(func(e: Enemy) -> bool: return e is Archer)
	_check(archers.size() == 3 and archers.all(func(a: Enemy) -> bool: return a.aware), "3 archers on ledges, alerted")
	# Archers shoot Rama.
	var hp := player.health
	for i in 60:
		await _wait(0.1)
		if player.health < hp:
			break
	_check(player.health < hp, "archer arrows hit Rama")
	player.heal(100)
	# Fire arrow: shoot past a torch at the first archer.
	var torch := _section(3).find_children("Torch*", "", false, false)[0] as Node3D
	var target := archers[0] as Enemy
	player.teleport(torch.global_position + Vector3(0.6, 0, 1.5), Vector3.FORWARD)
	player.current_target = target
	var arrow := player.arrow_scene.instantiate() as Projectile
	level.add_child(arrow)
	arrow.launch(torch.global_position + Vector3(0, 1.4, 0.8), Combat.aim_point(target) - (torch.global_position + Vector3(0, 1.4, 0.8)), player)
	await _wait(0.1)
	_check(not is_instance_valid(arrow) or arrow.is_fire, "arrow passing a torch catches fire")
	# Charged bow shot through the real input.
	player.teleport(Vector3(0, 0, -150), Vector3.FORWARD)
	player._invuln_left = 3.0  # archers would interrupt the draw
	await _wait(0.2)
	var archer_hp := {}
	for a in archers:
		if is_instance_valid(a):
			archer_hp[a] = a.health
	# Aim over the shoulder at the nearest archer and draw with the fire button.
	var rig := level.get_node("CameraRig") as CameraRig
	rig.look_toward(Combat.aim_point(archers[1]) if is_instance_valid(archers[1]) else Vector3(0, 2, -160))
	await get_tree().physics_frame  # simulated presses must land on a physics step
	Input.action_press("aim")
	Input.action_press("bow")
	for i in 30:  # hit-stops from nearby hits slow game time, so poll
		await _wait(0.1)
		if player.bow_charge >= 1.0:
			break
	_check(player.bow_charge >= 1.0, "bow charges fully")
	var aimed := player.aim_assist_target()
	var before: float = aimed.health if aimed and "health" in aimed else -1.0
	var aimed_enemy := aimed is Enemy
	Input.action_release("bow")
	await _wait(0.6)
	Input.action_release("aim")
	_check(aimed_enemy and (not is_instance_valid(aimed) or (aimed as Enemy).is_dead() or (aimed as Enemy).health < before), "charged arrow hits the locked target")
	await _kill_all(enc)
	await _wait(3.0)
	await _kill_all(enc)
	await _wait(2.0)
	_check(enc.is_complete() and _section(3).get_node("ExitGate").is_open, "ravine cleared, gate opens")


func _test_shrine() -> void:
	print("[shrine]")
	Game.has_chakra = false
	await _load(4)
	_check(not player.has_chakra, "no chakra before the shrine")
	await _walk_to(Vector3(0, 0, -203.5))
	await _wait(1.2)
	_check(player.has_chakra and Game.has_chakra, "chakra picked up")
	var enc := _section(4).get_node("ShrineAmbush") as Encounter
	_check(enc.is_started(), "shrine ambush triggers")
	var brute: Brute = null
	for e in _enemies_in(enc):
		if e is Brute:
			brute = e
	_check(brute != null, "brute spawns")
	if brute:
		await _wait(1.0)
		var hp := brute.health
		var front := brute.global_position + brute.facing() * 2.0
		brute.take_damage(10.0, front, 2.0, "light")
		_check(brute.health == hp, "brute's shield blocks a light hit from the front")
		brute.take_damage(10.0, brute.global_position - brute.facing() * 2.0, 2.0, "light")
		_check(brute.health < hp, "brute takes a hit from behind")
		hp = brute.health
		brute.take_damage(35.0, front, 6.0, "charged")
		_check(brute.health < hp and not brute.is_guarding(), "charged arrow breaks the brute's guard")
	await _kill_all(enc)
	await _wait(1.0)
	# Ring each bell with an arrow.
	var puzzle := _section(4).get_node("Bells")
	for bell in puzzle.get_children():
		var from := Vector3(bell.global_position.x * 0.3, 1.4, bell.global_position.z + 8.0)
		var arrow := player.arrow_scene.instantiate() as Projectile
		level.add_child(arrow)
		arrow.launch(from, bell.aim_point() - from, player)
		for i in 20:
			await _wait(0.1)
			if bell.is_rung:
				break
	_check(puzzle.is_complete(), "arrows ring all three bells")
	# The chakra homes onto something close by.
	var near := _section(4).get_node("ExitGate") as Node3D
	player.teleport(Vector3(0, 0, -215), Vector3.FORWARD)
	await _wait(0.2)
	player.chakra_ready = true
	player._throw_chakra()
	await _wait(1.6)
	_check(player.chakra_ready, "chakra flies out and returns to Rama")
	await _wait(1.0)
	_check(_section(4).get_node("ExitGate").is_open, "shrine gate opens")


func _test_yagna_and_boss() -> void:
	print("[yagna]")
	await _load(5)
	var section := _section(5)
	var enc := section.get_node("YagnaEncounter") as Encounter
	var altar := section.get_node("YagnaAltar")
	await _walk_to(Vector3(0, 0, -245))
	await _wait(1.5)
	_check(enc.is_started(), "yagna defense starts")
	_check(not section.get_node("EntryGate").is_open, "entry gate shuts behind Rama")
	# Stay far away: rakshasas should go for the fire.
	player.teleport(Vector3(0, 0, -240), Vector3.FORWARD)
	var altar_hp: float = altar.health
	for i in 120:
		await _wait(0.1)
		if altar.health < altar_hp:
			break
	_check(altar.health < altar_hp, "rakshasas attack the yagna fire when Rama is away")
	for wave in 3:
		await _kill_all(enc)
		await _wait(2.5)
	await _kill_all(enc)
	await _wait(1.0)
	_check(enc.is_complete(), "all 3 yagna waves cleared")
	_check(Game.checkpoint == Game.CHECKPOINT_BOSS, "boss checkpoint reached")
	print("[tataka]")
	var tataka := section.get_node("Boss/Tataka") as Tataka
	for i in 80:
		await _wait(0.1)
		if tataka.visible and tataka.state != Tataka.State.ENTERING:
			break
	_check(tataka.visible and tataka.is_in_group("enemies"), "Tataka enters the arena")
	_check(level.get_node("HUD")._boss_box.visible, "boss health bar shows")
	await _wait(2.0)
	# Burst damage can't skip a stage: each big hit stops at the next line.
	tataka.take_damage(tataka.max_health * 0.9, tataka.global_position + Vector3.BACK * 3.0, 0.0, "heavy")
	_check(is_equal_approx(tataka.health, tataka.stage_floor(1)), "a huge hit stops at the stage line")
	for i in 40:
		await _wait(0.1)
		if tataka.stage == 2:
			break
	_check(tataka.stage == 2, "stage 2 at 80% health")
	for i in 40:
		await _wait(0.1)
		if tataka.airborne and tataka.state == Tataka.State.HOVER:
			break
	_check(tataka.airborne, "she takes to the sky in stage 2")
	for next in [3, 4, 5]:
		await _force_stage(tataka, next)
		_check(tataka.stage == next, "stage %d reached" % next)
	await _force_stage(tataka, 6)
	for i in 60:
		await _wait(0.1)
		if tataka.state == Tataka.State.FINISHER:
			break
	_check(tataka.state == Tataka.State.FINISHER and not tataka.is_dead(), "at zero she waits for the final blow")
	player.teleport(tataka.global_position + Vector3(0, 0, 3.0), Vector3.FORWARD)
	await _wait(0.2)
	_check(player.takedown_candidate == tataka, "final blow offered")
	var defeated := [false]
	section.get_node("Boss").defeated.connect(func() -> void: defeated[0] = true)
	await _tap("attack_light")
	for i in 40:
		await _wait(0.1)
		if defeated[0]:
			break
	_check(defeated[0], "Tataka is defeated")


# --- Helpers ----------------------------------------------------------------

## Damage Tataka (whenever she can be hit) until she reaches `stage`.
func _force_stage(tataka: Tataka, stage: int) -> void:
	for i in 300:
		if tataka.stage >= stage or tataka.state == Tataka.State.FINISHER:
			return
		if tataka._accepts_damage("arrow", tataka.global_position):
			tataka.take_damage(tataka.max_health, tataka.global_position + Vector3.BACK * 3.0, 0.0, "arrow")
		elif tataka.hidden:
			tataka._reveal_cooldown = 0.0
		await _wait(0.1)


func _load(checkpoint: int) -> void:
	if level:
		level.queue_free()
		await get_tree().process_frame
	Game.checkpoint = checkpoint
	Engine.time_scale = 1.0
	level = load(LEVEL).instantiate()
	add_child(level)
	player = level.get_node("Player") as Player
	await _wait(0.5)


func _section(index: int) -> Section:
	return level.get_node("Sections/S%d" % index) as Section


func _enemies_in(node: Node) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for n in node.find_children("*", "", true, false):
		if n is Enemy and not n.is_dead():
			out.append(n)
	return out


func _kill_all(node: Node) -> void:
	for e in _enemies_in(node):
		e.take_damage(9999.0, e.global_position + Vector3.BACK, 0.0, "astra")
	await _wait(0.3)


func _walk_to(point: Vector3) -> void:
	player.teleport(point, Vector3.FORWARD)
	await get_tree().physics_frame
	await get_tree().physics_frame


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
