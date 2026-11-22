extends Node3D
## Opens the way once every bell child has been rung.

signal completed

var _complete := false


func _ready() -> void:
	add_to_group("requirement")
	for bell in _bells():
		bell.rung.connect(_check)


func is_complete() -> bool:
	return _complete


func rung_count() -> int:
	var count := 0
	for bell in _bells():
		if bell.is_rung:
			count += 1
	return count


func total() -> int:
	return _bells().size()


func skip() -> void:
	for bell in _bells():
		bell.ring(true)


func _bells() -> Array[Node]:
	var out: Array[Node] = []
	for child in get_children():
		if child.has_signal("rung"):
			out.append(child)
	return out


func _check() -> void:
	if _complete:
		return
	var hud := get_tree().get_first_node_in_group("hud")
	if rung_count() >= total():
		_complete = true
		if hud:
			hud.show_toast("The way opens")
		completed.emit()
	elif hud:
		hud.show_toast("Bells rung: %d / %d" % [rung_count(), total()])
