class_name Enemy
extends CharacterBody3D
## Shared enemy behavior: health, taking hits, death in ash, attack turns,
## stealth awareness (vision cone, hearing, suspicion), patrols, pathfinding,
## and going after an objective (the yagna altar) when Rama isn't close.

signal died(enemy: Enemy)
signal alerted(enemy: Enemy)

## How many enemies may be attacking Rama in melee at the same moment.
const MAX_ATTACKERS := 3
static var _tokens := 0

@export var max_health := 40.0
@export var gravity := 22.0
@export var move_speed := 3.8
## Height of the chest, for aiming arrows and the lock-on reticle.
@export var aim_height := 1.2
@export var label_height := 2.6
## Which way it faces at the start (0 = toward -Z, 180 = toward +Z).
@export var start_yaw_degrees := 0.0
## Astra meter Rama gains per point of damage dealt to this enemy.
@export var astra_per_damage := 0.3
@export_group("Awareness")
## Unaware enemies can be snuck past and taken down from behind.
@export var start_aware := true
@export var vision_range := 13.0
@export_range(0.0, 180.0) var vision_half_angle := 55.0
@export var hearing_range := 3.5
## Offsets from the starting position to walk between while unaware.
@export var patrol_points: Array[Vector3] = []

var health: float
var aware := true
## Optional thing to attack instead of Rama (the yagna altar).
var objective: Node3D

var _player: Player
var _has_token := false
var _suspicion := 0.0
var _home: Vector3
var _patrol_index := 0
var _patrol_wait := 0.0
var _repath_left := 0.0
var _dead := false
var _alert_label: Label3D
var _label_tween: Tween

@onready var visual: Node3D = $Visual
@onready var nav_agent: NavigationAgent3D = $NavAgent
## Animated body (optional; Tataka still uses procedural shapes).
@onready var model: CharacterModel = get_node_or_null("Visual/Model")

var _anim_lock := 0.0
var _snap_pending := true


static func reset_tokens() -> void:
	_tokens = 0


static func token_count() -> int:
	return _tokens


func _ready() -> void:
	add_to_group("enemies")
	add_to_group("targetable")
	health = max_health
	aware = start_aware
	visual.rotation.y = deg_to_rad(start_yaw_degrees)
	_home = global_position
	_player = get_tree().get_first_node_in_group("player") as Player
	_alert_label = Label3D.new()
	_alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_label.no_depth_test = true
	_alert_label.font_size = 120
	_alert_label.pixel_size = 0.006
	_alert_label.outline_size = 24
	_alert_label.position = Vector3(0, label_height, 0)
	_alert_label.visible = false
	add_child(_alert_label)


func _exit_tree() -> void:
	release_token()


func is_dead() -> bool:
	return _dead


func is_targetable() -> bool:
	return not _dead and is_inside_tree()


func aim_point() -> Vector3:
	return global_position + Vector3.UP * aim_height


func facing() -> Vector3:
	return -visual.global_basis.z


# --- Taking damage -----------------------------------------------------------

func take_damage(amount: float, from_position: Vector3, knockback: float, kind: String = "") -> bool:
	if _dead:
		return false
	if not _accepts_damage(kind, from_position):
		_on_blocked(from_position, kind)
		return false
	health -= amount
	if _player:
		_player.add_astra(amount * astra_per_damage)
	FX.flash(visual, Color(1, 1, 1, 0.85), 0.08)
	if not aware:
		become_aware()
	if health <= 0.0:
		die(kind)
		return true
	_on_hurt(amount, from_position, knockback, kind)
	return true


## Override to block some hits (e.g. a shield).
func _accepts_damage(_kind: String, _from_position: Vector3) -> bool:
	return true


func _on_blocked(_from_position: Vector3, _kind: String) -> void:
	pass


## Override for hit reactions. Default: get knocked back.
func _on_hurt(_amount: float, from_position: Vector3, knockback: float, _kind: String) -> void:
	apply_knockback(from_position, knockback)


