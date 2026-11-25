class_name Tataka
extends Enemy
## Boss: Tataka, the demoness of the forest, who rides the storm.
## A long fight in five stages, each a fifth of her health. Burst damage can't
## skip a stage: her health stops at the line and she changes (invulnerable).
##   1 The Demoness   on the ground: sweeps, combos, slams, a stomp if Rama
##                    hides behind her, boulder throws, leaps across the arena.
##   2 Storm-Rider    takes to the sky between ground bouts: dives on Rama
##                    (her shadow hunts him first), swoops low across the arena,
##                    drops burning stones from the clouds, hurls demon fire.
##                    Enough arrows knock her out of the sky; punish the crash.
##   3 The Brood      grounded and quicker: longer combos, delayed slams, charges,
##                    and rakshasas called to her side.
##   4 Maya           hides in the storm clouds, unseen and untouchable. Lightning
##                    shows her for a moment; she also shows herself to attack.
##   5 Fury           enraged: everything at once, demon fire on the ground, short
##                    flights for a dive. At the end she falls to her knees and
##                    waits for Rama's final blow (takedown).
## Every attack has a wind-up and a telegraph on the ground. Ground poise: deal
## enough damage quickly and she staggers. Air poise: arrows bring her down.

signal stage_changed(stage: int)
signal finisher_ready
signal defeated

enum State {
	DORMANT, ENTERING, IDLE, WINDUP, ACTIVE, RECOVER, STAGGER, TRANSITION, CHARGE, LEAP,
	TAKEOFF, HOVER, AIR_WINDUP, AIR_ACTIVE, AIR_RECOVER, DIVE, SWOOP, FALLING, CRASHED,
	LANDING, FINISHER, DYING,
}

const STAGE_COUNT := 5
const STAGE_NAMES := ["", "The Demoness", "Storm-Rider", "The Brood", "Maya", "Fury"]
## States where a script moves her along a path (no gravity, no collisions).
const PATH_STATES := [State.LEAP, State.TAKEOFF, State.DIVE, State.SWOOP, State.FALLING, State.LANDING]
const AIR_STATES := [State.HOVER, State.AIR_WINDUP, State.AIR_ACTIVE, State.AIR_RECOVER]

@export var grunt_scene: PackedScene
@export var boulder_scene: PackedScene
@export_group("Damage")
@export var sweep_damage := 27.0
@export var slam_damage := 38.0
@export var stomp_damage := 22.0
@export var leap_damage := 36.0
@export var charge_damage := 34.0
@export var dive_damage := 40.0
@export var swoop_damage := 30.0
@export var orb_damage := 18.0
@export var fire_damage := 11.0
@export_group("Poise")
## Damage needed (within a few seconds) to knock her down on the ground.
@export var poise := 180.0
## Damage needed (within a few seconds) to knock her out of the sky, by stage.
@export var air_poise := 110.0
@export var hidden_air_poise := 70.0
@export_group("Flight")
@export var hover_height := 7.5
## Height of her hiding place in the clouds (stage 4).
@export var hidden_height := 24.0
## How far from Rama she circles while flying.
@export var hover_distance := 15.0
## Seconds on the ground before flying again (stages 2 and 5).
@export var ground_bout := 14.0
@export var arena_center := Vector3(0, 0, -265)
## She keeps her landings and hovering inside this box around the center.
@export var arena_half_extents := Vector2(18, 22)

var state := State.DORMANT
var stage := 1
var boss_name := "TATAKA"
var airborne := false
var hidden := false
var add_spawn_points: Array[Node3D] = []
## Points to keep landings away from (the yagna altar), with radius.
var keep_clear: Array[Vector3] = []
var keep_clear_radius := 4.5

var _t := 0.0
var _attack := ""
var _combo: Array[String] = []
var _windup := 0.8
var _recover_time := 1.0
var _cooldown := 2.0
var _air_cooldown := 2.0
var _summon_cooldown := 0.0
var _fire_cooldown := 4.0
var _mode_time := 0.0
var _air_attacks_left := 0
var _reveal_cooldown := 4.0
var _reveal_left := 0.0
var _poise_damage := 0.0
var _poise_decay_wait := 0.0
var _air_poise_damage := 0.0
var _air_poise_wait := 0.0
var _hit_done := false
var _locked := false
var _lifted := false
var _attack_point := Vector3.ZERO
var _charge_dir := Vector3.ZERO
var _orbit_angle := 0.0
var _orbit_dir := 1.0
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _flight_time := 1.0
var _arc := 0.0
var _swoop_dir := Vector3.FORWARD
var _pending_stage := 0
var _finisher_pending := false
var _marker: Node3D
var _adds: Array[Node] = []
var _tween: Tween
var _trail: CPUParticles3D

var eye_mat: StandardMaterial3D
var _body_shape: CapsuleShape3D
var _ground_radius := 1.3


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
	_attach_features()
	_build_trail()
	var collision := $CollisionShape3D as CollisionShape3D
	_body_shape = (collision.shape as CapsuleShape3D).duplicate()
	collision.shape = _body_shape
	_ground_radius = _body_shape.radius


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


