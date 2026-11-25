class_name Boulder
extends Node3D
## Tataka's boulder: thrown in an arc, or (arc 0) falling burning out of the
## storm clouds. Lands on a marked spot and shatters, hurting Rama if he's
## still inside the red circle.

@export var damage := 18.0
@export var radius := 2.6

var _start := Vector3.ZERO
var _target := Vector3.ZERO
var _flight := 1.0
var _t := 0.0
var _arc := 6.0


func launch(from: Vector3, target: Vector3, flight_time: float, arc := 6.0) -> void:
	_start = from
	_target = target
	_flight = flight_time
	_arc = arc
	global_position = from
	FX.telegraph(target, radius, flight_time)
	if arc <= 0.0:
		_add_fire_trail()
		Sfx.play("stone_fall", target, -2.0)


func _physics_process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / _flight, 0.0, 1.0)
	var pos := _start.lerp(_target, k)
	pos.y += sin(k * PI) * _arc
	global_position = pos
	rotate_x(delta * 6.0)
	if k >= 1.0:
		FX.explosion(_target, radius)
		FX.dust(_target + Vector3.UP * 0.3)
		Combat.damage_in_radius(get_world_3d(), _target + Vector3.UP, radius, Combat.LAYER_PLAYER, damage, 9.0, "melee")
		queue_free()


## Burning trail for stones falling from the sky.
func _add_fire_trail() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(2.0, 2.0, 2.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	quad.material = mat
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.85, 0.4, 1), Color(1, 0.35, 0.05, 0.7), Color(0.2, 0.05, 0.05, 0)])
	var trail := CPUParticles3D.new()
	trail.mesh = quad
	trail.amount = 24
	trail.lifetime = 0.5
	trail.local_coords = false
	trail.direction = Vector3.UP
	trail.spread = 20.0
	trail.gravity = Vector3.ZERO
	trail.initial_velocity_min = 1.0
	trail.initial_velocity_max = 3.0
	trail.color_ramp = ramp
	add_child(trail)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.5, 0.15)
	light.light_energy = 2.5
	light.omni_range = 6.0
	add_child(light)
