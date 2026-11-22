class_name Combat
## Shared combat constants and helpers.

const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_ENEMY := 4

## Damage kinds that matter to defenses:
##   light, heavy, slam, arrow, charged, fire, chakra, astra, takedown, explosion
const RANGED_KINDS := ["arrow", "charged", "fire", "chakra"]


## Returns every unique body overlapping a sphere. Call from _physics_process.
static func sphere_query(world: World3D, center: Vector3, radius: float, mask: int, exclude: Array[RID] = []) -> Array[Node]:
	var shape := SphereShape3D.new()
	shape.radius = radius
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis(), center)
	params.collision_mask = mask
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.exclude = exclude
	var found: Array[Node] = []
	for result in world.direct_space_state.intersect_shape(params, 32):
		var collider: Node = result["collider"]
		if collider != null and not found.has(collider):
			found.append(collider)
	return found


## Damages everything with take_damage() inside a sphere. Returns what was hit.
static func damage_in_radius(world: World3D, center: Vector3, radius: float, mask: int, damage: float,
		knockback: float, kind: String, exclude: Array[RID] = []) -> Array[Node]:
	var hit: Array[Node] = []
	for target in sphere_query(world, center, radius, mask, exclude):
		if target.has_method("take_damage") and target.take_damage(damage, center, knockback, kind):
			hit.append(target)
	return hit


## Height of the ground (world layer) under a point, or `fallback` if none.
static func ground_height(world: World3D, at: Vector3, fallback: float) -> float:
	var params := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 12.0, at + Vector3.DOWN * 30.0, LAYER_WORLD)
	var hit := world.direct_space_state.intersect_ray(params)
	return (hit["position"] as Vector3).y if not hit.is_empty() else fallback


## True if nothing in the world layer blocks the straight line between two points.
static func line_of_sight(world: World3D, from: Vector3, to: Vector3) -> bool:
	var params := PhysicsRayQueryParameters3D.create(from, to, LAYER_WORLD)
	return world.direct_space_state.intersect_ray(params).is_empty()


## Flat (XZ-plane) direction from one point to another; falls back if they overlap.
static func flat_direction(from: Vector3, to: Vector3, fallback: Vector3 = Vector3.FORWARD) -> Vector3:
	var d := to - from
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return fallback
	return d.normalized()


## Rotation (around Y) that makes a node's -Z axis point along a flat direction.
static func yaw_for(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)


## The point to aim at on a target (chest height for characters).
static func aim_point(target: Node3D) -> Vector3:
	if target.has_method("aim_point"):
		return target.aim_point()
	return target.global_position + Vector3.UP


static func is_alive_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return false
	if target.has_method("is_targetable"):
		return target.is_targetable()
	return true
