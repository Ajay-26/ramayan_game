class_name Encounter
extends Node3D
## One fight.
##   "Placed" child: enemies already standing there (often unaware, for stealth).
##   "Wave1", "Wave2"... children: spawn points, spawned one wave after another.
##   "Trigger" child (Area3D): Rama walking in starts the fight.
## A fight also starts when any placed enemy notices Rama or dies.
## Completes when every enemy from every wave is dead.

signal started
signal completed

## Thing the spawned enemies attack instead of Rama when he's away (yagna altar).
@export var objective_path: NodePath
## Gate that slams shut when the fight starts and opens when it's won.
@export var lock_gate_path: NodePath
@export var start_banner := ""
@export var wave_delay := 1.5
## When the fight starts, every placed enemy notices Rama. Off for stealth areas,
## where each sentry has to spot Rama for itself.
@export var alert_all_on_start := true

var _started := false
var _complete := false
var _spawning := false
var _alive := 0
var _wave_index := 0
var _waves: Array[Node] = []


func _ready() -> void:
	add_to_group("requirement")
	for child in get_children():
		if child.name.begins_with("Wave"):
			_waves.append(child)
	var placed := get_node_or_null("Placed")
	if placed:
		for node in placed.get_children():
			var enemy := node as Enemy
			if enemy:
				_alive += 1
				enemy.died.connect(_on_enemy_died)
				enemy.alerted.connect(func(_e: Enemy) -> void: start())
	var trigger := get_node_or_null("Trigger") as Area3D
	if trigger:
		trigger.collision_layer = 0
		trigger.collision_mask = Combat.LAYER_PLAYER
		trigger.body_entered.connect(func(body: Node3D) -> void:
			if body is Player:
				start())


func is_started() -> bool:
	return _started


func is_complete() -> bool:
	return _complete


func alive_count() -> int:
	return _alive


func start() -> void:
	if _started or _complete:
		return
	_started = true
	started.emit()
	Sfx.music("music_battle")
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and start_banner != "":
		hud.show_banner(start_banner)
	var gate := get_node_or_null(lock_gate_path)
	if gate:
		gate.close()
	if alert_all_on_start:
		var placed := get_node_or_null("Placed")
		if placed:
			for node in placed.get_children():
				if node is Enemy and not node.is_dead():
					node.become_aware(false)
	# The first wave joins any placed enemies right away; later waves wait.
	if not _waves.is_empty():
		_spawn_next_wave()
	elif _alive == 0:
		_finish()


## Mark as already won (respawning at a later checkpoint).
func skip() -> void:
	_started = true
	_complete = true
	for node in find_children("*", "", true, false):
		if node is Enemy:
			node.queue_free()


func _spawn_next_wave() -> void:
	if _wave_index >= _waves.size():
		_finish()
		return
	var wave := _waves[_wave_index]
	_wave_index += 1
	_spawning = true
	var objective := get_node_or_null(objective_path) as Node3D
	var points: Array[Node] = []
	for point in wave.get_children():
		if point.get("enemy_scene") != null:
			points.append(point)
	_alive += points.size()
	for point in points:
		var enemy := (point.enemy_scene as PackedScene).instantiate() as Enemy
		enemy.position = to_local((point as Node3D).global_position)
		enemy.start_yaw_degrees = (point as Node3D).rotation_degrees.y
		if point.stationary and "stationary" in enemy:
			enemy.stationary = true
		enemy.objective = objective
		enemy.died.connect(_on_enemy_died)
		add_child(enemy)
		await get_tree().create_timer(0.25).timeout
		if not is_inside_tree():
			return
	_spawning = false
	_check_done()


func _on_enemy_died(_enemy: Enemy) -> void:
	_alive -= 1
	if not _started:
		start()  # killing a sentry silently still counts toward clearing the area
	_check_done.call_deferred()


func _check_done() -> void:
	if _complete or not _started or _spawning or _alive > 0:
		return
	if _wave_index < _waves.size():
		_spawning = true
		await get_tree().create_timer(wave_delay).timeout
		if is_inside_tree():
			_spawn_next_wave()
		return
	_finish()


func _finish() -> void:
	if _complete:
		return
	_complete = true
	var gate := get_node_or_null(lock_gate_path)
	if gate:
		gate.open()
	completed.emit()
	Sfx.music("music_calm")
