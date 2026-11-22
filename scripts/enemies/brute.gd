class_name Brute
extends Enemy
## Shielded rakshasa brute. Its big shield blocks every hit from the front.
## Ways through:
##   - hit it from behind (the chakra's return trip does this nicely)
##   - a charged arrow or the heavy ground slam breaks its guard for a while
##   - punish the long recovery after its own slam, when the shield is down
## It shrugs off light hits (no stagger) and slams the ground hard.

enum State { IDLE, SPAWNING, CHASE, WINDUP, ATTACK, RECOVER, STAGGER }

## Hits that go through the shield no matter where they come from.
const GUARD_BREAKERS := ["charged", "slam", "astra", "takedown", "explosion", "fire"]

@export var damage := 32.0
@export var attack_range := 2.4
@export var windup_time := 0.8
@export var slam_radius := 2.4
@export var guard_break_time := 3.5

var state := State.SPAWNING
var _t := 0.0
var _attack_cooldown := 1.0
var _guard_broken_left := 0.0
var _hit_done := false
var _tween: Tween

@onready var body_pivot: Node3D = $Visual/Body
@onready var shield: Node3D = $Visual/Body/Shield
@onready var maul: Node3D = $Visual/Body/MaulPivot

var _shield_up := Vector3(0.0, 0.0, 0.0)
var _shield_down := Vector3(deg_to_rad(-70), 0.0, deg_to_rad(30))
var _maul_rest := Vector3(deg_to_rad(-50), 0, 0)
var _maul_raised := Vector3(deg_to_rad(140), 0, 0)
var _maul_slam := Vector3(deg_to_rad(-85), 0, 0)


func _ready() -> void:
	super._ready()
	maul.rotation = _maul_rest
	if model:
		model.attach_weapon(maul, true, 0.1)
		maul.rotation = Vector3.ZERO
		_shield_up = Vector3.ZERO
		model.attach(shield, "Chest", Transform3D(Basis(), Vector3(-0.08, 0.05, 0.42)))
		shield.scale = Vector3.ONE * 0.6
		model.attach($Visual/Body/HornL, "Head", Transform3D(Basis.from_euler(Vector3(deg_to_rad(-20), 0, deg_to_rad(30))).scaled(Vector3.ONE * 0.55), Vector3(-0.07, 0.17, 0.02)))
		model.attach($Visual/Body/HornR, "Head", Transform3D(Basis.from_euler(Vector3(deg_to_rad(-20), 0, deg_to_rad(-30))).scaled(Vector3.ONE * 0.55), Vector3(0.07, 0.17, 0.02)))
		model.attach($Visual/Body/EyeL, "Head", Transform3D(Basis(), Vector3(-0.035, 0.075, 0.1)))
		model.attach($Visual/Body/EyeR, "Head", Transform3D(Basis(), Vector3(0.035, 0.075, 0.1)))
	if aware:
		FX.spawn_puff(global_position)
		state = State.SPAWNING
		act("Spawn", 0.8)
	else:
		state = State.IDLE


func is_guarding() -> bool:
	return _guard_broken_left <= 0.0 and state in [State.IDLE, State.SPAWNING, State.CHASE, State.WINDUP]


func _physics_process(delta: float) -> void:
	_t += delta
	_attack_cooldown -= delta
	if _guard_broken_left > 0.0:
		_guard_broken_left -= delta
		if _guard_broken_left <= 0.0:
			_raise_shield()
	apply_gravity(delta)

	match state:
		State.IDLE:
			patrol(delta)
			update_awareness(delta)
			if aware:
				_set_state(State.CHASE)
		State.SPAWNING:
			decelerate(delta, 10.0)
			if _t >= 0.7:
				_set_state(State.CHASE)
		State.CHASE:
			_chase(delta)
		State.WINDUP:
			decelerate(delta, 12.0)
			var target := current_target()
			if target and _t < windup_time * 0.5:
				face_toward(target.global_position, delta, 6.0)
			if _t >= windup_time:
				_set_state(State.ATTACK)
		State.ATTACK:
			decelerate(delta, 14.0)
			if not _hit_done and _t >= 0.1:
				_hit_done = true
				_slam()
			if _t >= 0.3:
				_set_state(State.RECOVER)
		State.RECOVER:
			decelerate(delta, 10.0)
			if _t >= 1.1:
				release_token()
				_attack_cooldown = randf_range(1.0, 1.8)
				_set_state(State.CHASE)
		State.STAGGER:
			decelerate(delta, 8.0)
			if _t >= 1.2:
				_set_state(State.CHASE)

	locomote(delta, "HeavyIdle", "HeavyWalking", "HeavyRunning")
	move_and_slide()


