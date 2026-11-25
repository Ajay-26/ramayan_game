extends Node
## Global game-feel helpers: hit-stop, screen shake ("trauma"), hit flashes,
## and particle bursts (sparks, ash, smoke, shockwaves).
## Runs even while paused, so a hit-stop can never leave the game frozen.

## 0..1. The camera shakes by trauma squared, and it decays over real time.
var trauma := 0.0
@export var trauma_decay := 1.6

var _hitstop_until_ms := 0
var _last_ticks_ms := 0
var _soft_texture: GradientTexture2D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_ticks_ms = Time.get_ticks_msec()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	_soft_texture = GradientTexture2D.new()
	_soft_texture.gradient = gradient
	_soft_texture.fill = GradientTexture2D.FILL_RADIAL
	_soft_texture.fill_from = Vector2(0.5, 0.5)
	_soft_texture.fill_to = Vector2(1.0, 0.5)
	_soft_texture.width = 32
	_soft_texture.height = 32


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var real_delta := (now - _last_ticks_ms) / 1000.0
	_last_ticks_ms = now
	if _hitstop_until_ms > 0 and now >= _hitstop_until_ms:
		_hitstop_until_ms = 0
		Engine.time_scale = 1.0
	trauma = maxf(trauma - real_delta * trauma_decay, 0.0)


## Freezes the game almost completely for a split second, to sell impact.
func hitstop(duration: float, time_scale := 0.03) -> void:
	if duration <= 0.0:
		return
	Engine.time_scale = time_scale
	_hitstop_until_ms = maxi(_hitstop_until_ms, Time.get_ticks_msec() + int(duration * 1000.0))


func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)


## Tints every mesh under `root` for a moment (white = hit, red = hurt).
func flash(root: Node, color: Color, duration := 0.08) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	for m in meshes:
		(m as MeshInstance3D).material_overlay = mat
	# Real-time timer, so it still clears during a hit-stop.
	await get_tree().create_timer(duration, true, false, true).timeout
	for m in meshes:
		if is_instance_valid(m) and (m as MeshInstance3D).material_overlay == mat:
			(m as MeshInstance3D).material_overlay = null


## Gold sparks where a blade connects.
func hit_spark(pos: Vector3) -> void:
	_burst(pos, 14, _ramp([Color(1, 0.95, 0.7, 1), Color(1, 0.6, 0.15, 1), Color(1, 0.3, 0.05, 0)]),
		0.14, 4.0, 9.0, 0.25, Vector3(0, -14, 0), 0.0, true, 1.6)


## A rakshasa bursting into embers, ash, and smoke.
func ash_burst(pos: Vector3) -> void:
	_burst(pos, 36, _ramp([Color(1, 0.8, 0.4, 1), Color(1, 0.35, 0.05, 1), Color(0.5, 0.1, 0.0, 0)]),
		0.2, 2.0, 6.5, 0.9, Vector3(0, 2.0, 0), 2.0, true, 1.8)
	_burst(pos, 40, _ramp([Color(0.25, 0.22, 0.22, 1), Color(0.12, 0.1, 0.1, 0.9), Color(0.05, 0.05, 0.05, 0)]),
		0.3, 1.0, 4.0, 1.6, Vector3(0, 1.2, 0), 1.5, false, 1.0)
	_burst(pos, 8, _ramp([Color(0.3, 0.25, 0.3, 0.6), Color(0.15, 0.12, 0.15, 0)]),
		0.9, 0.4, 1.4, 1.2, Vector3(0, 1.0, 0), 1.0, false, 1.0)
	_flash_light(pos, Color(1, 0.5, 0.15), 5.0, 0.35)


## Dark smoke when an enemy appears.
func spawn_puff(pos: Vector3) -> void:
	_burst(pos + Vector3.UP * 0.8, 12, _ramp([Color(0.2, 0.1, 0.25, 0.8), Color(0.08, 0.05, 0.1, 0)]),
		1.0, 0.5, 2.0, 0.9, Vector3(0, 1.5, 0), 1.5, false, 1.0)


## Expanding ring on the ground (spin finisher, slam).
func shockwave(pos: Vector3, radius: float, color := Color(1, 0.75, 0.35, 0.8)) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.material = mat
	var ring := MeshInstance3D.new()
	ring.mesh = torus
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root().add_child(ring)
	ring.global_position = pos + Vector3.UP * 0.1
	ring.scale = Vector3(0.2, 0.05, 0.2)
	var tween := ring.create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(radius, 0.05, radius), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.chain().tween_callback(ring.queue_free)


## Small puff where a projectile hits stone or dirt.
func dust(pos: Vector3) -> void:
	_burst(pos, 8, _ramp([Color(0.5, 0.45, 0.42, 0.8), Color(0.3, 0.28, 0.26, 0)]),
		0.18, 0.5, 2.0, 0.5, Vector3(0, -2, 0), 2.0, false, 1.0)


## Fiery explosion (clay pots, boulders).
func explosion(pos: Vector3, radius: float) -> void:
	_burst(pos, 50, _ramp([Color(1, 0.9, 0.5, 1), Color(1, 0.4, 0.05, 1), Color(0.3, 0.05, 0.0, 0)]),
		0.35, 3.0, 9.0, 0.8, Vector3(0, 3.0, 0), 3.0, true, 1.8)
	_burst(pos, 14, _ramp([Color(0.25, 0.2, 0.2, 0.8), Color(0.1, 0.08, 0.08, 0)]),
		1.6, 0.8, 2.5, 1.6, Vector3(0, 1.5, 0), 1.0, false, 1.0)
	shockwave(pos, radius, Color(1, 0.55, 0.2, 0.9))
	_flash_light(pos + Vector3.UP, Color(1, 0.5, 0.15), 8.0, 0.5)
	add_trauma(0.5)
	Sfx.play("explosion", pos, 0.0, 0.12)


