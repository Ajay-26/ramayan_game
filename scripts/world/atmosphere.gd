class_name Atmosphere
extends Node3D
## Air and weather around the camera: drifting ash flakes and embers always,
## plus rain, darkening, and lightning for the storm Tataka brings.
## Particles are emitted in world space from a box that follows the camera,
## so the air looks full everywhere without filling the whole level.
## Find it with get_tree().get_first_node_in_group("atmosphere").

@export var environment_path: NodePath = ^"../WorldEnvironment"
@export var sun_path: NodePath = ^"../Sun"
@export var ash_amount := 140
@export var ember_amount := 24
@export var rain_amount := 700

var _env: Environment
var _sun: DirectionalLight3D
var _sky: ShaderMaterial
var _ash: CPUParticles3D
var _embers: CPUParticles3D
var _rain: CPUParticles3D
var _base_ambient := 1.0
var _base_fog := 0.02
var _base_sun := 1.0
var _base_sun_color := Color.WHITE
var _darkness := 0.0
var _flash := 0.0
var _storm_tween: Tween


func _ready() -> void:
	add_to_group("atmosphere")
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var world_env := get_node_or_null(environment_path) as WorldEnvironment
	if world_env:
		_env = world_env.environment
		_base_ambient = _env.ambient_light_energy
		_base_fog = _env.fog_density
		if _env.sky and _env.sky.sky_material is ShaderMaterial:
			_sky = _env.sky.sky_material
	_sun = get_node_or_null(sun_path) as DirectionalLight3D
	if _sun:
		_base_sun = _sun.light_energy
		_base_sun_color = _sun.light_color
	_ash = _make_emitter(ash_amount, 7.0, Vector3(18, 7, 18), _soft_quad(0.05, Color(0.55, 0.52, 0.5, 0.7), false))
	_ash.gravity = Vector3(0.25, -0.18, 0.1)
	_ash.initial_velocity_min = 0.05
	_ash.initial_velocity_max = 0.3
	_ash.spread = 180.0
	_ash.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	_embers = _make_emitter(ember_amount, 5.0, Vector3(16, 4, 16), _soft_quad(0.06, Color(2.2, 1.0, 0.35, 1), true))
	_embers.position = Vector3(0, -3, 0)
	_embers.gravity = Vector3(0.3, 0.45, 0.0)
	_embers.initial_velocity_min = 0.2
	_embers.initial_velocity_max = 0.7
	_embers.direction = Vector3.UP
	_embers.spread = 40.0
	_embers.color_ramp = _ramp([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 0.6, 0.4, 0)])
	_rain = _make_emitter(rain_amount, 0.9, Vector3(16, 1, 16), _rain_mesh())
	_rain.position = Vector3(0, 11, 0)
	_rain.direction = Vector3(0.12, -1, 0.05)
	_rain.spread = 2.0
	_rain.gravity = Vector3.ZERO
	_rain.initial_velocity_min = 24.0
	_rain.initial_velocity_max = 28.0
	_rain.particle_flag_align_y = true
	_rain.emitting = false
	_rain.visible = false
	Sfx.loop("wind_loop", true, -4.0, 3.0)
	Sfx.loop("rain_loop", false, 0.0, 0.5)


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 3.5, 0.0)
		_apply_flash()


## Rain, and how much darker the night gets (0 = normal, 1 = pitch black storm).
func set_storm(rain: bool, darkness: float, fade_time := 2.0) -> void:
	Sfx.loop("rain_loop", rain, 0.0, fade_time)
	Sfx.loop("wind_loop", true, lerpf(-4.0, 4.0, darkness), fade_time)
	_rain.visible = rain
	_rain.emitting = rain
	if _storm_tween and _storm_tween.is_valid():
		_storm_tween.kill()
	_storm_tween = create_tween()
	_storm_tween.tween_method(_set_darkness, _darkness, darkness, fade_time)


