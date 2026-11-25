extends StaticBody3D
## The sacred fire of Vishwamitra's yagna. Rakshasas try to put it out.
## If its health runs out, Rama must try again from the checkpoint.

signal health_changed(current: float, maximum: float)
signal destroyed

@export var max_health := 450.0

var health := 0.0
var _destroyed := false

@onready var flame: Node3D = $Flame
@onready var light: OmniLight3D = $Light


func _ready() -> void:
	add_to_group("objective")
	health = max_health
	# The sacred fire crackles; you hear it as you come near.
	var fire := AudioStreamPlayer3D.new()
	fire.name = "FireSound"
	fire.stream = Sfx.stream("fire_loop")
	fire.unit_size = 4.0
	fire.max_distance = 30.0
	fire.volume_db = -6.0
	fire.position = Vector3.UP * 1.5
	add_child(fire)
	fire.play()


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
