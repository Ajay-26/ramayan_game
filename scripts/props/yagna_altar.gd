extends StaticBody3D
## The sacred fire of Vishwamitra's yagna. Rakshasas try to put it out.
## If its health runs out, Rama must try again from the checkpoint.

signal health_changed(current: float, maximum: float)
signal destroyed

@export var max_health := 300.0

var health := 0.0
var _destroyed := false

@onready var flame: Node3D = $Flame
@onready var light: OmniLight3D = $Light


func _ready() -> void:
	add_to_group("objective")
	health = max_health


func is_destroyed() -> bool:
	return _destroyed


func take_damage(amount: float, _from_position: Vector3, _knockback: float, kind: String = "") -> bool:
	# Only rakshasa attacks hurt the fire; Rama's own blows don't.
	if _destroyed or kind != "melee":
		return false
	health = maxf(health - amount, 0.0)
	health_changed.emit(health, max_health)
	FX.flash(flame, Color(0.3, 0.1, 0.4, 0.7), 0.1)
	var k := health / max_health
	flame.scale = Vector3.ONE * lerpf(0.35, 1.0, k)
	light.light_energy = lerpf(1.0, 5.0, k)
	if health <= 0.0:
		_destroyed = true
		destroyed.emit()
	return true