func _chase(delta: float) -> void:
	var target := current_target()
	if target == null or (target == _player and _player.is_dead()):
		decelerate(delta, 10.0)
		return
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var dir := to_target / dist if dist > 0.01 else facing()
	face_direction(dir, delta, 4.0)  # turns slowly: you can get around it
	var on_objective := target_is_objective(target)
	var reach := 3.0 if on_objective else attack_range
	if _attack_cooldown <= 0.0 and dist <= reach and (on_objective or take_token()):
		_set_state(State.WINDUP)
		return
	var desired := path_direction(target.global_position, delta, dir) * move_speed if dist > reach * 0.8 else Vector3.ZERO
	desired += separation() * 2.0
	_steer(desired, delta, 8.0)


func _slam() -> void:
	var center := global_position + facing() * 1.4
	FX.shockwave(center, slam_radius, Color(1, 0.5, 0.3, 0.9))
	FX.dust(center)
	FX.add_trauma(0.35)
	var target := current_target()
	if target_is_objective(target) and global_position.distance_to(target.global_position) < 3.6:
		target.take_damage(damage, global_position, 0.0, "melee")
	Combat.damage_in_radius(get_world_3d(), center + Vector3.UP, slam_radius, Combat.LAYER_PLAYER, damage, 11.0, "melee", [get_rid()])


func _accepts_damage(kind: String, from_position: Vector3) -> bool:
	if not is_guarding() or kind in GUARD_BREAKERS:
		return true
	var to_source := Combat.flat_direction(global_position, from_position, facing())
	return facing().dot(to_source) < 0.34  # blocks anything within ~70° of the front


func _on_blocked(from_position: Vector3, _kind: String) -> void:
	var shield_point := global_position + Vector3.UP * 1.2 + Combat.flat_direction(global_position, from_position) * 0.8
	FX.hit_spark(shield_point)
	FX.flash(shield, Color(0.8, 0.85, 1.0, 0.8), 0.06)
	FX.add_trauma(0.08)


func _on_hurt(_amount: float, from_position: Vector3, knockback: float, kind: String) -> void:
	if kind in ["charged", "slam", "explosion", "astra"]:
		_break_guard()
	# Super armor: only big hits stagger it, and it barely moves.
	apply_knockback(from_position, knockback * 0.3)
	if knockback >= 7.0 and state != State.ATTACK:
		release_token()
		_reset_pose()
		_set_state(State.STAGGER)


func _break_guard() -> void:
	_guard_broken_left = guard_break_time
	_kill_tween()
	_tween = new_tween()
	_tween.tween_property(shield, "rotation", _shield_down, 0.2)


func _raise_shield() -> void:
	new_tween().tween_property(shield, "rotation", _shield_up, 0.3)


func _set_state(new_state: State) -> void:
	state = new_state
	_t = 0.0
	if model:
		match new_state:
			State.WINDUP:
				act("HeavyCharge", windup_time + 0.1)
				FX.telegraph(global_position + facing() * 1.4, slam_radius, windup_time + 0.1)
			State.ATTACK:
				_hit_done = false
				act("HeavyRelease", 1.4)
				if _guard_broken_left <= 0.0:
					new_tween().tween_property(shield, "rotation", _shield_down, 0.15)
			State.STAGGER:
				act("Hurt2", 1.2)
			State.CHASE:
				if _guard_broken_left <= 0.0:
					_raise_shield()
		return
	match new_state:
		State.WINDUP:
			_kill_tween()
			_tween = new_tween().set_parallel(true)
			_tween.tween_property(maul, "rotation", _maul_raised, windup_time * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			_tween.tween_property(body_pivot, "rotation:x", deg_to_rad(12), windup_time * 0.8)
			FX.telegraph(global_position + facing() * 1.4, slam_radius, windup_time + 0.1)
		State.ATTACK:
			_hit_done = false
			_kill_tween()
			_tween = new_tween().set_parallel(true)
			_tween.tween_property(maul, "rotation", _maul_slam, 0.1)
			_tween.tween_property(body_pivot, "rotation:x", deg_to_rad(-18), 0.1)
			if _guard_broken_left <= 0.0:
				_tween.tween_property(shield, "rotation", _shield_down, 0.15)
		State.RECOVER:
			_kill_tween()
			_tween = new_tween().set_parallel(true)
			_tween.tween_property(maul, "rotation", _maul_rest, 0.9)
			_tween.tween_property(body_pivot, "rotation:x", 0.0, 0.9)
		State.CHASE:
			if _guard_broken_left <= 0.0:
				_raise_shield()


func _reset_pose() -> void:
	_kill_tween()
	if model:
		return
	maul.rotation = _maul_rest
	body_pivot.rotation = Vector3.ZERO


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
