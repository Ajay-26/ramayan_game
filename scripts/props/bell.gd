extends StaticBody3D
## Temple bell hung out of reach. Ring it with the chakra or an arrow.

signal rung

var is_rung := false

@onready var bell_mesh: Node3D = $Bell
@onready var glow: OmniLight3D = $Glow


func _ready() -> void:
	add_to_group("targetable")
	glow.visible = false


func is_targetable() -> bool:
	return not is_rung


func aim_point() -> Vector3:
	return bell_mesh.global_position


func take_damage(_amount: float, _from_position: Vector3, _knockback: float, kind: String = "") -> bool:
	if is_rung or not (kind in Combat.RANGED_KINDS or kind == "astra"):
		return false
	ring(false)
	return true


func ring(silent: bool) -> void:
	if is_rung:
		return
	is_rung = true
	remove_from_group("targetable")
	glow.visible = true
	if not silent:
		FX.flash(bell_mesh, Color(1, 0.85, 0.4, 0.6), 0.3)
		FX.shockwave(bell_mesh.global_position, 2.0, Color(1, 0.85, 0.4, 0.8))
		var tween := create_tween()
		tween.tween_property(bell_mesh, "rotation:z", deg_to_rad(25), 0.12)
		tween.tween_property(bell_mesh, "rotation:z", deg_to_rad(-18), 0.2)
		tween.tween_property(bell_mesh, "rotation:z", 0.0, 0.3)
	rung.emit()
