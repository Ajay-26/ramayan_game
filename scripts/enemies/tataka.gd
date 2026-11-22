class_name Tataka
extends Enemy
## Boss: Tataka, the giant demoness of the forest. Three phases.
##   Phase 1 (100-66%): arm sweep up close, ground slam, boulder throws at range.
##   Phase 2 (66-33%):  faster, and summons rakshasa grunts.
##   Phase 3 (<33%):    enraged; adds a charge across the arena and fire patches.
## Every big attack has a wind-up and a red ground telegraph. Deal enough damage
## quickly and she staggers to her knees, taking extra damage for a moment.

signal phase_changed(phase: int)
signal defeated

enum State { DORMANT, ENTERING, IDLE, WINDUP, ACTIVE, RECOVER, STAGGER, ROAR, CHARGE, DYING }

@export var grunt_scene: PackedScene
@export var boulder_scene: PackedScene
@export var sweep_damage := 27.0
@export var slam_damage := 38.0
@export var charge_damage := 34.0
@export var fire_damage := 11.0
## Damage needed (within a few seconds) to knock her down.
@export var poise := 200.0

var state := State.DORMANT
var phase := 1
var boss_name := "TATAKA"
var _t := 0.0
var _attack := ""
var _cooldown := 2.0
var _summon_cooldown := 6.0
var _fire_cooldown := 5.0
var _poise_damage := 0.0
var _poise_decay_wait := 0.0
var _hit_done := false
var _attack_point := Vector3.ZERO
var _charge_dir := Vector3.ZERO
var _adds: Array[Node] = []
var _tween: Tween
var add_spawn_points: Array[Node3D] = []

@onready var body_pivot: Node3D = $Visual/Body
@onready var arm_l: Node3D = $Visual/Body/ArmL
@onready var arm_r: Node3D = $Visual/Body/ArmR
var eye_mat: StandardMaterial3D


func _ready() -> void:
	super._ready()
	remove_from_group("targetable")  # until she enters
	remove_from_group("enemies")
	visible = false
	collision_layer = 0
	var eye := $Visual/Body/EyeL as MeshInstance3D
	eye_mat = (eye.get_active_material(0) as StandardMaterial3D).duplicate()
	eye.material_override = eye_mat
	($Visual/Body/EyeR as MeshInstance3D).material_override = eye_mat
	if model:
		_attach_features()


## Hangs her eyes, tusks, wild hair and bone necklace on the giant body's bones.
func _attach_features() -> void:
	var inv := 1.0 / model.scale.x  # keep each piece its own size on the scaled skeleton
	var place := func(node_path: String, bone: String, pos: Vector3, rot_deg := Vector3.ZERO, size := 1.0) -> void:
		var basis := Basis.from_euler(rot_deg * (PI / 180.0)).scaled(Vector3.ONE * inv * size)
		model.attach(get_node(node_path), bone, Transform3D(basis, pos))
	place.call("Visual/Body/EyeL", "Head", Vector3(-0.035, 0.075, 0.1), Vector3.ZERO, 0.5)
	place.call("Visual/Body/EyeR", "Head", Vector3(0.035, 0.075, 0.1), Vector3.ZERO, 0.5)
	place.call("Visual/Body/TuskL", "Head", Vector3(-0.025, 0.02, 0.1), Vector3(-160, 0, 0), 0.6)
	place.call("Visual/Body/TuskR", "Head", Vector3(0.025, 0.02, 0.1), Vector3(-160, 0, 0), 0.6)
	place.call("Visual/Body/Hair1", "Head", Vector3(0.06, 0.17, -0.04), Vector3.ZERO, 0.45)
	place.call("Visual/Body/Hair2", "Head", Vector3(-0.06, 0.16, -0.03), Vector3.ZERO, 0.45)
	place.call("Visual/Body/Hair3", "Head", Vector3(0.0, 0.2, -0.07), Vector3.ZERO, 0.45)
	place.call("Visual/Body/Hair4", "Head", Vector3(0.0, 0.1, -0.12), Vector3.ZERO, 0.45)
	var necklace := $Visual/Body/Necklace as Node3D
	model.attach(necklace, "UpperChest", Transform3D(Basis().scaled(Vector3(inv, inv * 0.5, inv) * 0.4), Vector3(0, 0.1, 0.05)))
	place.call("Visual/Body/Glow", "Head", Vector3(0, 0.05, 0.3))


