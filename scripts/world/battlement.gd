class_name Battlement
extends Node3D
## Fortifications built at load, running along this node's local X axis:
##   PALISADE: a wall of sharpened logs (rakshasa camp).
##   FORT:     a stone wall with crenellations, optional round towers at the ends.
## Each has box collision on the world layer.

enum Kind { PALISADE, FORT }

@export var kind := Kind.PALISADE
@export var length := 10.0
@export var height := 3.5
@export var thickness := 1.4
@export var towers := false
## No collision: purely decorative (e.g. a low rail on a ledge).
@export var decorative := false


func _ready() -> void:
	if kind == Kind.PALISADE:
		_build_palisade()
	else:
		_build_fort()
	if not decorative:
		var body := StaticBody3D.new()
		body.collision_layer = Combat.LAYER_WORLD
		body.collision_mask = 0
		var shape := BoxShape3D.new()
		shape.size = Vector3(length, height, maxf(thickness, 0.6))
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = Vector3(0, height * 0.5, 0)
		body.add_child(cs)
		add_child(body)


func _build_palisade() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(global_position.x * 13.0 + global_position.z * 7.0))
	var radius := 0.2
	var count := maxi(1, int(length / (radius * 2.0)))
	var log_mesh := CylinderMesh.new()
	log_mesh.top_radius = radius
	log_mesh.bottom_radius = radius
	log_mesh.height = 1.0
	log_mesh.radial_segments = 6
	log_mesh.rings = 1
	var tip_mesh := CylinderMesh.new()
	tip_mesh.top_radius = 0.0
	tip_mesh.bottom_radius = radius
	tip_mesh.height = 0.5
	tip_mesh.radial_segments = 6
	tip_mesh.rings = 1
	var logs: Array[Transform3D] = []
	var tips: Array[Transform3D] = []
	for i in count:
		var x := -length * 0.5 + radius + i * radius * 2.0
		var h := height * rng.randf_range(0.85, 1.05)
		var lean := Basis(Vector3.RIGHT, rng.randf_range(-0.05, 0.05))
		logs.append(Transform3D(lean.scaled(Vector3(1, h, 1)), Vector3(x, h * 0.5 - 0.3, 0)))
		tips.append(Transform3D(lean, Vector3(x, h - 0.05, 0)))
	var wood := ShaderMaterial.new()
	wood.shader = preload("res://shaders/bark.gdshader")
	wood.set_shader_parameter("moss_amount", 0.0)
	wood.set_shader_parameter("streak_scale", 3.0)
	_multimesh(log_mesh, logs, wood)
	_multimesh(tip_mesh, tips, wood)
	# Two lashing beams across the logs.
	for y in [height * 0.3, height * 0.7]:
		var beam := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(length, 0.16, 0.12)
		box.material = wood
		beam.mesh = box
		beam.position = Vector3(0, y, radius + 0.04)
		add_child(beam)


func _build_fort() -> void:
	var stone := ShaderMaterial.new()
	stone.shader = preload("res://shaders/stone_blocks.gdshader")

	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length, height, thickness)
	box.material = stone
	wall.mesh = box
	wall.position = Vector3(0, height * 0.5, 0)
	add_child(wall)
	# Crenellations along the top.
	var merlon := BoxMesh.new()
	merlon.size = Vector3(0.7, 0.8, thickness * 0.5)
	var spots: Array[Transform3D] = []
	var count := int(length / 1.4)
	for i in count:
		var x := -length * 0.5 + 0.7 + i * 1.4
		spots.append(Transform3D(Basis(), Vector3(x, height + 0.4, thickness * 0.25)))
	_multimesh(merlon, spots, stone)
	if towers:
		for side in [-1.0, 1.0]:
			var tower := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.5
			cyl.bottom_radius = 1.7
			cyl.height = height + 2.5
			cyl.material = stone
			tower.mesh = cyl
			tower.position = Vector3(side * length * 0.5, (height + 2.5) * 0.5, 0)
			add_child(tower)
			var roof := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 2.1
			cone.height = 2.2
			var roof_mat := StandardMaterial3D.new()
			roof_mat.albedo_color = Color(0.36, 0.17, 0.1)
			cone.material = roof_mat
			roof.mesh = cone
			roof.position = Vector3(side * length * 0.5, height + 2.5 + 1.1, 0)
			add_child(roof)


func _multimesh(mesh: Mesh, xforms: Array[Transform3D], material: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	node.material_override = material
	add_child(node)