## A lightning strike: the clouds light up, the world flashes cold blue-white.
## With `bolt_to` set, a bolt also cracks down to that point.
func lightning(strength := 1.0, direction := Vector3(0, 0.5, -1), bolt_to: Variant = null) -> void:
	if _sky:
		_sky.set_shader_parameter("lightning_direction", direction.normalized())
	_flash = maxf(_flash, strength)
	_apply_flash()
	# A second, weaker flicker right after the first.
	get_tree().create_timer(0.12).timeout.connect(func() -> void:
		_flash = maxf(_flash, strength * 0.7)
		_apply_flash())
	if bolt_to is Vector3:
		_bolt(bolt_to)
	# Thunder follows; closer strikes (with a bolt) are louder and sooner.
	var near := bolt_to is Vector3
	get_tree().create_timer(randf_range(0.05, 0.2) if near else randf_range(0.5, 1.6)).timeout.connect(func() -> void:
		Sfx.play("thunder", null, (2.0 if near else -6.0) + strength * 2.0, 0.12))


## Current lightning brightness (0 = none), for other storm visuals.
func flash_level() -> float:
	return _flash


## The sky's cloud noise, to share with other cloud layers.
func cloud_texture() -> Texture2D:
	return _sky.get_shader_parameter("clouds") as Texture2D if _sky else null


func _set_darkness(value: float) -> void:
	_darkness = value
	if _env:
		_env.ambient_light_energy = _base_ambient * lerpf(1.0, 0.35, value)
		_env.fog_density = _base_fog * lerpf(1.0, 1.9, value)
	_apply_flash()


func _apply_flash() -> void:
	if _sky:
		_sky.set_shader_parameter("lightning", _flash * 2.5)
	if _sun:
		_sun.light_energy = _base_sun * lerpf(1.0, 0.4, _darkness) + _flash * 2.6
		_sun.light_color = _base_sun_color.lerp(Color(0.8, 0.86, 1.0), clampf(_flash, 0.0, 1.0))
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("set_screen_flash"):
		hud.set_screen_flash(clampf(_flash * 0.35, 0.0, 1.0))


## A jagged bolt from high in the clouds down to `to`, gone in a blink.
func _bolt(to: Vector3) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(2.0, 2.2, 3.0, 1.0)
	var root := Node3D.new()
	get_tree().current_scene.add_child(root)
	var p := to + Vector3(randf_range(-6, 6), 40.0, randf_range(-6, 6))
	var steps := 9
	for i in steps:
		var k := float(i + 1) / steps
		var next := p.lerp(to, 1.0 / (steps - i))
		if i < steps - 1:
			next += Vector3(randf_range(-1.6, 1.6), 0, randf_range(-1.6, 1.6)) * (1.0 - k)
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		var length := p.distance_to(next)
		box.size = Vector3(0.18, 0.18, length)
		box.material = mat
		seg.mesh = box
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(seg)
		seg.global_position = (p + next) * 0.5
		seg.look_at(next, Vector3.RIGHT)
		p = next
	var light := OmniLight3D.new()
	light.light_color = Color(0.75, 0.82, 1.0)
	light.light_energy = 6.0
	light.omni_range = 16.0
	root.add_child(light)
	light.global_position = to + Vector3.UP * 3.0
	var tween := root.create_tween()
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.25).set_delay(0.08)
	tween.parallel().tween_property(light, "light_energy", 0.0, 0.3)
	tween.tween_callback(root.queue_free)


func _make_emitter(amount: int, lifetime: float, box: Vector3, mesh: Mesh) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.local_coords = false
	p.mesh = mesh
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	add_child(p)
	return p


func _soft_quad(size: float, color: Color, additive: bool) -> QuadMesh:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 16
	tex.height = 16
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = color
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	return quad


func _rain_mesh() -> BoxMesh:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.62, 0.68, 0.8, 0.28)
	var box := BoxMesh.new()
	box.size = Vector3(0.015, 0.75, 0.015)
	box.material = mat
	return box


func _ramp(colors: Array) -> Gradient:
	var g := Gradient.new()
	var offsets := PackedFloat32Array()
	var packed := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / float(colors.size() - 1))
		packed.append(colors[i])
	g.offsets = offsets
	g.colors = packed
	return g