func speed_scale() -> float:
	return [1.0, 1.0, 1.2, 1.4][phase]


## Leap into the arena from the darkness.
func enter_arena() -> void:
	visible = true
	add_to_group("targetable")
	add_to_group("enemies")
	collision_layer = Combat.LAYER_ENEMY
	state = State.ENTERING
	_t = 0.0
	var landing := global_position
	global_position = landing + Vector3(0, 18, -6)
	reset_physics_interpolation()
	var tween := new_tween()
	tween.tween_property(self, "global_position", landing, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		FX.shockwave(landing, 8.0, Color(1, 0.4, 0.2, 1))
		FX.explosion(landing, 6.0)
		FX.add_trauma(0.9)
		act("LandHard", 1.6)
		Combat.damage_in_radius(get_world_3d(), landing + Vector3.UP, 4.0, Combat.LAYER_PLAYER, 10.0, 14.0, "melee"))


func _physics_process(delta: float) -> void:
	if state == State.DORMANT:
		return
	_t += delta
	_cooldown -= delta * speed_scale()
	_summon_cooldown -= delta
	_fire_cooldown -= delta
	_poise_decay_wait -= delta
	if _poise_decay_wait <= 0.0:
		_poise_damage = maxf(_poise_damage - poise * 0.25 * delta, 0.0)
	if state != State.ENTERING:
		apply_gravity(delta)

	match state:
		State.ENTERING:
			if _t >= 1.6:
				_roar(false)
		State.IDLE:
			_idle(delta)
		State.WINDUP:
			decelerate(delta, 10.0)
			if _attack == "sweep" or _attack == "charge":
				face_toward(_player.global_position, delta, 3.0)
			if _t >= _windup_time():
				_begin_active()
		State.ACTIVE:
			_active(delta)
		State.CHARGE:
			_charging(delta)
		State.RECOVER:
			decelerate(delta, 8.0)
			if _t >= 1.0 / speed_scale():
				_set_idle()
		State.STAGGER:
			decelerate(delta, 6.0)
			if _t >= 2.8:
				_set_idle()
		State.ROAR:
			decelerate(delta, 10.0)
			if _t >= 1.6:
				_set_idle()
		State.DYING:
			pass

	if state == State.IDLE or state == State.RECOVER:
		locomote(delta, "HeavyIdle", "HeavyWalking", "HeavyWalking")
	if state != State.ENTERING and state != State.DYING:
		move_and_slide()


func _idle(delta: float) -> void:
	if _player == null or _player.is_dead():
		decelerate(delta, 8.0)
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	face_toward(_player.global_position, delta, 3.0 * speed_scale())

	if phase >= 3 and _fire_cooldown <= 0.0:
		_fire_cooldown = 5.0
		_spawn_fire_patch(_player.global_position)
	if phase >= 2 and _summon_cooldown <= 0.0 and _living_adds() < 2:
		_begin("summon")
		return
	if _cooldown <= 0.0:
		if dist < 5.5:
			_begin("sweep" if randf() < 0.55 else "slam")
		elif dist < 9.0:
			_begin("slam")
		elif phase >= 3 and randf() < 0.5:
			_begin("charge")
		else:
			_begin("boulder")
		return
	var desired := Vector3.ZERO
	if dist > 4.5:
		desired = path_direction(_player.global_position, delta, to_player / maxf(dist, 0.01)) * move_speed * speed_scale()
	_steer(desired, delta, 6.0)


