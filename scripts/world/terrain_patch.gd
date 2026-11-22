class_name TerrainPatch
extends Node3D
## A stretch of forest floor with real ups and downs. Builds its own mesh and
## collision (HeightMapShape3D) at load, from one shared world-space noise, so
## neighbouring patches line up seamlessly.
##   - The play area (|x| < play_half_width) gently rolls; the path down the
##     middle stays nearly flat.
##   - Beyond the play area the ground rises into wooded hills.
##   - "mounds" add hand-placed hills inside the play area.
## Colors: lush mossy greens, a dirt path, brown-grey rock on steep slopes.

@export var x_range := Vector2(-40, 40)
## z_range.x is the near edge (larger z), z_range.y the far edge.
@export var z_range := Vector2(0, -40)
@export var play_half_width := 12.0
@export var path_half_width := 2.2
@export var inner_amplitude := 0.45
@export var hill_height := 5.0
## Extra hills inside the play area: Vector3(x, z, height), radius ~4.5 m.
@export var mounds: Array[Vector3] = []
@export var mound_radius := 4.5

static var _noise: FastNoiseLite
static var _detail: FastNoiseLite

var body: StaticBody3D


static func _ensure_noise() -> void:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.seed = 11
		_noise.frequency = 0.045
		_noise.fractal_octaves = 3
		_detail = FastNoiseLite.new()
		_detail.seed = 23
		_detail.frequency = 0.18


func _ready() -> void:
	_ensure_noise()
	_build()


## Where the dirt path runs at a given z (it wanders a little).
func path_center(z: float) -> float:
	return sin(z * 0.05) * 1.2


## Ground height at a world position.
func height_at(x: float, z: float) -> float:
	_ensure_noise()
	var n := _noise.get_noise_2d(x, z)
	var from_path := absf(x - path_center(z))
	# Gentle rolling inside the play area, nearly flat on the path.
	var inner := n * inner_amplitude * smoothstep(path_half_width, path_half_width * 3.0, from_path)
	# Hills rise beyond the play area.
	var beyond := absf(x) - play_half_width
	var rise := smoothstep(-1.0, 9.0, beyond)
	var hill := hill_height * (0.55 + 0.45 * _noise.get_noise_2d(x * 0.6 + 300.0, z * 0.6))
	var h := lerpf(inner, hill + n * 1.5, rise)
	for m in mounds:
		var d2 := (x - m.x) * (x - m.x) + (z - m.y) * (z - m.y)
		h += m.z * exp(-d2 / (mound_radius * mound_radius))
	return h


func _build() -> void:
	var x0 := int(floor(x_range.x))
	var x1 := int(ceil(x_range.y))
	var z_min := int(floor(minf(z_range.x, z_range.y)))
	var z_max := int(ceil(maxf(z_range.x, z_range.y)))
	var w := x1 - x0 + 1
	var d := z_max - z_min + 1

	var heights := PackedFloat32Array()
	heights.resize(w * d)
	for j in d:
		for i in w:
			heights[j * w + i] = height_at(x0 + i, z_min + j)

	# Visual mesh.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in d:
		for i in w:
			var x := float(x0 + i)
			var z := float(z_min + j)
			var h := heights[j * w + i]
			st.set_color(_ground_color(x, z, h, heights, i, j, w, d))
			st.set_uv(Vector2(x, z) * 0.25)
			st.add_vertex(Vector3(x, h, z))
	for j in d - 1:
		for i in w - 1:
			var a := j * w + i
			var b := a + 1
			var c := a + w
			var e := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(e)
			st.add_index(c)
	st.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _ground_material()
	add_child(mesh_instance)

	# Collision.
	body = StaticBody3D.new()
	body.collision_layer = Combat.LAYER_WORLD
	body.collision_mask = 0
	add_child(body)
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = d
	shape.map_data = heights
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3((x0 + x1) * 0.5, 0.0, (z_min + z_max) * 0.5)
	body.add_child(collision)


func _ground_color(x: float, z: float, h: float, heights: PackedFloat32Array, i: int, j: int, w: int, d: int) -> Color:
	var n := _detail.get_noise_2d(x, z) * 0.5 + 0.5
	var deep := Color(0.07, 0.17, 0.07)
	var lush := Color(0.16, 0.32, 0.11)
	var color := deep.lerp(lush, n)
	# Dirt path down the middle.
	var from_path := absf(x - path_center(z))
	var dirt := Color(0.3, 0.22, 0.15).lerp(Color(0.24, 0.19, 0.13), n)
	color = color.lerp(dirt, 1.0 - smoothstep(path_half_width * 0.6, path_half_width * 1.3, from_path + (n - 0.5) * 0.8))
	# Rock on steep slopes.
	var hx := heights[j * w + mini(i + 1, w - 1)] - heights[j * w + maxi(i - 1, 0)]
	var hz := heights[mini(j + 1, d - 1) * w + i] - heights[maxi(j - 1, 0) * w + i]
	var slope := Vector2(hx, hz).length() * 0.5
	color = color.lerp(Color(0.27, 0.25, 0.23), smoothstep(0.5, 1.0, slope))
	return color


func _ground_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.62, 0.62, 0.62))
	ramp.set_color(1, Color(1, 1, 1))
	var tex := NoiseTexture2D.new()
	tex.seamless = true
	tex.noise = noise
	tex.color_ramp = ramp
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_scale = Vector3(0.35, 0.35, 0.35)
	mat.roughness = 1.0
	return mat
