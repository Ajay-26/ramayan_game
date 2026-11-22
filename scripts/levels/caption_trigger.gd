extends Area3D
## Shows story/tutorial captions when Rama walks in (once).

@export var speaker := ""
@export var lines: PackedStringArray = []
@export var banner := ""

var _used := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = Combat.LAYER_PLAYER
	body_entered.connect(_on_body_entered)


func disable() -> void:
	_used = true


func _on_body_entered(body: Node3D) -> void:
	if _used or not (body is Player):
		return
	_used = true
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	if banner != "":
		hud.show_banner(banner)
	if not lines.is_empty():
		hud.queue_captions(speaker, lines)