## Storm cloud that streams off her while she flies.
func _build_trail() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = tex
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	quad.material = mat
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	ramp.colors = PackedColorArray([Color(0.2, 0.12, 0.22, 0.0), Color(0.12, 0.1, 0.14, 0.7), Color(0.05, 0.05, 0.07, 0.0)])
	_trail = CPUParticles3D.new()
	_trail.mesh = quad
	_trail.amount = 36
	_trail.lifetime = 1.4
	_trail.local_coords = false
	_trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_trail.emission_sphere_radius = 1.6
	_trail.position = Vector3(0, 2.2, 0)
	_trail.gravity = Vector3(0, 0.6, 0)
	_trail.initial_velocity_min = 0.2
	_trail.initial_velocity_max = 0.8
	_trail.spread = 180.0
	_trail.scale_amount_min = 0.7
	_trail.scale_amount_max = 1.3
	_trail.color_ramp = ramp
	_trail.emitting = false
	add_child(_trail)


func speed_scale() -> float:
	return [1.0, 1.0, 1.0, 1.12, 1.15, 1.3][stage]


## Health at which `for_stage` ends (stage 5 ends at zero).
func stage_floor(for_stage: int) -> float:
	return max_health * (1.0 - float(for_stage) / STAGE_COUNT)


func stage_name() -> String:
	return STAGE_NAMES[stage]


## Begin the fight part-way through (resuming from a stage checkpoint).
func start_at_stage(start_stage: int) -> void:
	stage = clampi(start_stage, 1, STAGE_COUNT)
	health = stage_floor(stage - 1)


func is_targetable() -> bool:
	return super.is_targetable() and not hidden and state != State.DORMANT


