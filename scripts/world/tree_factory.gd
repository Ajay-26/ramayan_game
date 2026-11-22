class_name TreeFactory
## Builds painterly tree, pine and grass meshes plus their materials at load,
## with every texture painted in code (no image files to download). Results are
## cached, so all forest patches share the same few meshes.
##   broadleaf(v): bent tapered trunk, branches, ~6 leaf clusters of painted
##                 leaf cards with normals that shade each cluster like a ball.
##   pine(v):      straight trunk with tiers of drooping needle-branch cards.
##   grass_tuft(): crossed painted grass cards.
## Meshes have two surfaces: 0 = bark, 1 = foliage.

const LEAF_SHADER := preload("res://shaders/leaves.gdshader")
const BARK_SHADER := preload("res://shaders/bark.gdshader")

static var _cache := {}


static func broadleaf(variant: int) -> ArrayMesh:
	var key := "broadleaf%d" % variant
	if not _cache.has(key):
		_cache[key] = _build_broadleaf(variant)
	return _cache[key]


static func pine(variant: int) -> ArrayMesh:
	var key := "pine%d" % variant
	if not _cache.has(key):
		_cache[key] = _build_pine(variant)
	return _cache[key]


static func bush(variant: int) -> ArrayMesh:
	var key := "bush%d" % variant
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = 9000 + variant * 13
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var center := Vector3(0, 0.55, 0)
		_leaf_cluster(st, rng, center, 0.75, 14, 1.0, Vector3(0, 0.2, 0))
		_leaf_cluster(st, rng, center + Vector3(rng.randf_range(-0.5, 0.5), -0.1, rng.randf_range(-0.5, 0.5)), 0.55, 9, 0.9, Vector3(0, 0.2, 0))
		var mesh := ArrayMesh.new()
		st.commit(mesh)
		mesh.surface_set_material(0, leaf_material())
		_cache[key] = mesh
	return _cache[key]


static func grass_tuft() -> ArrayMesh:
	if not _cache.has("grass"):
		_cache["grass"] = _build_grass()
	return _cache["grass"]


# --- Materials --------------------------------------------------------------

static func bark_material() -> ShaderMaterial:
	if not _cache.has("bark_mat"):
		var mat := ShaderMaterial.new()
		mat.shader = BARK_SHADER
		_cache["bark_mat"] = mat
	return _cache["bark_mat"]


static func leaf_material() -> ShaderMaterial:
	if not _cache.has("leaf_mat"):
		var mat := ShaderMaterial.new()
		mat.shader = LEAF_SHADER
		mat.set_shader_parameter("leaf_texture", _leaf_texture())
		_cache["leaf_mat"] = mat
	return _cache["leaf_mat"]


static func needle_material() -> ShaderMaterial:
	if not _cache.has("needle_mat"):
		var mat := ShaderMaterial.new()
		mat.shader = LEAF_SHADER
		mat.set_shader_parameter("leaf_texture", _needle_texture())
		mat.set_shader_parameter("color_a", Color(0.1, 0.26, 0.14))
		mat.set_shader_parameter("color_b", Color(0.18, 0.34, 0.16))
		mat.set_shader_parameter("alpha_cut", 0.38)
		mat.set_shader_parameter("sway", 0.025)
		_cache["needle_mat"] = mat
	return _cache["needle_mat"]


static func grass_material() -> ShaderMaterial:
	if not _cache.has("grass_mat"):
		var mat := ShaderMaterial.new()
		mat.shader = LEAF_SHADER
		mat.set_shader_parameter("leaf_texture", _grass_texture())
		mat.set_shader_parameter("color_a", Color(0.22, 0.4, 0.13))
		mat.set_shader_parameter("color_b", Color(0.34, 0.48, 0.16))
		mat.set_shader_parameter("alpha_cut", 0.35)
		mat.set_shader_parameter("sway", 0.6)
		mat.set_shader_parameter("sway_height", 0.6)
		mat.set_shader_parameter("sway_speed", 1.6)
		_cache["grass_mat"] = mat
	return _cache["grass_mat"]


