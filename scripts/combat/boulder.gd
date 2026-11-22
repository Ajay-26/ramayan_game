class_name Boulder
extends Node3D
## Tataka's thrown boulder: flies in an arc to a marked spot, then shatters,
## hurting Rama if he's still inside the red circle.

@export var damage := 18.0
@export var radius := 2.6

var _start := Vector3.ZERO
var _target := Vector3.ZERO
var _flight := 1.0
var _t := 0.0


func launch(from: Vector3, target: Vector3, flight_time: float) -> void:
	_start = from
	_target = target
	_flight = flight_time
	global_position = from
	FX.telegraph(target, radius, flight_time)


func _physics_process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / _flight, 0.0, 1.0)
	var pos := _start.lerp(_target, k)
	pos.y += sin(k * PI) * 6.0  # arc
	global_position = pos
	rotate_x(delta * 6.0)
	if k >= 1.0:
		FX.explosion(_target, radius)
		FX.dust(_target + Vector3.UP * 0.3)
		Combat.damage_in_radius(get_world_3d(), _target + Vector3.UP, radius, Combat.LAYER_PLAYER, damage, 9.0, "melee")
		queue_free()
