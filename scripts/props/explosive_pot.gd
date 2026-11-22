extends StaticBody3D
## Clay pot full of lamp oil. Any hit (arrow, chakra, blade) makes it explode,
## hurting every rakshasa nearby. Rama gets singed if he's too close.

@export var radius := 4.0
@export var damage := 60.0

var _exploded := false


func _ready() -> void:
	add_to_group("targetable")


func is_targetable() -> bool:
	return not _exploded


func aim_point() -> Vector3:
	return global_position + Vector3.UP * 0.5


func take_damage(_amount: float, _from_position: Vector3, _knockback: float, _kind: String = "") -> bool:
	if _exploded:
		return false
	_exploded = true
	remove_from_group("targetable")
	_explode.call_deferred()
	return true


func _explode() -> void:
	var center := global_position + Vector3.UP * 0.5
	FX.explosion(center, radius)
	FX.hitstop(0.08)
	Combat.damage_in_radius(get_world_3d(), center, radius, Combat.LAYER_ENEMY | Combat.LAYER_WORLD, damage, 10.0, "explosion", [get_rid()])
	Combat.damage_in_radius(get_world_3d(), center, radius * 0.6, Combat.LAYER_PLAYER, 15.0, 8.0, "explosion")
	queue_free()
