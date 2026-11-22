extends Area3D
## The divine chakra resting on the shrine pedestal. Walking up to it grants it.

signal picked

@export var speaker := "Vishwamitra"
@export var lines: PackedStringArray = []

var _time := 0.0

@onready var chakra_visual: Node3D = $Chakra


func _ready() -> void:
	collision_layer = 0
	collision_mask = Combat.LAYER_PLAYER
	body_entered.connect(_on_body_entered)
	if Game.has_chakra:
		queue_free()


func _process(delta: float) -> void:
	_time += delta
	chakra_visual.rotate_y(delta * 2.5)
	chakra_visual.position.y = 1.6 + sin(_time * 1.8) * 0.12


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if player == null:
		return
	player.unlock_chakra()
	FX.divine_blast(chakra_visual.global_position - Vector3.UP, 3.0)
	FX.hitstop(0.1)
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_banner("The Divine Chakra")
		if not lines.is_empty():
			hud.queue_captions(speaker, lines)
	picked.emit()
	queue_free()