# --- Trees ------------------------------------------------------------------

static func _build_broadleaf(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + variant * 77
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var leaves := SurfaceTool.new()
	leaves.begin(Mesh.PRIMITIVE_TRIANGLES)

	var height := rng.randf_range(6.5, 8.5)
	var lean := Vector3(rng.randf_range(-0.5, 0.5), 0, rng.randf_range(-0.5, 0.5))
	var trunk_top := Vector3(0, height, 0) + lean
	# Trunk: bends gently toward its lean.
	var spine: Array[Vector3] = []
	for k in 7:
		var t := k / 6.0
		spine.append(Vector3(0, height * t, 0) + lean * t * t)
	_tube(bark, spine, 0.42, 0.18, 9)

	var cluster_centers: Array[Vector3] = []
	var branches := rng.randi_range(4, 6)
	for b in branches:
		var start_t := rng.randf_range(0.5, 0.85)
		var start := Vector3(0, height * start_t, 0) + lean * start_t * start_t
		var ang := TAU * b / branches + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(ang), rng.randf_range(0.5, 0.9), sin(ang)).normalized()
		var length := rng.randf_range(1.8, 3.0)
		var mid := start + out * length * 0.5 + Vector3.UP * 0.3
		var end := start + out * length + Vector3.UP * 0.6
		_tube(bark, [start, mid, end] as Array[Vector3], 0.14, 0.05, 6)
		cluster_centers.append(end)
	cluster_centers.append(trunk_top + Vector3.UP * 0.5)
	cluster_centers.append(trunk_top + Vector3(rng.randf_range(-1, 1), -0.6, rng.randf_range(-1, 1)))

	# Leaf clusters around each center; normals point out from the canopy center.
	var canopy_center := Vector3.ZERO
	for c in cluster_centers:
		canopy_center += c
	canopy_center /= cluster_centers.size()
	for c in cluster_centers:
		var radius := rng.randf_range(1.3, 1.9)
		_leaf_cluster(leaves, rng, c, radius, 16, 1.5, canopy_center)

	var mesh := ArrayMesh.new()
	bark.generate_normals()
	bark.commit(mesh)
	leaves.commit(mesh)
	mesh.surface_set_material(0, bark_material())
	mesh.surface_set_material(1, leaf_material())
	return mesh