func _begin(attack: String) -> void:
	_attack = attack
	state = State.WINDUP
	_t = 0.0
	_hit_done = false
	eye_mat.emission_energy_multiplier = 9.0
	if model:
		var wind := _windup_time()
		match attack:
			"sweep":
				act("HeavyCharge", wind + 0.1)
				FX.telegraph(global_position + facing() * 2.5, 5.0, wind)
			"slam":
				_attack_point = global_position + facing() * 3.5
				act("HeavyCharge", wind + 0.1)
				FX.telegraph(_attack_point, 3.8, wind)
			"boulder":
				_attack_point = _player.global_position
				act("ThrowR", wind + 0.55)  # the throw lands as the boulder leaves her hand
			"charge":
				act("HeavyCharge", wind + 0.1)
			"summon":
				act("Spawn", wind + 0.6)
		return
	_kill_tween()
	_tween = new_tween().set_parallel(true)
	var w := _windup_time()
	match attack:
		"sweep":
			_tween.tween_property(arm_r, "rotation", _deg(0, -100, 70), w)
			_tween.tween_property(body_pivot, "rotation:y", deg_to_rad(-30), w)
			FX.telegraph(global_position + facing() * 2.5, 5.0, w)
		"slam":
			_attack_point = global_position + facing() * 3.5
			_tween.tween_property(arm_l, "rotation", _deg(160, 0, 0), w)
			_tween.tween_property(arm_r, "rotation", _deg(160, 0, 0), w)
			_tween.tween_property(body_pivot, "rotation:x", deg_to_rad(15), w)
			FX.telegraph(_attack_point, 3.8, w)
		"boulder":
			_attack_point = _player.global_position
			_tween.tween_property(arm_r, "rotation", _deg(170, 0, -20), w)
		"charge":
			_tween.tween_property(body_pivot, "rotation:x", deg_to_rad(-25), w)
			_tween.tween_property(arm_l, "rotation", _deg(-40, 0, 40), w)
			_tween.tween_property(arm_r, "rotation", _deg(-40, 0, -40), w)
		"summon":
			_tween.tween_property(arm_l, "rotation", _deg(150, 0, 40), w)
			_tween.tween_property(arm_r, "rotation", _deg(150, 0, -40), w)


func _windup_time() -> float:
	var base: float = {"sweep": 0.75, "slam": 1.0, "boulder": 0.9, "charge": 0.9, "summon": 1.0}.get(_attack, 0.8)
	return base / speed_scale()


func _begin_active() -> void:
	state = State.ACTIVE
	_t = 0.0
	if model:
		match _attack:
			"sweep":
				act("Heavy1", 0.75)
			"slam":
				act("Heavy2", 0.7)
			"charge":
				_charge_dir = Combat.flat_direction(global_position, _player.global_position, facing())
				state = State.CHARGE
				_anim_lock = 0.0
				model.play("Sprint", 1.0, 0.1)
		return
	_kill_tween()
	_tween = new_tween().set_parallel(true)
	match _attack:
		"sweep":
			_tween.tween_property(arm_r, "rotation", _deg(0, 100, 70), 0.18)
			_tween.tween_property(body_pivot, "rotation:y", deg_to_rad(40), 0.18)
		"slam":
			_tween.tween_property(arm_l, "rotation", _deg(-60, 0, 0), 0.12)
			_tween.tween_property(arm_r, "rotation", _deg(-60, 0, 0), 0.12)
			_tween.tween_property(body_pivot, "rotation:x", deg_to_rad(-25), 0.12)
		"boulder":
			_tween.tween_property(arm_r, "rotation", _deg(-30, 0, -20), 0.15)
		"charge":
			_charge_dir = Combat.flat_direction(global_position, _player.global_position, facing())
			state = State.CHARGE
		"summon":
			_tween.tween_property(arm_l, "rotation", _deg(60, 0, 40), 0.2)
			_tween.tween_property(arm_r, "rotation", _deg(60, 0, -40), 0.2)


