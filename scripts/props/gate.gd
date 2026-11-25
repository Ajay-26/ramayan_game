extends StaticBody3D
## A heavy gate that sinks into the ground to open (and can rise to shut).

@export var start_open := false

var is_open := false
var _closed_y := 0.0


func _ready() -> void:
	_closed_y = position.y
	if start_open:
		open(true)


func open(instant: bool = false) -> void:
	if is_open:
		return
	is_open = true
	collision_layer = 0
	if instant:
		position.y = _closed_y - 5.5
		return
	FX.dust(global_position + Vector3.UP * 0.5)
	FX.add_trauma(0.2)
	Sfx.play("gate", global_position + Vector3.UP * 2.0)
	var tween := create_tween()
	tween.tween_property(self, "position:y", _closed_y - 5.5, 1.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func close() -> void:
	if not is_open:
		return
	is_open = false
	collision_layer = Combat.LAYER_WORLD
	FX.add_trauma(0.2)
	Sfx.play("slam", global_position + Vector3.UP * 2.0, -4.0)
	var tween := create_tween()
	tween.tween_property(self, "position:y", _closed_y, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
