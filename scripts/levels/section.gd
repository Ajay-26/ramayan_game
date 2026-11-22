class_name Section
extends Node3D
## One stretch of the level. Has a checkpoint where it begins ("CheckpointArea"
## + "Spawn" marker), and an exit gate that opens once every requirement inside
## (encounters, bell puzzles) is complete.

signal completed

@export var index := 0
@export var title := ""
@export var exit_gate_path: NodePath

var _requirements: Array[Node] = []
var _done := false


func _ready() -> void:
	for node in find_children("*", "", true, false):
		if node.is_in_group("requirement"):
			_requirements.append(node)
			node.completed.connect(_check)
	var area := get_node_or_null("CheckpointArea") as Area3D
	if area:
		area.collision_layer = 0
		area.collision_mask = Combat.LAYER_PLAYER
		area.body_entered.connect(_on_checkpoint_entered)


func spawn_point() -> Node3D:
	return get_node("Spawn") as Node3D


func find_requirement(node_name: String) -> Node:
	for r in _requirements:
		if r.name == node_name:
			return r
	return null


## Respawning past this section: everything here counts as done.
func skip_completed() -> void:
	_done = true
	for r in _requirements:
		r.skip()
	for node in find_children("*", "", true, false):
		if node.has_method("disable"):
			node.disable()
	var gate := get_node_or_null(exit_gate_path)
	if gate:
		gate.open(true)


func _on_checkpoint_entered(body: Node3D) -> void:
	var player := body as Player
	if player == null:
		return
	if Game.reach_checkpoint(index):
		player.heal(player.max_health)
		var hud := get_tree().get_first_node_in_group("hud")
		if hud:
			hud.show_toast("Checkpoint")
			if title != "":
				hud.show_location(title)


func _check() -> void:
	if _done:
		return
	for r in _requirements:
		if not r.is_complete():
			return
	_done = true
	var gate := get_node_or_null(exit_gate_path)
	if gate:
		gate.open()
	completed.emit()