## Leap into the arena from the storm.
func enter_arena() -> void:
	visible = true
	state = State.ENTERING
	_set_presence(true, true)
	_t = 0.0
	var landing := global_position
	global_position = landing + Vector3(0, 18, -6)
	reset_physics_interpolation()
	model.play("HeavyFalling", 1.0, 0.1)
	var tween := new_tween()
	tween.tween_property(self, "global_position", landing, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_callback(func() -> void:
		FX.shockwave(landing, 8.0, Color(1, 0.4, 0.2, 1))
		FX.explosion(landing, 6.0)
		Sfx.play("slam", landing, 4.0)
		FX.add_trauma(0.9)
		act("LandHard", 1.6)
		Combat.damage_in_radius(get_world_3d(), landing + Vector3.UP, 4.0, Combat.LAYER_PLAYER, 10.0, 14.0, "melee"))


# --- Main loop ---------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == State.DORMANT:
		return
	_t += delta
	_tick_timers(delta)
	var on_path := state in PATH_STATES
	if not airborne and not on_path and state != State.ENTERING:
		apply_gravity(delta)

	match state:
		State.ENTERING:
			if _t >= 1.6:
				_roar(false)
		State.IDLE:
			_idle(delta)
		State.WINDUP:
			decelerate(delta, 10.0)
			if _attack in ["sweep", "charge", "stomp"]:
				face_toward(_player.global_position, delta, 3.0)
			if _t >= _windup:
				_begin_active()
		State.ACTIVE:
			_active(delta)
		State.CHARGE:
			_charging(delta)
		State.RECOVER:
			decelerate(delta, 8.0)
			if _t >= _recover_time / speed_scale():
				_after_ground_recover()
		State.STAGGER:
			decelerate(delta, 6.0)
			if _t >= 2.8:
				_set_idle()
		State.CRASHED:
			decelerate(delta, 8.0)
			if _t >= 4.0:
				_after_ground_recover()
		State.TRANSITION:
			decelerate(delta, 10.0)
			if _t >= 2.0:
				_after_roar()
		State.FINISHER:
			decelerate(delta, 10.0)
		State.LEAP:
			_leaping()
		State.TAKEOFF:
			_taking_off(delta)
		State.HOVER:
			_hover(delta)
		State.AIR_WINDUP:
			_air_windup(delta)
		State.AIR_ACTIVE:
			_hover_drift(delta, 0.5)
			if _t >= 1.6:
				_set_air_recover(1.2)
		State.AIR_RECOVER:
			_hover_drift(delta, 1.0)
			if _t >= _recover_time / speed_scale():
				_enter_hover()
		State.DIVE:
			_diving()
		State.SWOOP:
			_swooping(delta)
		State.FALLING, State.LANDING:
			_falling()
		State.DYING:
			pass

	if not airborne and (state == State.IDLE or state == State.RECOVER):
		locomote(delta, "HeavyIdle", "HeavyWalking", "HeavyWalking")
	elif airborne and state in AIR_STATES:
		_anim_lock -= delta
		if _anim_lock <= 0.0:
			model.play("HeavyFalling", 0.6, 0.25)
	if not on_path and state != State.ENTERING and state != State.DYING:
		move_and_slide()


func _tick_timers(delta: float) -> void:
	_cooldown -= delta * speed_scale()
	_air_cooldown -= delta * speed_scale()
	_summon_cooldown -= delta
	_fire_cooldown -= delta
	_mode_time += delta
	_poise_decay_wait -= delta
	if _poise_decay_wait <= 0.0:
		_poise_damage = maxf(_poise_damage - poise * 0.25 * delta, 0.0)
	_air_poise_wait -= delta
	if _air_poise_wait <= 0.0:
		_air_poise_damage = maxf(_air_poise_damage - air_poise * 0.12 * delta, 0.0)


# --- Ground fighting ---------------------------------------------------------

func _idle(delta: float) -> void:
	if _player == null or _player.is_dead():
		decelerate(delta, 8.0)
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	face_toward(_player.global_position, delta, 3.0 * speed_scale())

	if stage >= 5 and _fire_cooldown <= 0.0:
		_fire_cooldown = 4.5
		_spawn_fire_patch(_player.global_position)
	if stage == 3 and _summon_cooldown <= 0.0 and _living_adds() < 2:
		_begin("summon")
		return
	if _wants_to_fly():
		_takeoff()
		return
	if _cooldown <= 0.0:
		var behind := dist > 0.01 and facing().dot(to_player / dist) < -0.35
		if dist < 4.5 and behind:
			_begin("stomp")
		elif dist < 5.5:
			_begin_melee_string()
		elif dist < 9.0:
			_begin("slam") if randf() < 0.6 or stage < 3 else _begin("leap")
		elif stage >= 3 and randf() < 0.4:
			_begin("charge")
		elif randf() < 0.45:
			_begin("leap")
		else:
			_begin("boulder")
		return
	var desired := Vector3.ZERO
	if dist > 4.5:
		desired = path_direction(_player.global_position, delta, to_player / maxf(dist, 0.01)) * move_speed * speed_scale()
	_steer(desired, delta, 6.0)


func _wants_to_fly() -> bool:
	if stage == 4:
		return true
	return (stage == 2 or stage == 5) and _mode_time > ground_bout


## A melee string: one to three swings, longer in later stages.
func _begin_melee_string() -> void:
	_combo.clear()
	var roll := randf()
	match stage:
		1, 2:
			if roll < 0.45:
				_combo.assign(["slam"])
		3, 4:
			if roll < 0.55:
				_combo.assign(["sweep", "slam"])
			elif roll < 0.85:
				_combo.assign(["slam"])
		_:
			_combo.assign(["sweep", "slam"] if roll < 0.7 else ["sweep", "stomp"])
	_begin("sweep" if randf() < 0.6 else "slam")


func _begin(attack: String, quick := false) -> void:
	_attack = attack
	state = State.WINDUP
	_t = 0.0
	_hit_done = false
	eye_mat.emission_energy_multiplier = 9.0
	var base: float = {"sweep": 0.75, "slam": 1.0, "stomp": 0.6, "boulder": 0.9, "charge": 0.9,
		"summon": 1.0, "leap": 0.75}.get(attack, 0.8)
	if attack == "slam" and stage >= 3:
		base *= randf_range(0.85, 1.6)  # a delayed slam, to catch an early dodge
	if quick:
		base *= 0.65
	_windup = base / speed_scale()
	match attack:
		"sweep":
			act("HeavyCharge", _windup + 0.1)
			FX.telegraph(global_position + facing() * 2.5, 5.0, _windup)
		"slam":
			_attack_point = global_position + facing() * 3.5
			act("HeavyCharge", _windup + 0.1)
			FX.telegraph(_attack_point, 3.8, _windup)
		"stomp":
			act("HeavyCharge", _windup + 0.1)
			FX.telegraph(global_position, 4.4, _windup)
		"boulder":
			_attack_point = _player.global_position
			act("ThrowR", _windup + 0.55)  # the throw lands as the boulder leaves her hand
		"charge":
			act("HeavyCharge", _windup + 0.1)
		"summon":
			act("Spawn", _windup + 0.6)
		"leap":
			# The landing spot is fixed now, so Rama can see it and get clear.
			_attack_point = _landing_spot(_player.global_position)
			act("HeavyCharge", _windup + 0.1)
			FX.telegraph(_attack_point, 4.4, _windup + 1.0 / speed_scale())


func _begin_active() -> void:
	state = State.ACTIVE
	_t = 0.0
	match _attack:
		"sweep":
			act("Heavy1", 0.75)
		"slam":
			act("Heavy2", 0.7)
		"stomp":
			act("Heavy2", 0.5)
		"charge":
			_charge_dir = Combat.flat_direction(global_position, _player.global_position, facing())
			state = State.CHARGE
			_anim_lock = 0.0
			model.play("Sprint", 1.0, 0.1)
		"leap":
			state = State.LEAP
			_from = global_position
			_to = _attack_point
			_flight_time = 1.0 / speed_scale()
			_arc = 9.0
			collision_mask = 0
			face_direction(Combat.flat_direction(_from, _to, facing()), 1.0, 100.0)
			model.play("HeavyFalling", 1.0, 0.1)
			FX.dust(global_position)
			FX.add_trauma(0.25)


func _active(delta: float) -> void:
	decelerate(delta, 12.0)
	if not _hit_done and _t >= 0.12:
		_hit_done = true
		match _attack:
			"sweep":
				_sweep()
			"slam":
				_slam()
			"stomp":
				_stomp()
			"boulder":
				_throw_boulder()
			"summon":
				_summon()
	if _t >= 0.4:
		if not _combo.is_empty():
			_begin(_combo.pop_front(), true)
			return
		var rest: float = {"sweep": 0.9, "slam": 1.3, "stomp": 0.8, "boulder": 0.9, "summon": 0.8}.get(_attack, 1.0)
		_set_recover(rest)


func _sweep() -> void:
	FX.add_trauma(0.35)
	Sfx.play("swoop", global_position + Vector3.UP * 3.0, -4.0, 0.15)
	if _player and not _player.is_dead():
		var to_player := _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() < 5.8 and facing().dot(to_player.normalized()) > -0.1:
			_player.take_damage(sweep_damage, global_position, 11.0, "melee")


func _slam() -> void:
	Sfx.play("slam", _attack_point, 2.0)
	FX.shockwave(_attack_point, 4.2, Color(1, 0.45, 0.2, 1))
	FX.dust(_attack_point)
	FX.add_trauma(0.6)
	Combat.damage_in_radius(get_world_3d(), _attack_point + Vector3.UP, 3.8, Combat.LAYER_PLAYER, slam_damage, 13.0, "melee")


func _stomp() -> void:
	Sfx.play("slam", global_position, 0.0)
	FX.shockwave(global_position, 4.6, Color(1, 0.45, 0.2, 1))
	FX.dust(global_position)
	FX.add_trauma(0.5)
	Combat.damage_in_radius(get_world_3d(), global_position + Vector3.UP, 4.4, Combat.LAYER_PLAYER, stomp_damage, 15.0, "melee")


func _throw_boulder() -> void:
	if boulder_scene == null or _player == null:
		return
	var count := 1 if stage < 3 else 3
	for i in count:
		var target := _player.global_position
		if i > 0:
			target += Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		var boulder := boulder_scene.instantiate() as Boulder
		get_tree().current_scene.add_child(boulder)
		boulder.launch(global_position + Vector3(0, 6.5, 0) + facing() * 1.5, target, 1.1)


func _summon() -> void:
	FX.add_trauma(0.3)
	Sfx.play("roar", global_position + Vector3.UP * 5.0, 0.0, 0.1)
	_summon_cooldown = 18.0
	if grunt_scene == null:
		return
	var points := add_spawn_points.duplicate()
	points.shuffle()
	for i in mini(3, points.size()):
		var grunt := grunt_scene.instantiate() as Enemy
		grunt.position = (points[i] as Node3D).global_position
		get_parent().add_child(grunt)
		FX.spawn_puff(grunt.global_position)
		_adds.append(grunt)


func _charging(delta: float) -> void:
	var speed := 17.0
	velocity.x = _charge_dir.x * speed
	velocity.z = _charge_dir.z * speed
	face_direction(_charge_dir, delta, 20.0)
	if _player and not _hit_done and _player.global_position.distance_to(global_position) < 2.6:
		_hit_done = true
		_player.take_damage(charge_damage, global_position, 14.0, "melee")
	if get_slide_collision_count() > 0 and _t > 0.15:
		for i in get_slide_collision_count():
			var collider := get_slide_collision(i).get_collider()
			if not (collider is CharacterBody3D) and absf(get_slide_collision(i).get_normal().y) < 0.5:
				# Slammed into a wall: dazed.
				FX.add_trauma(0.6)
				FX.dust(global_position + _charge_dir * 2.0 + Vector3.UP)
				_stagger()
				return
	if _t >= 1.3:
		_set_recover(1.0)


func _leaping() -> void:
	var k := _follow_path(0)
	if k >= 1.0:
		_touch_down()
		_impact(global_position, 4.2, leap_damage, 0.8)
		act("LandHard", 1.4)
		_set_recover(1.6)


func _spawn_fire_patch(at: Vector3) -> void:
	var patch := FirePatch.new()
	patch.damage = fire_damage
	get_tree().current_scene.add_child(patch)
	patch.global_position = Vector3(at.x, Combat.ground_height(get_world_3d(), at, global_position.y), at.z)


func _living_adds() -> int:
	var alive: Array[Node] = []
	for add in _adds:
		if is_instance_valid(add) and not (add as Enemy).is_dead():
			alive.append(add)
	_adds = alive
	return _adds.size()


func _clear_adds() -> void:
	for add in _adds:
		if is_instance_valid(add) and not (add as Enemy).is_dead():
			(add as Enemy).die("astra")
	_adds.clear()


func _set_recover(duration: float) -> void:
	state = State.RECOVER
	_t = 0.0
	_recover_time = duration
	_cooldown = randf_range(0.8, 1.6)
	eye_mat.emission_energy_multiplier = 3.0


func _set_idle() -> void:
	state = State.IDLE
	_t = 0.0


## After a ground recovery or a crash: back to fighting, or up into the sky.
func _after_ground_recover() -> void:
	if stage == 4:
		_takeoff()
	else:
		_set_idle()


func _stagger() -> void:
	state = State.STAGGER
	_t = 0.0
	_poise_damage = 0.0
	_combo.clear()
	eye_mat.emission_energy_multiplier = 1.0
	model.play("HurtIdle", 1.0, 0.2)
	_anim_lock = 2.8


# --- Flight ------------------------------------------------------------------

func _takeoff() -> void:
	state = State.TAKEOFF
	_t = 0.0
	_lifted = false
	_combo.clear()
	act("HeavyCharge", 0.5)


func _taking_off(_delta: float) -> void:
	if _t < 0.45:
		return
	if not _lifted:
		_lifted = true
		airborne = true
		collision_mask = 0
		_body_shape.radius = _ground_radius * 1.6  # a bigger target in the sky
		_set_presence(true, false)
		_from = global_position
		_to = _hover_point()
		_flight_time = 0.9
		_t = 0.45
		_trail.emitting = true
		model.play("HeavyFalling", 1.0, 0.1)
		FX.shockwave(global_position, 6.0, Color(0.6, 0.6, 0.8, 0.8))
		FX.dust(global_position)
		FX.add_trauma(0.35)
		Sfx.play("swoop", global_position, 0.0, 0.05)
	var k := clampf((_t - 0.45) / _flight_time, 0.0, 1.0)
	global_position = _from.lerp(_to, 1.0 - (1.0 - k) * (1.0 - k))
	if k >= 1.0:
		_air_attacks_left = [0, 0, randi_range(4, 5), 0, 999, randi_range(1, 2)][stage]
		_air_cooldown = 1.2
		_reveal_cooldown = randf_range(2.5, 4.0)
		velocity = Vector3.ZERO
		if stage == 4:
			_set_hidden(true)
		_enter_hover()


func _enter_hover() -> void:
	state = State.HOVER
	_t = 0.0
	_air_cooldown = maxf(_air_cooldown, randf_range(1.6, 2.6))
	if stage == 4 and not hidden and _reveal_left <= 0.0:
		_set_hidden(true)


func _hover(delta: float) -> void:
	_hover_drift(delta, 1.0)
	if _player == null or _player.is_dead():
		return
	if stage == 4:
		if hidden:
			_reveal_cooldown -= delta
			if _reveal_cooldown <= 0.0:
				_reveal()
				return
		else:
			# Shown by lightning: a short window to shoot her.
			_reveal_left -= delta
			if _reveal_left <= 0.0:
				_set_hidden(true)
				_reveal_cooldown = randf_range(4.0, 6.0)
			return
	if _air_cooldown <= 0.0:
		_choose_air_attack()


## Drift toward her circling point near Rama, facing him.
func _hover_drift(delta: float, follow: float) -> void:
	# Slow enough that a well-aimed arrow lands without leading her.
	_orbit_angle += delta * 0.1 * _orbit_dir
	var target := _hover_point()
	target.y += sin(_t * 1.6) * 0.4
	var want := (target - global_position) * 0.8 * follow
	if want.length() > 4.5:
		want = want.normalized() * 4.5
	velocity = velocity.lerp(want, 1.0 - exp(-2.0 * delta))
	if _player:
		face_toward(_player.global_position, delta, 4.0)


func _hover_point() -> Vector3:
	var around := _player.global_position if _player else arena_center
	# Lean the circle toward the arena's middle, so with Rama near a wall she
	# stays in front of him (high overhead is out of the camera's reach).
	var offset := Vector3(sin(_orbit_angle), 0.0, cos(_orbit_angle))
	var inward := Vector3(arena_center.x - around.x, 0.0, arena_center.z - around.z)
	if inward.length() > 4.0:
		offset = (offset + inward.normalized() * 0.9).normalized()
	var point := around + offset * hover_distance
	point = _clamp_to_arena(point)
	point.y = arena_center.y + (hidden_height if hidden else hover_height)
	return point


func _choose_air_attack() -> void:
	if _air_attacks_left <= 0:
		_begin_air("dive")  # every flight ends coming down on Rama
		return
	_air_attacks_left -= 1
	var weights: Dictionary = {
		2: {"orbs": 3, "stones": 3, "swoop": 3, "dive": 1},
		4: {"stones": 3, "dive": 3, "swoop": 3, "orbs": 2},
		5: {"stones": 1, "orbs": 1},
	}.get(stage, {"orbs": 1})
	var total := 0
	for w in weights.values():
		total += w
	var roll := randi() % total
	for attack in weights:
		roll -= weights[attack]
		if roll < 0:
			_begin_air(attack)
			return


func _begin_air(attack: String) -> void:
	_attack = attack
	state = State.AIR_WINDUP
	_t = 0.0
	_hit_done = false
	_locked = false
	eye_mat.emission_energy_multiplier = 10.0
	match attack:
		"orbs":
			_windup = 0.8 / speed_scale()
			act("ThrowR", _windup + 0.5)
		"stones":
			_windup = 1.0 / speed_scale()
			act("Spawn", _windup + 0.8)
		"dive":
			# Her shadow hunts Rama, then stops: that's the moment to move.
			_windup = [1.4, 1.4, 1.4, 1.3, 1.1, 1.0][stage] + 0.5
			_marker = FX.tracking_marker(4.4)
			_marker.global_position = _ground_under(_player.global_position)
		"swoop":
			_windup = 1.5 / speed_scale()
			_swoop_dir = Combat.flat_direction(global_position, _player.global_position, facing())
			var center := _player.global_position
			_from = global_position
			_to = center - _swoop_dir * 22.0
			_to.y = arena_center.y + 9.5
			_attack_point = center
			FX.telegraph_line(_ground_under(center - _swoop_dir * 12.0), _ground_under(center + _swoop_dir * 12.0), 4.5, _windup)


func _air_windup(delta: float) -> void:
	match _attack:
		"dive":
			var lock_at := _windup - 0.5
			if _t < lock_at:
				_marker.global_position = _marker.global_position.lerp(_ground_under(_player.global_position), 1.0 - exp(-10.0 * delta))
				var above := _marker.global_position + Vector3.UP * (hover_height + 3.0) - _swoop_back(5.0)
				if hidden:
					above.y = arena_center.y + hidden_height
				velocity = velocity.lerp((above - global_position) * 2.5, 1.0 - exp(-4.0 * delta))
			elif not _locked:
				_locked = true
				velocity = Vector3.ZERO
				var ring := _marker.get_node("Ring") as MeshInstance3D
				((ring.mesh as TorusMesh).material as StandardMaterial3D).albedo_color = Color(1, 0.85, 0.6, 0.9)
				if hidden:
					_set_hidden(false)
					_strike_lightning(global_position, _marker.global_position)
				act("HeavyJumpAttack", 0.9)
				Sfx.play("dive_warn", global_position, 4.0, 0.0)
			else:
				velocity = velocity.lerp(Vector3.ZERO, 1.0 - exp(-8.0 * delta))
			if _player:
				face_toward(_marker.global_position, delta, 6.0)
		"swoop":
			var k := clampf(_t / (_windup * 0.8), 0.0, 1.0)
			global_position = _from.lerp(_to, k * k * (3.0 - 2.0 * k))
			velocity = Vector3.ZERO
			face_direction(_swoop_dir, delta, 8.0)
		_:
			_hover_drift(delta, 0.6)
	if _t >= _windup:
		_begin_air_active()


func _swoop_back(amount: float) -> Vector3:
	return Combat.flat_direction(global_position, _player.global_position, facing()) * amount if _player else Vector3.ZERO


func _begin_air_active() -> void:
	_t = 0.0
	match _attack:
		"orbs":
			_throw_orbs()
			_set_air_recover(1.0)
		"stones":
			state = State.AIR_ACTIVE
			_rain_stones()
		"dive":
			state = State.DIVE
			_from = global_position
			_to = _marker.global_position
			_flight_time = 0.32
			_arc = 0.0
			model.play("HeavyJumpAttack", 1.0, 0.05)
			tilt_model(0.5, 0.15)
		"swoop":
			if hidden:
				_set_hidden(false)
				_strike_lightning(global_position, _ground_under(_attack_point))
			state = State.SWOOP
			Sfx.play("swoop", _attack_point + Vector3.UP * 2.0, 6.0, 0.05)
			_from = global_position
			_to = _attack_point + _swoop_dir * 22.0
			_flight_time = 1.3 / speed_scale()
			model.play("Sprint", 1.4, 0.1)
			tilt_model(0.9, 0.2)


func _throw_orbs() -> void:
	if _player == null:
		return
	Sfx.play("fire_whoosh", global_position + Vector3.UP * 5.0, 2.0)
	var count := 1 if stage == 2 else 3
	var hand := global_position + Vector3.UP * 5.0 + facing() * 1.5
	var aim := (_player.global_position + Vector3.UP - hand).normalized()
	for i in count:
		var spread := 0.0 if count == 1 else (float(i) - (count - 1) * 0.5) * 0.3
		var orb := DemonOrb.new()
		orb.damage = orb_damage
		orb.leaves_fire = stage >= 5
		orb.fire_damage = fire_damage
		get_tree().current_scene.add_child(orb)
		orb.launch(hand, aim.rotated(Vector3.UP, spread), _player if i == (count - 1) / 2 else null)


## Burning stones out of the storm, one after another, the first right on Rama.
func _rain_stones() -> void:
	if boulder_scene == null:
		return
	var count: int = [0, 0, 6, 0, 9, 7][stage]
	Sfx.play("growl", global_position + Vector3.UP * 5.0, 6.0, 0.0)
	var tween := new_tween()
	for i in count:
		tween.tween_callback(func() -> void:
			if _player == null or not is_inside_tree():
				return
			var target := _player.global_position
			if i > 0:
				target += Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
			target = _ground_under(_clamp_to_arena(target))
			var boulder := boulder_scene.instantiate() as Boulder
			get_tree().current_scene.add_child(boulder)
			boulder.launch(target + Vector3(randf_range(-4, 4), 30.0, randf_range(-4, 4)), target, 1.3, 0.0))
		tween.tween_interval(0.22)
	FX.add_trauma(0.25)


func _diving() -> void:
	var k := clampf(_t / _flight_time, 0.0, 1.0)
	global_position = _from.lerp(_to, k * k)
	if k >= 1.0:
		_free_marker()
		_touch_down()
		tilt_model(0.0, 0.2)
		_impact(global_position, 4.4, dive_damage, 0.85)
		act("LandHard", 2.0)
		_mode_time = 0.0
		_set_recover(2.4)


func _swooping(delta: float) -> void:
	var k := clampf(_t / _flight_time, 0.0, 1.0)
	var pos := _from.lerp(_to, k)
	var low := absf(k - 0.5) * 2.0
	pos.y = arena_center.y + 2.4 + 7.0 * low * low
	global_position = pos
	face_direction(_swoop_dir, delta, 10.0)
	if not _hit_done and _player and not _player.is_dead():
		if (global_position + Vector3.UP * 2.5).distance_to(_player.global_position + Vector3.UP) < 3.2:
			_hit_done = true
			_player.take_damage(swoop_damage, global_position - _swoop_dir * 2.0, 14.0, "melee")
	if k >= 1.0:
		tilt_model(0.0, 0.4)
		velocity = Vector3.ZERO
		_set_air_recover(0.9)


func _set_air_recover(duration: float) -> void:
	state = State.AIR_RECOVER
	_t = 0.0
	_recover_time = duration
	eye_mat.emission_energy_multiplier = 3.0


## Stage 4: lightning shows where she lurks, for a moment.
func _reveal() -> void:
	var spot := _hover_point()
	spot.y = arena_center.y + hover_height
	_set_hidden(false)
	global_position = spot
	reset_physics_interpolation()
	velocity = Vector3.ZERO
	_reveal_left = 2.8
	eye_mat.emission_energy_multiplier = 14.0
	_strike_lightning(spot + Vector3.UP * 4.0, _ground_under(spot + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))))