## Golden divine blast (astra).
func divine_blast(pos: Vector3, radius: float) -> void:
	_burst(pos + Vector3.UP, 80, _ramp([Color(1, 1, 0.85, 1), Color(1, 0.8, 0.3, 1), Color(0.6, 0.4, 1.0, 0)]),
		0.3, 6.0, 16.0, 1.0, Vector3(0, 1.0, 0), 2.5, true, 2.0)
	shockwave(pos, radius, Color(1, 0.9, 0.5, 1.0))
	shockwave(pos, radius * 0.6, Color(0.6, 0.7, 1.0, 0.9))
	_flash_light(pos + Vector3.UP * 2.0, Color(1, 0.85, 0.5), 14.0, 0.8)


## Ground warning for a big attack: a red ring with a filling disc. Frees itself.
func telegraph(pos: Vector3, radius: float, duration: float, color := Color(1, 0.25, 0.1, 0.55)) -> void:
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.albedo_color = color
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.92
	ring_mesh.outer_radius = 1.0
	ring_mesh.material = ring_mat
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var disc_mat := ring_mat.duplicate() as StandardMaterial3D
	disc_mat.albedo_color = Color(color.r, color.g, color.b, color.a * 0.5)
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 1.0
	disc_mesh.bottom_radius = 1.0
	disc_mesh.height = 0.02
	disc_mesh.material = disc_mat
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var root := Node3D.new()
	root.add_child(ring)
	root.add_child(disc)
	_root().add_child(root)
	root.global_position = pos + Vector3.UP * 0.08
	ring.scale = Vector3(radius, 0.05, radius)
	disc.scale = Vector3(0.01, 1.0, 0.01)
	var tween := root.create_tween()
	tween.tween_property(disc, "scale", Vector3(radius, 1.0, radius), duration)
	tween.tween_callback(root.queue_free)


## Ground warning for a straight rush (Tataka's swoop): a red strip from
## `from` to `to` that fills along its length. Frees itself.
func telegraph_line(from: Vector3, to: Vector3, width: float, duration: float, color := Color(1, 0.25, 0.1, 0.5)) -> void:
	var flat_to := Vector3(to.x, from.y, to.z)
	var length := from.distance_to(flat_to)
	if length < 0.1:
		return
	var root := Node3D.new()
	_root().add_child(root)
	root.global_position = from + Vector3.UP * 0.08
	root.look_at(flat_to + Vector3.UP * 0.08, Vector3.UP)
	var edge_mat := _telegraph_material(color)
	var fill_mat := _telegraph_material(Color(color.r, color.g, color.b, color.a * 0.5))
	for side in [-1.0, 1.0]:
		var edge := _flat_box(Vector3(0.12, 0.02, length), edge_mat)
		edge.position = Vector3(side * width * 0.5, 0, -length * 0.5)
		root.add_child(edge)
	var fill := _flat_box(Vector3(width, 0.02, 1.0), fill_mat)
	fill.position = Vector3(0, 0, -0.005)
	fill.scale = Vector3(1, 1, 0.01)
	root.add_child(fill)
	var tween := root.create_tween().set_parallel(true)
	tween.tween_property(fill, "scale:z", length, duration)
	tween.tween_property(fill, "position:z", -length * 0.5, duration)
	tween.chain().tween_callback(root.queue_free)


## A dark shadow with a red ring that a script moves around (Tataka's dive
## follows Rama with it). Free it yourself.
func tracking_marker(radius: float, color := Color(1, 0.25, 0.1, 0.6)) -> Node3D:
	var root := Node3D.new()
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.albedo_color = Color(0, 0, 0, 0.55)
	shadow_mat.albedo_texture = _soft_texture
	var shadow := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(2, 2)
	quad.material = shadow_mat
	shadow.mesh = quad
	shadow.scale = Vector3(radius, 1, radius) * 1.3
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shadow)
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.9
	ring_mesh.outer_radius = 1.0
	ring_mesh.material = _telegraph_material(color)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = ring_mesh
	ring.scale = Vector3(radius, 0.05, radius)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	_root().add_child(root)
	return root


# --- Internals --------------------------------------------------------------

func _burst(pos: Vector3, amount: int, ramp: Gradient, size: float, speed_min: float, speed_max: float,
		lifetime: float, gravity: Vector3, damping: float, additive: bool, brightness: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_texture
	mat.albedo_color = Color(brightness, brightness, brightness, 1.0)
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat

	var p := CPUParticles3D.new()
	p.mesh = quad
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed_min
	p.initial_velocity_max = speed_max
	p.gravity = gravity
	p.damping_min = damping
	p.damping_max = damping
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.0
	p.color_ramp = ramp
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	_root().add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(lifetime + 0.5, false).timeout.connect(p.queue_free)


func _flash_light(pos: Vector3, color: Color, energy: float, duration: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 6.0
	_root().add_child(light)
	light.global_position = pos
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, duration)
	tween.tween_callback(light.queue_free)


func _telegraph_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	return mat


func _flat_box(size: Vector3, mat: Material) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


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


func _root() -> Node:
	var scene := get_tree().current_scene
	return scene if scene else get_tree().root
