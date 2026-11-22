class_name FirePatch
extends Node3D
## A patch of demon fire on the ground (Tataka, phase 3). Warns for a second,
## then burns for a few seconds, hurting Rama while he stands in it.

@export var radius := 2.2
@export var warn_time := 1.0
@export var burn_time := 5.0
@export var damage := 8.0
@export var tick := 0.5

var _t := 0.0
var _tick_left := 0.0
var _light: OmniLight3D
var _flames: CPUParticles3D


func _ready() -> void:
	FX.telegraph(global_position, radius, warn_time, Color(1, 0.4, 0.05, 0.6))


func _physics_process(delta: float) -> void:
	_t += delta
	if _t < warn_time:
		return
	if _light == null:
		_ignite()
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = tick
		Combat.damage_in_radius(get_world_3d(), global_position + Vector3.UP * 0.5, radius, Combat.LAYER_PLAYER, damage, 2.0, "fire")
	_light.light_energy = 3.0 + sin(_t * 17.0) * 0.6
	if _t >= warn_time + burn_time:
		_flames.emitting = false
		_light.light_energy = 0.0
		set_physics_process(false)
		get_tree().create_timer(1.2).timeout.connect(queue_free)


func _ignite() -> void:
	_light = OmniLight3D.new()
	_light.light_color = Color(1, 0.45, 0.1)
	_light.omni_range = radius * 2.5
	_light.position = Vector3.UP
	add_child(_light)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1.6, 1.6, 1.6)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.6, 0.6)
	quad.material = mat
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.8, 0.3, 1), Color(1, 0.35, 0.05, 0.8), Color(0.3, 0.05, 0.0, 0)])
	_flames = CPUParticles3D.new()
	_flames.mesh = quad
	_flames.amount = 40
	_flames.lifetime = 0.8
	_flames.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_flames.emission_sphere_radius = radius * 0.8
	_flames.direction = Vector3.UP
	_flames.spread = 15.0
	_flames.gravity = Vector3(0, 2.5, 0)
	_flames.initial_velocity_min = 0.5
	_flames.initial_velocity_max = 1.5
	_flames.color_ramp = ramp
	_flames.scale_amount_min = 0.6
	_flames.scale_amount_max = 1.0
	add_child(_flames)
	_flames.emitting = true