func _set_hidden(value: bool) -> void:
	if hidden == value:
		return
	hidden = value
	visual.visible = not value
	collision_layer = 0 if value else Combat.LAYER_ENEMY
	_set_presence(not value, false)
	FX.spawn_puff(global_position + Vector3.UP * 2.0)


## Knocked out of the sky by arrows: she tumbles down into the arena.
func _shot_down() -> void:
	_free_marker()
	_air_poise_damage = 0.0
	_set_hidden(false)
	state = State.FALLING
	_t = 0.0
	_from = global_position
	_to = _landing_spot(global_position)
	_flight_time = clampf((global_position.y - _to.y) / 9.0, 0.6, 1.4)
	_arc = 1.5
	tilt_model(-0.7, 0.3)
	model.play("HeavyFalling", 1.6, 0.1)
	FX.hitstop(0.12)
	FX.add_trauma(0.5)
	eye_mat.emission_energy_multiplier = 1.0


## Back to the ground under her, without attacking (stage changes).
func _land_now() -> void:
	_free_marker()
	_set_hidden(false)
	state = State.LANDING
	_t = 0.0
	_from = global_position
	_to = _landing_spot(global_position)
	_flight_time = clampf((global_position.y - _to.y) / 12.0, 0.4, 1.2)
	_arc = 1.0
	tilt_model(0.0, 0.3)