func apply_knockback(from_position: Vector3, knockback: float) -> void:
	var away := Combat.flat_direction(from_position, global_position, -facing())
	velocity.x = away.x * knockback
	velocity.z = away.z * knockback
	if knockback > 8.0:
		velocity.y = 4.0


func die(kind: String = "") -> void:
	if _dead:
		return
	_dead = true
	release_token()
	remove_from_group("enemies")
	remove_from_group("targetable")
	collision_layer = 0
	collision_mask = Combat.LAYER_WORLD
	set_physics_process(false)
	_alert_label.visible = false
	if _player:
		_player.add_astra(5.0)
	died.emit(self)
	_death_effect(kind)


func _death_effect(_kind: String) -> void:
	FX.ash_burst(aim_point())
	var tween := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(visual, "scale", Vector3(1.25, 0.15, 1.25), 0.1)
	tween.tween_callback(queue_free)


# --- Stealth -----------------------------------------------------------------

func become_aware(propagate: bool = true) -> void:
	if aware or _dead:
		return
	aware = true
	_suspicion = 0.0
	_show_label("!", Color(1, 0.3, 0.1), true)
	alerted.emit(self)
	if propagate:
		# Shout to nearby friends.
		for node in get_tree().get_nodes_in_group("enemies"):
			var other := node as Enemy
			if other and other != self and not other.aware and other.global_position.distance_to(global_position) < 12.0:
				other.become_aware(false)


## Call every physics frame while unaware.
func update_awareness(delta: float) -> void:
	if _player == null or _player.is_dead():
		return
	var to_player := _player.global_position - global_position
	var dist := to_player.length()
	var sneaking := _player.is_sneaking
	var sight_range := vision_range * (0.5 if sneaking else 1.0)
	var noticed := false
	if dist < sight_range:
		var flat := Vector3(to_player.x, 0.0, to_player.z)
		if flat.length() > 0.01 and rad_to_deg(facing().angle_to(flat.normalized())) < vision_half_angle:
			noticed = Combat.line_of_sight(get_world_3d(), aim_point() + Vector3.UP * 0.4, _player.global_position + Vector3.UP * 1.2)
	var player_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	if not sneaking and dist < hearing_range and player_speed > 1.0:
		noticed = true  # heard running footsteps
	if noticed:
		_suspicion += delta * (2.5 if dist < sight_range * 0.5 else 1.2)
	else:
		_suspicion = maxf(_suspicion - delta * 0.4, 0.0)
	if _suspicion >= 1.0:
		become_aware()
	elif _suspicion > 0.05:
		_show_label("?", Color(1, 0.85, 0.3, clampf(0.4 + _suspicion, 0.0, 1.0)), false)
	elif _alert_label.visible and _alert_label.text == "?":
		_alert_label.visible = false


func can_be_taken_down(by: Node3D) -> bool:
	if aware or _dead:
		return false
	var to_attacker := by.global_position - global_position
	to_attacker.y = 0.0
	if to_attacker.length() > 2.2:
		return false
	return facing().dot(to_attacker.normalized()) < -0.1


## Rama grabs this enemy; it freezes until the killing blow lands.
func receive_takedown() -> void:
	set_physics_process(false)
	velocity = Vector3.ZERO
	_alert_label.visible = false


func _show_label(text: String, color: Color, pop: bool) -> void:
	_alert_label.text = text
	_alert_label.modulate = color
	_alert_label.visible = true
	if pop:
		if _label_tween and _label_tween.is_valid():
			_label_tween.kill()
		_alert_label.scale = Vector3.ONE * 1.8
		_label_tween = create_tween()
		_label_tween.tween_property(_alert_label, "scale", Vector3.ONE, 0.2)
		_label_tween.tween_interval(1.0)
		_label_tween.tween_callback(func() -> void: _alert_label.visible = false)


func patrol(delta: float) -> void:
	if patrol_points.is_empty():
		decelerate(delta, 10.0)
		return
	if _patrol_wait > 0.0:
		_patrol_wait -= delta
		decelerate(delta, 10.0)
		return
	var target := _home + patrol_points[_patrol_index]
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.5:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()
		_patrol_wait = 1.5
		return
	var dir := to_target.normalized()
	face_direction(dir, delta, 4.0)
	_steer(dir * move_speed * 0.4, delta, 8.0)