func _active(delta: float) -> void:
	decelerate(delta, 12.0)
	if not _hit_done and _t >= 0.12:
		_hit_done = true
		match _attack:
			"sweep":
				_sweep()
			"slam":
				_slam()
			"boulder":
				_throw_boulder()
			"summon":
				_summon()
	if _t >= 0.4:
		_set_recover()


func _sweep() -> void:
	FX.add_trauma(0.35)
	if _player and not _player.is_dead():
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() < 5.8 and facing().dot(to_player.normalized()) > -0.1:
			_player.take_damage(sweep_damage, global_position, 11.0, "melee")


func _slam() -> void:
	FX.shockwave(_attack_point, 4.2, Color(1, 0.45, 0.2, 1))
	FX.dust(_attack_point)
	FX.add_trauma(0.6)
	Combat.damage_in_radius(get_world_3d(), _attack_point + Vector3.UP, 3.8, Combat.LAYER_PLAYER, slam_damage, 13.0, "melee")


func _throw_boulder() -> void:
	if boulder_scene == null or _player == null:
		return
	var count := 1 if phase == 1 else 3
	for i in count:
		var target := _player.global_position
		if i > 0:
			target += Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		var boulder := boulder_scene.instantiate() as Boulder
		get_tree().current_scene.add_child(boulder)
		boulder.launch(global_position + Vector3(0, 6.5, 0) + facing() * 1.5, target, 1.1)


func _summon() -> void:
	FX.add_trauma(0.3)
	_summon_cooldown = 16.0
	if grunt_scene == null:
		return
	var points := add_spawn_points.duplicate()
	points.shuffle()
	for i in mini(2, points.size()):
		var grunt := grunt_scene.instantiate() as Enemy
		grunt.position = (points[i] as Node3D).global_position
		get_parent().add_child(grunt)
		_adds.append(grunt)


func _charging(delta: float) -> void:
	var speed := 17.0
	velocity.x = _charge_dir.x * speed
	velocity.z = _charge_dir.z * speed
	face_direction(_charge_dir, delta, 20.0)
	if _player and not _hit_done and _player.global_position.distance_to(global_position) < 2.6:
		_hit_done = true
		_player.take_damage(charge_damage, global_position, 14.0, "melee")
	var hit_wall := get_slide_collision_count() > 0 and _t > 0.15
	if hit_wall:
		for i in get_slide_collision_count():
			var collider := get_slide_collision(i).get_collider()
			if not (collider is CharacterBody3D) and absf(get_slide_collision(i).get_normal().y) < 0.5:
				# Slammed into a wall: dazed.
				FX.add_trauma(0.6)
				FX.dust(global_position + _charge_dir * 2.0 + Vector3.UP)
				_stagger()
				return
	if _t >= 1.3:
		_set_recover()


func _spawn_fire_patch(at: Vector3) -> void:
	var patch := FirePatch.new()
	patch.damage = fire_damage
	get_tree().current_scene.add_child(patch)
	patch.global_position = Vector3(at.x, global_position.y, at.z)


func _living_adds() -> int:
	var alive: Array[Node] = []
	for add in _adds:
		if is_instance_valid(add) and not (add as Enemy).is_dead():
			alive.append(add)
	_adds = alive
	return _adds.size()


func _set_recover() -> void:
	state = State.RECOVER
	_t = 0.0
	_cooldown = randf_range(0.8, 1.6)
	eye_mat.emission_energy_multiplier = 3.0
	_rest_pose(0.6)


func _set_idle() -> void:
	state = State.IDLE
	_t = 0.0
	body_pivot.rotation = Vector3.ZERO