func _falling() -> void:
	var k := _follow_path(0)
	if k < 1.0:
		return
	var was_landing := state == State.LANDING
	state = State.CRASHED  # off the path before anything else decides what's next
	_t = 0.0
	_touch_down()
	tilt_model(0.0, 0.2)
	if was_landing:
		FX.shockwave(global_position, 6.0, Color(1, 0.4, 0.2, 0.9))
		FX.add_trauma(0.5)
		act("LandHard", 1.0)
		_after_landing()
		return
	# Crashed down.
	_impact(global_position, 3.0, 12.0, 0.9)
	FX.explosion(global_position + Vector3.UP, 4.0)
	if _finisher_pending:
		_begin_finisher()
		return
	_t = 0.0
	_mode_time = 0.0
	_poise_damage = 0.0
	model.play("HurtIdle", 1.0, 0.2)
	_anim_lock = 4.0


func _after_landing() -> void:
	if _finisher_pending:
		_begin_finisher()
	elif _pending_stage > 0:
		_roar_transition()
	else:
		_set_idle()


func _touch_down() -> void:
	airborne = false
	_body_shape.radius = _ground_radius
	_trail.emitting = false
	collision_mask = Combat.LAYER_WORLD
	velocity = Vector3.ZERO
	global_position.y = Combat.ground_height(get_world_3d(), global_position, global_position.y) + 0.05
	_set_presence(true, true)


