extends Node3D
## Standing torch: flickering firelight. Rama's arrows that fly through the
## flame catch fire (group "fire_source").

@export var base_energy := 2.2
@export var flicker_amount := 0.18

var _time := randf() * 100.0

@onready var light: OmniLight3D = $Light
@onready var flame: Node3D = $Flame


func _ready() -> void:
	add_to_group("fire_source")
	light.light_energy = base_energy


func _process(delta: float) -> void:
	_time += delta * 9.0
	var wobble := sin(_time) * 0.5 + sin(_time * 2.3 + 1.7) * 0.35 + sin(_time * 5.1) * 0.15
	light.light_energy = base_energy * (1.0 + wobble * flicker_amount)
	flame.scale = Vector3.ONE * (1.0 + wobble * 0.12)
