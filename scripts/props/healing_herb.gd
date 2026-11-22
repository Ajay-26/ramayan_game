extends Area3D
## Glowing sanjeevani herb. Walk through it to heal.

@export var amount := 25.0

var _time := randf() * 10.0

@onready var plant: Node3D = $Plant


func _ready() -> void:
	collision_layer = 0
	collision_mask = Combat.LAYER_PLAYER
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_time += delta
	plant.position.y = 0.3 + sin(_time * 2.0) * 0.08
	plant.rotate_y(delta * 0.8)


func _on_body_entered(body: Node3D) -> void:
	var player := body as Player
	if player == null or player.is_dead() or player.health >= player.max_health:
		return
	player.heal(amount)
	FX.shockwave(global_position, 1.5, Color(0.4, 1.0, 0.6, 0.8))
	var hud := get_tree().get_first_node_in_group("hud")
	if hud:
		hud.show_toast("+%d health" % int(amount))
	queue_free()
