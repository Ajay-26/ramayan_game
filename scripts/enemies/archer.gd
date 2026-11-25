class_name Archer
extends Enemy
## Rakshasa archer: keeps its distance, draws (glowing arrowhead = warning),
## then fires at where Rama is heading. Backs away if Rama gets close.
## Archers placed on ledges can't reach Rama, so they hold position: use the
## bow or chakra on them.

enum State { IDLE, SPAWNING, POSITION, DRAW, RECOVER, HURT }

@export var arrow_scene: PackedScene
@export var preferred_min := 7.0
@export var preferred_max := 15.0
@export var draw_time := 0.75
@export var shot_interval_min := 1.5
@export var shot_interval_max := 2.4
## Archers on ledges never walk.
@export var stationary := false

var state := State.SPAWNING
var _t := 0.0
var _shot_cooldown := 0.0

@onready var bow_pivot: Node3D = $Visual/Body/BowPivot
@onready var tip: MeshInstance3D = $Visual/Body/BowPivot/Tip


func _ready() -> void:
	super._ready()
	_shot_cooldown = randf_range(0.8, 2.0)
	tip.visible = false
	if model:
		model.attach(bow_pivot, "LeftHand", str_to_var(CharacterModel.HAND_L))
		bow_pivot.rotation = Vector3.ZERO
		model.attach($Visual/Body/HornL, "Head", Transform3D(Basis.from_euler(Vector3(deg_to_rad(-20), 0, deg_to_rad(30))).scaled(Vector3.ONE * 0.55), Vector3(-0.07, 0.17, 0.02)))
		model.attach($Visual/Body/HornR, "Head", Transform3D(Basis.from_euler(Vector3(deg_to_rad(-20), 0, deg_to_rad(-30))).scaled(Vector3.ONE * 0.55), Vector3(0.07, 0.17, 0.02)))
		model.attach($Visual/Body/EyeL, "Head", Transform3D(Basis(), Vector3(-0.035, 0.075, 0.1)))
		model.attach($Visual/Body/EyeR, "Head", Transform3D(Basis(), Vector3(0.035, 0.075, 0.1)))
	if aware:
		FX.spawn_puff(global_position)
		state = State.SPAWNING
		act("Spawn", 0.7)
	else:
		state = State.IDLE


func _physics_process(delta: float) -> void:
	_t += delta
	_shot_cooldown -= delta
	apply_gravity(delta)

	match state:
		State.IDLE:
			patrol(delta)
			update_awareness(delta)
			if aware:
				_set_state(State.POSITION)
		State.SPAWNING:
			decelerate(delta, 10.0)
			if _t >= 0.6:
				_set_state(State.POSITION)
		State.POSITION:
			_position(delta)
		State.DRAW:
			decelerate(delta, 12.0)
			if _player:
				face_toward(_player.global_position, delta, 12.0)
			if _t >= draw_time:
				_shoot()
				_set_state(State.RECOVER)
		State.RECOVER:
			decelerate(delta, 10.0)
			if _t >= 0.5:
				_set_state(State.POSITION)
		State.HURT:
			decelerate(delta, 7.0)
			if _t >= 0.4:
				_set_state(State.POSITION)

	locomote(delta, "LightIdle", "LightWalking", "LightRunning", "LightStrafe", "Retreat")
	move_and_slide()


func _position(delta: float) -> void:
	if _player == null or _player.is_dead():
		decelerate(delta, 10.0)
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var dir := to_player / dist if dist > 0.01 else facing()
	face_direction(dir, delta, 8.0)

	var desired := Vector3.ZERO
	if not stationary:
		if dist < preferred_min:
			desired = -dir * move_speed  # back off
		elif dist > preferred_max:
			desired = path_direction(_player.global_position, delta, dir) * move_speed
		desired += separation() * 2.0
	_steer(desired, delta, 10.0)

	var can_see := Combat.line_of_sight(get_world_3d(), aim_point(), _player.aim_point())
	if _shot_cooldown <= 0.0 and can_see and dist < preferred_max + 12.0:
		_set_state(State.DRAW)


func _shoot() -> void:
	tip.visible = false
	if arrow_scene == null or _player == null:
		return
	var start := aim_point() + Vector3.UP * 0.3 + facing() * 0.6
	var target := _player.aim_point()
	var flight := start.distance_to(target) / 24.0
	# Lead the shot a little, so standing still isn't the only way to get hit.
	target += Vector3(_player.velocity.x, 0.0, _player.velocity.z) * flight * 0.5
	var arrow := arrow_scene.instantiate() as Projectile
	arrow.from_player = false
	arrow.mask = Combat.LAYER_WORLD | Combat.LAYER_PLAYER
	get_tree().current_scene.add_child(arrow)
	arrow.launch(start, target - start, self)
	Sfx.play("bow_release", start, -3.0)
	_shot_cooldown = randf_range(shot_interval_min, shot_interval_max)


func _set_state(new_state: State) -> void:
	state = new_state
	_t = 0.0
	match new_state:
		State.DRAW:
			tip.visible = true
			if model:
				act("ThrowLTopOnly", draw_time + 0.45)
			else:
				new_tween().tween_property(bow_pivot, "rotation:x", deg_to_rad(10), draw_time * 0.5)
		State.RECOVER, State.HURT, State.POSITION:
			tip.visible = false
			if model == null:
				bow_pivot.rotation.x = 0.0
			if new_state == State.HURT:
				act("Hurt1", 0.4)


func _on_hurt(_amount: float, from_position: Vector3, knockback: float, _kind: String) -> void:
	if not stationary:
		apply_knockback(from_position, knockback)
	_shot_cooldown = maxf(_shot_cooldown, 0.8)
	_set_state(State.HURT)