func _stagger() -> void:
	state = State.STAGGER
	_t = 0.0
	_poise_damage = 0.0
	eye_mat.emission_energy_multiplier = 1.0
	if model:
		model.play("HurtIdle", 1.0, 0.2)
		_anim_lock = 2.8
		return
	_kill_tween()
	_tween = new_tween().set_parallel(true)
	_tween.tween_property(body_pivot, "rotation:x", deg_to_rad(-35), 0.3)
	_tween.tween_property(body_pivot, "position:y", 1.6, 0.3)
	_tween.tween_property(arm_l, "rotation", _deg(-20, 0, 20), 0.3)
	_tween.tween_property(arm_r, "rotation", _deg(-20, 0, -20), 0.3)


func _roar(knockback_player: bool) -> void:
	state = State.ROAR
	_t = 0.0
	eye_mat.emission_energy_multiplier = 12.0
	_rest_pose(0.2)
	act("Spawn", 1.6)
	FX.shockwave(global_position, 10.0, Color(1, 0.3, 0.1, 0.9))
	FX.add_trauma(0.7)
	if knockback_player:
		Combat.damage_in_radius(get_world_3d(), global_position + Vector3.UP, 7.0, Combat.LAYER_PLAYER, 5.0, 16.0, "melee")


func _accepts_damage(_kind: String, _from_position: Vector3) -> bool:
	return state not in [State.DORMANT, State.ENTERING, State.ROAR, State.DYING]


func take_damage(amount: float, from_position: Vector3, knockback: float, kind: String = "") -> bool:
	if state == State.STAGGER:
		amount *= 1.5
	if kind == "takedown":
		amount = 40.0
	return super.take_damage(amount, from_position, knockback, kind)


func _on_hurt(amount: float, _from_position: Vector3, _knockback: float, _kind: String) -> void:
	var new_phase := 1
	if health < max_health * 0.33:
		new_phase = 3
	elif health < max_health * 0.66:
		new_phase = 2
	if new_phase != phase:
		phase = new_phase
		phase_changed.emit(phase)
		_roar(true)
		return
	if state == State.STAGGER:
		return
	_poise_damage += amount
	_poise_decay_wait = 2.0
	if _poise_damage >= poise and state in [State.IDLE, State.RECOVER, State.WINDUP]:
		_stagger()


func die(_kind: String = "") -> void:
	if _dead:
		return
	_dead = true
	state = State.DYING
	remove_from_group("enemies")
	remove_from_group("targetable")
	collision_layer = 0
	died.emit(self)
	# Clear her summons.
	for add in _adds:
		if is_instance_valid(add) and not (add as Enemy).is_dead():
			(add as Enemy).die("astra")
	FX.hitstop(0.35)
	FX.add_trauma(1.0)
	_kill_tween()
	_tween = create_tween()
	if model:
		act("Die1", 1.4)
		_tween.tween_interval(1.2)
	else:
		_tween.tween_property(body_pivot, "rotation:x", deg_to_rad(-80), 1.2).set_ease(Tween.EASE_IN)
	for i in 6:
		_tween.parallel().tween_callback(func() -> void:
			FX.ash_burst(global_position + Vector3(randf_range(-1.5, 1.5), randf_range(1.0, 5.0), randf_range(-1.5, 1.5)))).set_delay(0.2 * i)
	_tween.tween_callback(func() -> void:
		FX.explosion(global_position + Vector3.UP * 2.0, 6.0)
		FX.ash_burst(global_position + Vector3.UP * 3.0)
		visual.visible = false
		defeated.emit())


func _rest_pose(duration: float) -> void:
	_kill_tween()
	if model:
		return
	_tween = new_tween().set_parallel(true)
	_tween.tween_property(arm_l, "rotation", Vector3.ZERO, duration)
	_tween.tween_property(arm_r, "rotation", Vector3.ZERO, duration)
	_tween.tween_property(body_pivot, "rotation", Vector3.ZERO, duration)
	_tween.tween_property(body_pivot, "position:y", 3.0, duration)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()


func _deg(x: float, y: float, z: float) -> Vector3:
	return Vector3(deg_to_rad(x), deg_to_rad(y), deg_to_rad(z))
