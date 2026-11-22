class_name Rock
extends Node3D
## An irregular boulder: a sphere pushed around by noise, with a flattened
## base, painterly rock-and-moss shading, and simple collision.

const ROCK_SHADER := preload("res://shaders/rock.gdshader")

@export var size := Vector3(1.5, 1.0, 1.3)
@export var rock_seed := 1

static var _material: ShaderMaterial


func _ready() -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_mesh()
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = ROCK_SHADER
	mesh_instance.material_override = _material
	add_child(mesh_instance)
	var body := StaticBody3D.new()
	body.collision_layer = Combat.LAYER_WORLD
	body.collision_mask = 0
	var shape := CylinderShape3D.new()
	shape.radius = maxf(size.x, size.z) * 0.85
	shape.height = size.y * 1.6
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, size.y * 0.3, 0)
	body.add_child(cs)
	add_child(body)


func _build_mesh() -> Mesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 10
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var noise := FastNoiseLite.new()
	noise.seed = rock_seed
	noise.frequency = 1.1
	var detail := FastNoiseLite.new()
	detail.seed = rock_seed + 7
	detail.frequency = 3.5
	for i in verts.size():
		var v := verts[i]
		var push := 1.0 + noise.get_noise_3dv(v) * 0.35 + detail.get_noise_3dv(v) * 0.08
		v *= push
		# Flatten the bottom so it sits on the ground, and facet it a little.
		if v.y < -0.35:
			v.y = -0.35 + (v.y + 0.35) * 0.2
		verts[i] = Vector3(v.x * size.x, v.y * size.y, v.z * size.z)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var st := SurfaceTool.new()
	st.create_from(mesh, 0)
	st.generate_normals()
	return st.commit()