## Position along the current flight path. `ease`: 0 linear.
func _follow_path(_ease: int) -> float:
	var k := clampf(_t / _flight_time, 0.0, 1.0)
	global_position = _from.lerp(_to, k) + Vector3.UP * sin(k * PI) * _arc
	return k


func _impact(at: Vector3, radius: float, damage: float, trauma: float) -> void:
	Sfx.play("slam", at, 4.0)
	FX.shockwave(at, radius + 0.5, Color(1, 0.4, 0.2, 1))
	FX.explosion(at + Vector3.UP * 0.5, radius * 0.6)
	FX.dust(at)
	FX.add_trauma(trauma)
	Combat.damage_in_radius(get_world_3d(), at + Vector3.UP, radius, Combat.LAYER_PLAYER, damage, 14.0, "melee")


func _strike_lightning(from_point: Vector3, ground: Vector3) -> void:
	var atmosphere := get_tree().get_first_node_in_group("atmosphere") as Atmosphere
	if atmosphere == null:
		return
	var cam := get_viewport().get_camera_3d()
	var dir := (from_point - cam.global_position).normalized() if cam else Vector3(0, 0.5, -1)
	atmosphere.lightning(1.0, dir, ground)


func tilt_model(angle: float, duration: float) -> void:
	var tween := new_tween()
	tween.tween_property(model, "rotation:x", angle, duration)