static func _build_pine(variant: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5000 + variant * 31
	var bark := SurfaceTool.new()
	bark.begin(Mesh.PRIMITIVE_TRIANGLES)
	var needles := SurfaceTool.new()
	needles.begin(Mesh.PRIMITIVE_TRIANGLES)

	var height := rng.randf_range(9.0, 12.0)
	_tube(bark, [Vector3.ZERO, Vector3(0, height * 0.5, 0), Vector3(0, height, 0)] as Array[Vector3], 0.32, 0.06, 8)
	var tiers := 9
	for k in tiers:
		var t := float(k) / (tiers - 1)
		var y := lerpf(height * 0.25, height * 0.98, t)
		var reach := lerpf(2.6, 0.5, t) * rng.randf_range(0.9, 1.1)
		var count := 7 if t < 0.7 else 5
		var spin := rng.randf() * TAU
		for i in count:
			var ang := spin + TAU * i / count
			var dir := Vector3(cos(ang), 0, sin(ang))
			var droop := lerpf(0.55, 0.25, t)
			var tip := Vector3(0, y, 0) + dir * reach + Vector3.DOWN * reach * droop
			var base := Vector3(0, y + 0.15, 0)
			var side := Vector3(-dir.z, 0, dir.x) * reach * 0.42
			var ao := lerpf(0.55, 1.0, t)
			# Each branch card: 4 corners, normals tilted out and up.
			var n := (dir + Vector3.UP * 0.8).normalized()
			_quad(needles, base - side * 0.3, base + side * 0.3, tip + side, tip - side,
				[n, n, n, n], [Vector2(0.5, 1), Vector2(0.5, 1), Vector2(1, 0), Vector2(0, 0)], ao)
	var mesh := ArrayMesh.new()
	bark.generate_normals()
	bark.commit(mesh)
	needles.commit(mesh)
	mesh.surface_set_material(0, bark_material())
	mesh.surface_set_material(1, needle_material())
	return mesh


static func _build_grass() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var ang := PI * k / 3.0
		var d := Vector3(cos(ang), 0, sin(ang)) * 0.35
		var h := 0.55
		var n := Vector3.UP
		_quad(st, -d, d, d + Vector3.UP * h, -d + Vector3.UP * h,
			[n, n, n, n], [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], 1.0)
	var mesh := ArrayMesh.new()
	st.commit(mesh)
	mesh.surface_set_material(0, grass_material())
	return mesh


## A tapered tube along a polyline (trunks, branches). UV: x around, y along.
static func _tube(st: SurfaceTool, points: Array[Vector3], r0: float, r1: float, sides: int) -> void:
	var rings: Array = []
	for k in points.size():
		var t := float(k) / (points.size() - 1)
		var p := points[k]
		var forward := (points[mini(k + 1, points.size() - 1)] - points[maxi(k - 1, 0)]).normalized()
		var right := forward.cross(Vector3.FORWARD if absf(forward.y) > 0.9 else Vector3.UP).normalized()
		var up := right.cross(forward).normalized()
		var ring: Array[Vector3] = []
		var radius := lerpf(r0, r1, t)
		for s in sides + 1:
			var a := TAU * s / sides
			ring.append(p + (right * cos(a) + up * sin(a)) * radius)
		rings.append(ring)
	for k in points.size() - 1:
		var v0 := float(k) / (points.size() - 1)
		var v1 := float(k + 1) / (points.size() - 1)
		for s in sides:
			var u0 := float(s) / sides
			var u1 := float(s + 1) / sides
			var a: Vector3 = rings[k][s]
			var b: Vector3 = rings[k][s + 1]
			var c: Vector3 = rings[k + 1][s + 1]
			var d: Vector3 = rings[k + 1][s]
			for pair in [[a, Vector2(u0, v0)], [c, Vector2(u1, v1)], [b, Vector2(u1, v0)],
					[a, Vector2(u0, v0)], [d, Vector2(u0, v1)], [c, Vector2(u1, v1)]]:
				st.set_uv(pair[1])
				st.add_vertex(pair[0])


## A clump of leaf cards scattered over a sphere; normals point away from the
## canopy center so the clump lights like one soft mass.
static func _leaf_cluster(st: SurfaceTool, rng: RandomNumberGenerator, center: Vector3, radius: float,
		cards: int, size: float, canopy_center: Vector3) -> void:
	for i in cards:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 1), rng.randf_range(-1, 1)).normalized()
		var pos := center + dir * radius * rng.randf_range(0.35, 1.0)
		var tangent := dir.cross(Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT).normalized()
		var bitangent := dir.cross(tangent).normalized()
		var spin := rng.randf() * TAU
		var t := (tangent * cos(spin) + bitangent * sin(spin)) * size * 0.5
		var b := (tangent * -sin(spin) + bitangent * cos(spin)) * size * 0.5
		var corners := [pos - t - b, pos + t - b, pos + t + b, pos - t + b]
		var normals := []
		for c in corners:
			normals.append(((c as Vector3) - canopy_center).normalized().lerp(Vector3.UP, 0.25).normalized())
		# Darker deep inside the canopy, brighter on the outside.
		var ao := clampf(0.4 + (pos - canopy_center).length() / (radius * 2.2), 0.4, 1.0)
		_quad(st, corners[0], corners[1], corners[2], corners[3], normals,
			[Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)], ao)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normals: Array, uvs: Array, ao: float) -> void:
	var verts := [a, b, c, d]
	for idx in [0, 1, 2, 0, 2, 3]:
		st.set_color(Color(ao, ao, ao))
		st.set_normal(normals[idx])
		st.set_uv(uvs[idx])
		st.add_vertex(verts[idx])


