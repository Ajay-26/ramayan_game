class_name Grunt
extends Enemy
## Rakshasa grunt: circles Rama and takes turns attacking with a club.
## Every attack has a clear wind-up (club raised, eyes flare) that Rama can
## dodge or interrupt by hitting first. Unaware grunts patrol and can be
## snuck up on.

enum State { IDLE, SPAWNING, CHASE, WINDUP, ATTACK, RECOVER, HURT }

@export var attack_range := 1.9
@export var damage := 17.0
@export var windup_time := 0.5
## Distance kept while circling and waiting for a turn to attack.
@export var circle_distance := 3.2

var state := State.SPAWNING
var _t := 0.0
var _attack_cooldown := 0.0
var _strafe_dir := 1.0
var _hit_done := false
var _eye_mat: StandardMaterial3D
var _tween: Tween

@onready var body_pivot: Node3D = $Visual/Body
@onready var club: Node3D = $Visual/Body/ClubPivot

var _club_rest := Vector3(deg_to_rad(-60), 0, deg_to_rad(10))
var _club_raised := Vector3(deg_to_rad(120), 0, 0)
var _club_slam := Vector3(deg_to_rad(-80), 0, 0)


func _ready() -> void:
	super._ready()
	_strafe_dir = 1.0 if randf() < 0.5 else -1.0
	_attack_cooldown = randf_range(0.6, 1.6)
	var eye_l := $Visual/Body/EyeL as MeshInstance3D
	var eye_r := $Visual/Body/EyeR as MeshInstance3D
	_eye_mat = (eye_l.get_active_material(0) as StandardMaterial3D).duplicate()
	eye_l.material_override = _eye_mat
	eye_r.material_override = _eye_mat
	club.rotation = _club_rest
	if model:
		model.attach_weapon(club, true, 0.15)
		club.rotation = Vector3.ZERO
		model.attach($Visual/Body/HornL, "Head", Transform3D(Basis.from_euler(Vector3(deg_to_rad(-20), 0, deg_to_rad(30))).scaled(Vector3.ONE * 0.55), Vector3(-0.07, 0.17, 0.02)))
		model.attach($Visual/Body/HornR, "Head", Transform3D(Basis.from_euler(Vector3(deg_to_rad(-20), 0, deg_to_rad(-30))).scaled(Vector3.ONE * 0.55), Vector3(0.07, 0.17, 0.02)))
		model.attach(eye_l, "Head", Transform3D(Basis(), Vector3(-0.035, 0.075, 0.1)))
		model.attach(eye_r, "Head", Transform3D(Basis(), Vector3(0.035, 0.075, 0.1)))
	if aware:
		# Pop in out of dark smoke.
		FX.spawn_puff(global_position)
		visual.scale = Vector3.ONE * 0.05
		new_tween().tween_property(visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		state = State.SPAWNING
		act("Spawn", 0.7)
	else:
		state = State.IDLE


func _physics_process(delta: float) -> void:
	_t += delta
	_attack_cooldown -= delta
	apply_gravity(delta)

	match state:
		State.IDLE:
			patrol(delta)
			update_awareness(delta)
			if aware:
				_set_state(State.CHASE)
		State.SPAWNING:
			decelerate(delta, 10.0)
			if _t >= 0.6:
				_set_state(State.CHASE)
		State.CHASE:
			_chase(delta)
		State.WINDUP:
			decelerate(delta, 12.0)
			var target := current_target()
			if target and _t < windup_time * 0.6:
				face_toward(target.global_position, delta, 10.0)
			if _t >= windup_time:
				_set_state(State.ATTACK)
		State.ATTACK:
			decelerate(delta, 14.0)
			if not _hit_done and _t >= 0.08:
				_hit_done = true
				_strike()
			if _t >= 0.3:
				_set_state(State.RECOVER)
		State.RECOVER:
			decelerate(delta, 10.0)
			if _t >= 0.75:
				release_token()
				_attack_cooldown = randf_range(0.6, 1.4)
				_set_state(State.CHASE)
		State.HURT:
			decelerate(delta, 7.0)
			if _t >= 0.42:
				_set_state(State.CHASE)

	if state == State.IDLE:
		locomote(delta, "HeavyIdle", "HeavyWalking", "HeavyRunning")
	else:
		locomote(delta, "HeavyIdle", "HeavyWalking", "HeavyRunning", "HeavyStrafe", "Retreat")
	move_and_slide()


func _chase(delta: float) -> void:
	var target := current_target()
	if target == null or (target == _player and _player.is_dead()):
		decelerate(delta, 10.0)
		return
	var on_objective := target_is_objective(target)
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var dir := to_target / dist if dist > 0.01 else facing()
	face_direction(dir, delta, 8.0)

	var desired := Vector3.ZERO
	if on_objective:
		# Altar attackers don't wait for a turn.
		if dist <= 2.6:
			if _attack_cooldown <= 0.0:
				_set_state(State.WINDUP)
				return
		else:
			desired = path_direction(target.global_position, delta, dir) * move_speed
	else:
		if not _has_token and _attack_cooldown <= 0.0 and dist < 7.0:
			take_token()
		if _has_token:
			if dist <= attack_range:
				_set_state(State.WINDUP)
				return
			desired = path_direction(target.global_position, delta, dir) * move_speed
		elif dist > circle_distance + 4.0:
			desired = path_direction(target.global_position, delta, dir) * move_speed
		else:
			# Circle at a distance, waiting for a turn to attack.
			var tangent := Vector3(-dir.z, 0.0, dir.x) * _strafe_dir
			var radial := clampf(dist - circle_distance, -1.0, 1.0)
			desired = (dir * radial + tangent * 0.6) * move_speed * 0.55
			if randf() < delta * 0.3:
				_strafe_dir = -_strafe_dir
	desired += separation() * 2.5
	_steer(desired, delta, 12.0)


func _strike() -> void:
	var target := current_target()
	if target_is_objective(target):
		if global_position.distance_to(target.global_position) < 3.2:
			target.take_damage(damage, global_position, 0.0, "melee")
		_attack_cooldown = randf_range(0.8, 1.4)
		return
	var center := global_position + Vector3.UP + facing() * 1.2
	Combat.damage_in_radius(get_world_3d(), center, 1.0, Combat.LAYER_PLAYER, damage, 7.0, "melee", [get_rid()])


func _set_state(new_state: State) -> void:
	state = new_state
	_t = 0.0
	if model:
		match new_state:
			State.WINDUP:
				act("HeavyCharge", windup_time + 0.1)
				_eye_mat.emission_energy_multiplier = 3.0
			State.ATTACK:
				_hit_done = false
				var thrust := facing() * 7.0
				velocity.x = thrust.x
				velocity.z = thrust.z
				act("HeavyRelease", 1.1, 1.0)
			State.RECOVER:
				_eye_mat.emission_energy_multiplier = 0.8
			State.HURT:
				act("Hurt1" if randf() < 0.5 else "Hurt2", 0.42)
		return
	match new_state:
		State.WINDUP:
			_kill_tween()
			_tween = new_tween().set_parallel(true)
			_tween.tween_property(club, "rotation", _club_raised, windup_time * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tween.tween_property(body_pivot, "rotation:x", deg_to_rad(15), windup_time * 0.8)
			_eye_mat.emission_energy_multiplier = 3.0
		State.ATTACK:
			_hit_done = false
			var lunge := facing() * 7.0
			velocity.x = lunge.x
			velocity.z = lunge.z
			_kill_tween()
			_tween = new_tween().set_parallel(true)
			_tween.tween_property(club, "rotation", _club_slam, 0.08)
			_tween.tween_property(body_pivot, "rotation:x", deg_to_rad(-20), 0.08)
		State.RECOVER:
			_eye_mat.emission_energy_multiplier = 0.8
			_kill_tween()
			_tween = new_tween().set_parallel(true)
			_tween.tween_property(club, "rotation", _club_rest, 0.5)
			_tween.tween_property(body_pivot, "rotation:x", 0.0, 0.5)


func _accepts_damage(_kind: String, _from_position: Vector3) -> bool:
	return state != State.SPAWNING


func _on_hurt(_amount: float, from_position: Vector3, knockback: float, _kind: String) -> void:
	apply_knockback(from_position, knockback)
	# Getting hit interrupts any attack and gives up the attack turn.
	release_token()
	_attack_cooldown = maxf(_attack_cooldown, 0.8)
	_reset_pose()
	_set_state(State.HURT)


func receive_takedown() -> void:
	super.receive_takedown()
	_reset_pose()


func _reset_pose() -> void:
	_kill_tween()
	_eye_mat.emission_energy_multiplier = 0.8
	if model:
		return
	club.rotation = _club_rest
	body_pivot.rotation = Vector3.ZERO
	_eye_mat.emission_energy_multiplier = 0.8


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