func _free_marker() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null


## A safe spot to come down near `near`: inside the arena, clear of the altar.
func _landing_spot(near: Vector3) -> Vector3:
	var spot := _clamp_to_arena(near)
	for point in keep_clear:
		var away := Vector3(spot.x - point.x, 0.0, spot.z - point.z)
		if away.length() < keep_clear_radius:
			var dir := away.normalized() if away.length() > 0.1 else Vector3.BACK
			spot = point + dir * keep_clear_radius
			spot.y = near.y
	return _ground_under(spot)


func _clamp_to_arena(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, arena_center.x - arena_half_extents.x, arena_center.x + arena_half_extents.x),
		point.y,
		clampf(point.z, arena_center.z - arena_half_extents.y, arena_center.z + arena_half_extents.y))


func _ground_under(point: Vector3) -> Vector3:
	return Vector3(point.x, Combat.ground_height(get_world_3d(), point, arena_center.y), point.z)


## In the lock-on/aim lists ("targetable") and the melee lists ("enemies").
func _set_presence(targetable: bool, melee: bool) -> void:
	if targetable and not hidden:
		add_to_group("targetable")
	else:
		remove_from_group("targetable")
	if melee:
		add_to_group("enemies")
	else:
		remove_from_group("enemies")
	if not hidden and state != State.DORMANT:
		collision_layer = Combat.LAYER_ENEMY


