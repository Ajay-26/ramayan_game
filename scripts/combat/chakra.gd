class_name ChakraProjectile
extends Node3D
## Rama's divine chakra. Homes in on its target (curving around to reach it),
## cutting everything it passes through, then boomerangs back to Rama's hand,
## cutting again on the way home. With no target it flies straight ahead.
## Enemies hit from behind on the return trip can't block it.

signal caught

@export var out_speed := 20.0
@export var return_speed := 26.0
@export var max_distance := 7.0
## How sharply it can turn toward its target (radians per second).
@export var turn_rate := 7.0
## Gives up chasing after this long and comes back.
@export var max_out_time := 0.7
@export var damage := 14.0
@export var knockback := 3.0
@export var hit_radius := 0.8

var _owner: Player
var _target: Node3D
var _target_point := Vector3.ZERO
var _dir := Vector3.FORWARD
var _returning := false
var _out_time := 0.0
var _hit_this_leg: Array[Object] = []

@onready var disc: Node3D = $Disc


func launch(owner_player: Player, from: Vector3, target_point: Vector3, homing_target: Node3D = null) -> void:
	_owner = owner_player
	_target = homing_target
	global_position = from
	_target_point = target_point
	var to := target_point - from
	if to.length() < 1.0:
		to = owner_player.facing
	_dir = to.normalized()
	if _target == null and to.length() > max_distance:
		_target_point = from + _dir * max_distance


func _physics_process(delta: float) -> void:
	disc.rotate_y(delta * 30.0)
	if not is_instance_valid(_owner):
		queue_free()
		return

	if _returning:
		var home := _owner.global_position + Vector3.UP * 1.2
		var to_home := home - global_position
		var step := return_speed * delta
		global_position += to_home.normalized() * minf(step, to_home.length())
		_cut_along_path()
		if global_position.distance_to(home) < 0.8:
			caught.emit()
			queue_free()
		return

	_out_time += delta
	if _target and Combat.is_alive_target(_target):
		_target_point = Combat.aim_point(_target)
	elif _target:
		_target = null  # it died: finish the flight and come back
	# Curve toward the target point.
	var wanted := (_target_point - global_position).normalized()
	var angle := _dir.angle_to(wanted)
	if angle > 0.001:
		var axis := _dir.cross(wanted)
		if axis.length_squared() < 0.0001:
			axis = Vector3.UP
		_dir = _dir.rotated(axis.normalized(), minf(angle, turn_rate * delta)).normalized()
	var new_pos := global_position + _dir * out_speed * delta

	# Bounce back early if a wall is in the way.
	var params := PhysicsRayQueryParameters3D.create(global_position, new_pos, Combat.LAYER_WORLD)
	var wall := get_world_3d().direct_space_state.intersect_ray(params)
	if not wall.is_empty():
		_hit_object(wall["collider"], wall["position"])
		global_position = wall["position"] - _dir * 0.2
		_start_return()
		return

	global_position = new_pos
	_cut_along_path()
	var reached := _target == null and global_position.distance_to(_target_point) < 0.6
	if reached or _out_time >= max_out_time:
		_start_return()


func _start_return() -> void:
	if _returning:
		return
	_returning = true
	_hit_this_leg.clear()


func _cut_along_path() -> void:
	var mask := Combat.LAYER_ENEMY | Combat.LAYER_WORLD
	for body in Combat.sphere_query(get_world_3d(), global_position, hit_radius, mask):
		_hit_object(body, global_position)


func _hit_object(body: Object, at: Vector3) -> void:
	if body == null or _hit_this_leg.has(body) or not body.has_method("take_damage"):
		return
	_hit_this_leg.append(body)
	# The hit comes from the chakra's side, so a return trip strikes shields from behind.
	var source := global_position - _dir * 0.5 if not _returning else global_position
	if body.take_damage(damage, source, knockback, "chakra"):
		FX.hit_spark(at)
		Sfx.play("sword_hit", at, -3.0, 0.15)
		FX.hitstop(0.03)
	# Reached what it was hunting: turn for home.
	if body == _target and not _returning:
		_start_return()