# --- Painted textures -------------------------------------------------------

## A clump of overlapping leaves in several greens, transparent between them.
static func _leaf_texture() -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var center := Vector2(size, size) * 0.5
	for i in 70:
		var p := center + Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1)).limit_length(1.0) * size * 0.4
		var length := rng.randf_range(26.0, 40.0)
		var width := length * rng.randf_range(0.38, 0.5)
		var ang := rng.randf() * TAU
		var shade := rng.randf_range(0.6, 1.15)
		var color := Color(0.75 * shade, 0.95 * shade, 0.55 * shade)
		_stamp_leaf(img, p, length, width, ang, color)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A drooping pine branch: a stem with needles brushed off both sides.
static func _needle_texture() -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for k in 3:
		var x0 := size * (0.3 + 0.2 * k)
		for j in 120:
			var t := rng.randf()
			var y := lerpf(size * 0.95, size * 0.05, t)
			var stem_x := lerpf(size * 0.5, x0, t)
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var length := lerpf(34.0, 14.0, t) * rng.randf_range(0.7, 1.1)
			var ang := -PI / 2.0 + side * rng.randf_range(0.6, 1.1)
			var shade := rng.randf_range(0.65, 1.1)
			_stamp_line(img, Vector2(stem_x, y), Vector2(cos(ang), sin(ang)) * length, 2.2,
				Color(0.6 * shade, 0.85 * shade, 0.6 * shade))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Grass blades: dark at the roots, lighter toward the tips.
static func _grass_texture() -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 40:
		var x := rng.randf_range(8, size - 8)
		var h := rng.randf_range(size * 0.45, size * 0.98)
		var lean := rng.randf_range(-18, 18)
		var shade := rng.randf_range(0.75, 1.15)
		var steps := int(h)
		for s in steps:
			var t := float(s) / steps
			var px := x + lean * t * t
			var py := size - 1 - s
			var w := lerpf(2.6, 0.6, t)
			var col := Color(0.55, 0.75, 0.45).lerp(Color(0.95, 1.0, 0.7), t) * shade
			col.a = 1.0
			for dx in range(-int(ceil(w)), int(ceil(w)) + 1):
				var xx := int(px) + dx
				if xx >= 0 and xx < size and py >= 0 and absf(dx) <= w:
					img.set_pixel(xx, py, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _stamp_leaf(img: Image, center: Vector2, length: float, width: float, angle: float, color: Color) -> void:
	var axis := Vector2(cos(angle), sin(angle))
	var normal := Vector2(-axis.y, axis.x)
	var r := int(length * 0.6)
	for y in range(int(center.y) - r, int(center.y) + r):
		for x in range(int(center.x) - r, int(center.x) + r):
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			var d := Vector2(x, y) - center
			var u := d.dot(axis) / (length * 0.5)
			var v := d.dot(normal) / (width * 0.5)
			# Leaf outline: pointed at both ends.
			var edge := (1.0 - absf(u)) * (1.0 + 0.3 * u)
			if absf(u) <= 1.0 and absf(v) <= edge:
				var midrib := 1.0 - 0.18 * (1.0 - smoothstep(0.0, 0.12, absf(v)))
				var light := 0.85 + 0.25 * (v * 0.5 + 0.5) - 0.15 * absf(u)
				var c := Color(color.r * light * midrib, color.g * light * midrib, color.b * light * midrib, 1.0)
				img.set_pixel(x, y, c)


static func _stamp_line(img: Image, from: Vector2, delta: Vector2, width: float, color: Color) -> void:
	var steps := int(delta.length())
	for s in steps:
		var t := float(s) / maxf(steps, 1)
		var p := from + delta * t
		var w := width * (1.0 - t * 0.7)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if Vector2(dx, dy).length() > w:
					continue
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, Color(color.r * (0.8 + 0.3 * t), color.g * (0.8 + 0.3 * t), color.b, 1.0))
