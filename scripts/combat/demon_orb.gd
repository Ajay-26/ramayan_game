class_name DemonOrb
extends Node3D
## A slow ball of demon fire Tataka hurls from the sky. Curves a little toward
## Rama early in its flight, then flies straight, so a late dodge beats it.
## Bursts on Rama or the ground; with `leaves_fire` it leaves burning ground.

@export var speed := 13.0
@export var damage := 18.0
@export var radius := 2.0
@export var homing_time := 0.5
@export var turn_rate := 2.0
@export var lifetime := 4.0
var leaves_fire := false
var fire_damage := 9.0

var _velocity := Vector3.ZERO
var _target: Node3D
var _t := 0.0


## Call right after adding to the tree.
func launch(from: Vector3, direction: Vector3, target: Node3D = null) -> void:
	global_position = from
	_velocity = direction.normalized() * speed
	_target = target
	_build()


func _physics_process(delta: float) -> void:
	_t += delta
	if _t >= lifetime:
		queue_free()
		return
	if _t < homing_time and is_instance_valid(_target):
		var want := (_target.global_position + Vector3.UP - global_position).normalized() * speed
		_velocity = _velocity.slerp(want, clampf(turn_rate * delta, 0.0, 1.0))
	var from := global_position
	var to := from + _velocity * delta
	var params := PhysicsRayQueryParameters3D.create(from, to, Combat.LAYER_WORLD | Combat.LAYER_PLAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty():
		_burst(hit["position"])
		return
	global_position = to


func _burst(at: Vector3) -> void:
	FX.explosion(at, radius)
	Sfx.play("fire_whoosh", at)
	Combat.damage_in_radius(get_world_3d(), at + Vector3.UP * 0.5, radius, Combat.LAYER_PLAYER, damage, 8.0, "fire")
	if leaves_fire:
		var patch := FirePatch.new()
		patch.damage = fire_damage
		patch.warn_time = 0.4
		patch.burn_time = 3.5
		get_tree().current_scene.add_child(patch)
		patch.global_position = Vector3(at.x, Combat.ground_height(get_world_3d(), at, at.y), at.z)
	queue_free()


func _build() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(2.4, 0.9, 0.35)
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.45
	sphere.height = 0.9
	sphere.radial_segments = 12
	sphere.rings = 6
	sphere.material = mat
	core.mesh = sphere
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(core)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.45, 0.15)
	light.light_energy = 3.0
	light.omni_range = 7.0
	add_child(light)
	var trail_mat := StandardMaterial3D.new()
	trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	trail_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	trail_mat.vertex_color_use_as_albedo = true
	trail_mat.albedo_color = Color(1.8, 1.8, 1.8)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	quad.material = trail_mat
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.7, 0.3, 1), Color(0.8, 0.15, 0.3, 0.6), Color(0.15, 0.0, 0.1, 0)])
	var trail := CPUParticles3D.new()
	trail.mesh = quad
	trail.amount = 30
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.spread = 180.0
	trail.gravity = Vector3(0, 1.5, 0)
	trail.initial_velocity_min = 0.3
	trail.initial_velocity_max = 1.0
	trail.color_ramp = ramp
	add_child(trail)