# --- Targets and movement ----------------------------------------------------

## Rama, unless there's an objective to wreck and Rama is far away.
func current_target() -> Node3D:
	if objective and is_instance_valid(objective) and objective.has_method("is_destroyed") and not objective.is_destroyed():
		if _player == null or _player.is_dead() or global_position.distance_to(_player.global_position) > 6.0:
			return objective
	return _player


func target_is_objective(target: Node3D) -> bool:
	return target != null and target == objective


func take_token() -> bool:
	if _has_token:
		return true
	if _tokens < MAX_ATTACKERS:
		_tokens += 1
		_has_token = true
	return _has_token


func release_token() -> void:
	if _has_token:
		_has_token = false
		_tokens = maxi(_tokens - 1, 0)


## Direction along the navigation path toward a point (walks around obstacles).
func path_direction(target_position: Vector3, delta: float, fallback: Vector3) -> Vector3:
	_repath_left -= delta
	if _repath_left <= 0.0:
		_repath_left = 0.25
		nav_agent.target_position = target_position
	if nav_agent.is_navigation_finished():
		return fallback
	var to_next := nav_agent.get_next_path_position() - global_position
	to_next.y = 0.0
	return to_next.normalized() if to_next.length() > 0.05 else fallback


func separation() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("enemies"):
		if node == self:
			continue
		var offset: Vector3 = global_position - (node as Node3D).global_position
		offset.y = 0.0
		var d := offset.length()
		if d < 1.6 and d > 0.001:
			push += offset / d * (1.6 - d)
	return push


func face_direction(dir: Vector3, delta: float, speed: float) -> void:
	if dir.length_squared() < 0.0001:
		return
	visual.rotation.y = lerp_angle(visual.rotation.y, Combat.yaw_for(dir), 1.0 - exp(-speed * delta))


func face_toward(point: Vector3, delta: float, speed: float) -> void:
	face_direction(Combat.flat_direction(global_position, point, facing()), delta, speed)


func decelerate(delta: float, rate: float) -> void:
	_steer(Vector3.ZERO, delta, rate)


func _steer(desired: Vector3, delta: float, rate: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(desired, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func apply_gravity(delta: float) -> void:
	if _snap_pending:
		# Stand on the (uneven) ground where we were placed.
		_snap_pending = false
		global_position.y = Combat.ground_height(get_world_3d(), global_position, global_position.y) + 0.05
		reset_physics_interpolation()
	if not is_on_floor():
		velocity.y -= gravity * delta


## Play an action animation fitted into `duration`; locomotion waits until it ends.
func act(animation: String, duration: float, lock: float = -1.0) -> void:
	if model == null:
		return
	model.play_fit(animation, duration)
	_anim_lock = duration if lock < 0.0 else lock


## Idle / walk / run / strafe based on how the enemy is actually moving.
## Call once per physics frame.
func locomote(delta: float, idle: String, walk: String, run: String, strafe_prefix: String = "", back: String = "") -> void:
	if model == null:
		return
	_anim_lock -= delta
	if _anim_lock > 0.0:
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var speed := flat.length()
	if speed < 0.3:
		model.play(idle, 1.0, 0.2)
		return
	var forward := facing().dot(flat) / speed
	var right := facing().cross(Vector3.UP).dot(flat) / speed * -1.0
	if strafe_prefix != "" and absf(right) > absf(forward) + 0.2:
		model.play(strafe_prefix + ("R" if right > 0.0 else "L"), clampf(speed / 2.5, 0.6, 1.4), 0.15)
	elif back != "" and forward < -0.5:
		model.play(back, clampf(speed / 3.0, 0.6, 1.4), 0.15)
	elif speed > 2.6:
		model.play(run, clampf(speed / 4.5, 0.7, 1.3), 0.15)
	else:
		model.play(walk, clampf(speed / 1.6, 0.6, 1.4), 0.15)


func new_tween() -> Tween:
	return create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
