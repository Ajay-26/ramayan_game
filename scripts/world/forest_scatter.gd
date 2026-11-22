class_name ForestScatter
extends Node3D
## Fills its parent TerrainPatch with forest: painterly broadleaf trees and
## pines (thick on the hills, a few as cover inside the play area), leafy bushes
## and grass tufts. Everything is drawn with MultiMesh (a handful of draw calls),
## and tree trunks get collision so Rama and enemies walk around them.

@export var seed := 1
@export var edge_trees := 90
@export var inner_trees := 6
@export var bushes := 70
@export var grass := 900
## Areas (x, z, width, depth in world XZ) kept clear of trees and bushes:
## paths, gates, fight spots.
@export var keep_clear: Array[Rect2] = []
## Edge trees only grow further than this from the center line (-1 = just
## outside the terrain's play area). Keeps trunks off ledges and out of forts.
@export var edge_min_x := -1.0

const BROADLEAF_VARIANTS := 3
const PINE_VARIANTS := 2

var _terrain: TerrainPatch
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_terrain = get_parent() as TerrainPatch
	if _terrain == null:
		push_warning("ForestScatter must be a child of a TerrainPatch")
		return
	_rng.seed = seed
	_build.call_deferred()  # after the terrain has generated


func _build() -> void:
	_make_trees(_place_trees())
	_make_bushes()
	_make_grass()


func _clear(x: float, z: float, margin: float) -> bool:
	var p := Vector2(x, z)
	for r in keep_clear:
		if r.grow(margin).has_point(p):
			return false
	return true


func _random_point() -> Vector2:
	var t := _terrain
	return Vector2(_rng.randf_range(t.x_range.x, t.x_range.y),
		_rng.randf_range(minf(t.z_range.x, t.z_range.y), maxf(t.z_range.x, t.z_range.y)))


func _place_trees() -> Array:
	var out: Array = []
	var t := _terrain
	var edge_start := edge_min_x if edge_min_x >= 0.0 else t.play_half_width - 1.0
	var tries := 0
	while out.size() < edge_trees and tries < edge_trees * 20:
		tries += 1
		var p := _random_point()
		if absf(p.x) < edge_start or not _clear(p.x, p.y, 1.5):
			continue
		if _too_close(out, p, 2.8):
			continue
		out.append(p)
	var inner := 0
	tries = 0
	while inner < inner_trees and tries < inner_trees * 40:
		tries += 1
		var p := _random_point()
		if absf(p.x) >= t.play_half_width - 1.0 or absf(p.x - t.path_center(p.y)) < t.path_half_width + 2.5:
			continue
		if not _clear(p.x, p.y, 2.0) or _too_close(out, p, 4.0):
			continue
		out.append(p)
		inner += 1
	return out


func _too_close(points: Array, p: Vector2, dist: float) -> bool:
	for q in points:
		if (q as Vector2).distance_squared_to(p) < dist * dist:
			return true
	return false


func _make_trees(points: Array) -> void:
	var groups := {}  # mesh -> Array[Transform3D]
	var collider := StaticBody3D.new()
	collider.collision_layer = Combat.LAYER_WORLD
	collider.collision_mask = 0
	add_child(collider)
	for p in points:
		var pos := Vector3(p.x, _terrain.height_at(p.x, p.y) - 0.15, p.y)
		var is_pine := _rng.randf() < 0.45
		var mesh: Mesh = TreeFactory.pine(_rng.randi() % PINE_VARIANTS) if is_pine \
			else TreeFactory.broadleaf(_rng.randi() % BROADLEAF_VARIANTS)
		var s := _rng.randf_range(0.85, 1.3)
		var xform := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s), pos)
		if not groups.has(mesh):
			groups[mesh] = [] as Array[Transform3D]
		(groups[mesh] as Array[Transform3D]).append(xform)
		var shape := CylinderShape3D.new()
		shape.radius = 0.4 * s
		shape.height = 4.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position = pos + Vector3.UP * 2.0
		collider.add_child(cs)
	for mesh in groups:
		_multimesh(mesh, groups[mesh])


func _make_bushes() -> void:
	var groups := [[] as Array[Transform3D], [] as Array[Transform3D]]
	var t := _terrain
	var tries := 0
	var placed := 0
	while placed < bushes and tries < bushes * 20:
		tries += 1
		var p := _random_point()
		if absf(p.x - t.path_center(p.y)) < t.path_half_width + 1.0 or not _clear(p.x, p.y, 0.5):
			continue
		var s := _rng.randf_range(0.7, 1.5)
		(groups[placed % 2] as Array[Transform3D]).append(Transform3D(
			Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s * 1.2, s, s * 1.2)),
			Vector3(p.x, t.height_at(p.x, p.y) - 0.1, p.y)))
		placed += 1
	for v in 2:
		_multimesh(TreeFactory.bush(v), groups[v])


func _make_grass() -> void:
	var xforms: Array[Transform3D] = []
	var t := _terrain
	for k in grass:
		var p := _random_point()
		if absf(p.x - t.path_center(p.y)) < t.path_half_width * 0.8:
			continue
		var s := _rng.randf_range(0.7, 1.4)
		xforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.3), s)),
			Vector3(p.x, t.height_at(p.x, p.y) - 0.03, p.y)))
	_multimesh(TreeFactory.grass_tuft(), xforms)


func _multimesh(mesh: Mesh, xforms: Array[Transform3D]) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = mm
	add_child(node)
