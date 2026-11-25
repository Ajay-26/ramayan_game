class_name Projectile
extends Node3D
## Arrows (Rama's and the archers'). Moves by raycasting each physics step, so
## fast arrows never pass through thin things. Rama's arrows catch fire when
## they fly through a torch flame (group "fire_source").

@export var speed := 40.0
@export var damage := 12.0
@export var knockback := 2.0
@export var kind := "arrow"
@export var gravity := 0.0
@export var lifetime := 2.5
## Charged arrows keep flying through enemies.
@export var pierce := false

var velocity := Vector3.ZERO
var mask := Combat.LAYER_WORLD | Combat.LAYER_ENEMY
var from_player := true
var is_fire := false
var _exclude: Array[RID] = []

@onready var fire_fx: Node3D = get_node_or_null("Fire")


## Call right after adding to the tree.
func launch(from: Vector3, direction: Vector3, shooter: CollisionObject3D) -> void:
	velocity = direction.normalized() * speed
	if shooter:
		_exclude.append(shooter.get_rid())
		# Start the first ray from inside the shooter, so an enemy standing
		# right up close (overlapping the spawn point) still gets hit.
		global_position = from - velocity.normalized() * 0.7
	else:
		global_position = from
	_orient()
	if fire_fx:
		fire_fx.visible = false


func ignite() -> void:
	if is_fire:
		return
	is_fire = true
	kind = "fire"
	damage *= 1.5
	if fire_fx:
		fire_fx.visible = true


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		return
	velocity.y -= gravity * delta
	var from := global_position
	var to := from + velocity * delta

	if from_player and not is_fire:
		# Passing close by a torch (anywhere up its pole to the flame) lights the arrow.
		for source in get_tree().get_nodes_in_group("fire_source"):
			var base := (source as Node3D).global_position
			var flat := Vector2(to.x - base.x, to.z - base.z).length()
			if flat < 1.0 and to.y > base.y - 0.5 and to.y < base.y + 3.2:
				ignite()
				break

	var params := PhysicsRayQueryParameters3D.create(from, to, mask, _exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		var hit_pos: Vector3 = hit["position"]
		var source_pos := hit_pos - velocity.normalized() * 2.0
		var landed := false
		if collider.has_method("take_damage"):
			landed = collider.take_damage(damage, source_pos, knockback, kind)
		if landed:
			FX.hit_spark(hit_pos)
			Sfx.play("arrow_hit", hit_pos)
		else:
			FX.dust(hit_pos)
			Sfx.play("arrow_thunk", hit_pos, -4.0)
		if landed and from_player:
			FX.hitstop(0.04 if not pierce else 0.08)
		if pierce and collider is CharacterBody3D:
			_exclude.append((collider as CollisionObject3D).get_rid())
			global_position = hit_pos
			return
		queue_free()
		return
	global_position = to
	_orient()


func _orient() -> void:
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP if absf(velocity.normalized().y) < 0.99 else Vector3.RIGHT)