# --- Stages ------------------------------------------------------------------

func _begin_transition() -> void:
	_combo.clear()
	_poise_damage = 0.0
	_air_poise_damage = 0.0
	_free_marker()
	if airborne or state in PATH_STATES:
		_land_now()
	else:
		_roar_transition()


func _roar_transition() -> void:
	stage = _pending_stage
	_pending_stage = 0
	_mode_time = 0.0
	_cooldown = 1.0
	if stage == 4:
		_clear_adds()
	if stage == 3:
		_summon_cooldown = 0.0
	stage_changed.emit(stage)
	_roar(true)
	state = State.TRANSITION


func _roar(knockback_player: bool) -> void:
	state = State.TRANSITION
	_t = 0.0
	eye_mat.emission_energy_multiplier = 12.0
	act("Spawn", 2.0)
	Sfx.play("roar", global_position + Vector3.UP * 5.0, 6.0, 0.05)
	FX.shockwave(global_position, 10.0, Color(1, 0.3, 0.1, 0.9))
	FX.add_trauma(0.7)
	if knockback_player:
		Combat.damage_in_radius(get_world_3d(), global_position + Vector3.UP, 7.0, Combat.LAYER_PLAYER, 5.0, 16.0, "melee")


func _after_roar() -> void:
	if stage == 2 or stage == 4:
		_takeoff()
	elif stage == 3 and _summon_cooldown <= 0.0:
		_begin("summon")
	else:
		_set_idle()


## Health is gone: she drops to her knees and waits for the final blow.
func _begin_finisher() -> void:
	_finisher_pending = false
	_clear_adds()
	if airborne or state in PATH_STATES:
		_finisher_pending = true
		if state != State.FALLING:
			_shot_down()
		return
	state = State.FINISHER
	_t = 0.0
	health = 0.0
	velocity = Vector3.ZERO
	eye_mat.emission_energy_multiplier = 0.6
	model.play("HurtIdle", 0.6, 0.3)
	_anim_lock = 999.0
	_set_presence(true, true)
	finisher_ready.emit()


func can_be_taken_down(by: Node3D) -> bool:
	if state != State.FINISHER or _dead:
		return false
	var to_attacker := by.global_position - global_position
	to_attacker.y = 0.0
	return to_attacker.length() < 4.5


func receive_takedown() -> void:
	super.receive_takedown()
	collision_layer = 0  # let Rama step in close for the blow


# --- Damage ------------------------------------------------------------------

func _accepts_damage(kind: String, _from_position: Vector3) -> bool:
	if state == State.FINISHER:
		return kind == "takedown"
	if hidden:
		return false
	return state not in [State.DORMANT, State.ENTERING, State.TRANSITION, State.TAKEOFF,
		State.LANDING, State.FINISHER, State.DYING] and _pending_stage == 0 and not _finisher_pending


func take_damage(amount: float, from_position: Vector3, knockback: float, kind: String = "") -> bool:
	if _dead:
		return false
	if state == State.FINISHER:
		if kind != "takedown":
			return false
		return super.take_damage(9999.0, from_position, 0.0, kind)
	if not _accepts_damage(kind, from_position):
		return false
	if state == State.STAGGER:
		amount *= 1.5
	elif state == State.CRASHED:
		amount *= 1.6
	if kind == "takedown":
		amount = 40.0
	# A stage can't be skipped: health stops at its line.
	var floor_health := stage_floor(stage)
	if health - amount <= floor_health:
		if _player:
			_player.add_astra((health - floor_health) * astra_per_damage)
		health = floor_health
		FX.flash(visual, Color(1, 1, 1, 0.85), 0.08)
		if stage >= STAGE_COUNT:
			_begin_finisher()
		else:
			_pending_stage = stage + 1
			_begin_transition()
		return true
	return super.take_damage(amount, from_position, knockback, kind)


func _on_hurt(amount: float, _from_position: Vector3, _knockback: float, _kind: String) -> void:
	if airborne:
		if state in AIR_STATES:
			_air_poise_damage += amount
			_air_poise_wait = 3.0
			var limit := hidden_air_poise if stage == 4 else air_poise
			if _air_poise_damage >= limit:
				_shot_down()
		return
	if state == State.STAGGER or state == State.CRASHED:
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
	_clear_adds()
	_free_marker()
	FX.hitstop(0.35)
	FX.add_trauma(1.0)
	_strike_lightning(global_position + Vector3.UP * 8.0, global_position)
	Sfx.play("roar", global_position + Vector3.UP * 4.0, 8.0, 0.0)
	_kill_tween()
	_tween = create_tween()
	act("Die1", 1.4)
	_tween.tween_interval(1.2)
	for i in 8:
		_tween.parallel().tween_callback(func() -> void:
			FX.ash_burst(global_position + Vector3(randf_range(-1.5, 1.5), randf_range(1.0, 5.0), randf_range(-1.5, 1.5)))).set_delay(0.2 * i)
	_tween.tween_callback(func() -> void:
		FX.explosion(global_position + Vector3.UP * 2.0, 6.0)
		FX.ash_burst(global_position + Vector3.UP * 3.0)
		visual.visible = false
		_trail.emitting = false
		defeated.emit())


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
