extends Node3D
## The Tataka fight: her entrance, boss health bar, wider camera, phase
## banners, and the end of the level when she falls.

signal defeated

@export var tataka_path: NodePath
@export var intro_lines: PackedStringArray = []
## How much further out the camera sits during the boss fight.
@export var arena_camera_distance := 1.5
@export var arena_camera_extra_fov := 4.0

var tataka: Tataka
var _started := false


func _ready() -> void:
	tataka = get_node(tataka_path) as Tataka
	var spawns: Array[Node3D] = []
	for marker in get_node("AddSpawns").get_children():
		spawns.append(marker as Node3D)
	tataka.add_spawn_points = spawns
	tataka.defeated.connect(func() -> void: defeated.emit())
	tataka.phase_changed.connect(_on_phase_changed)


func start() -> void:
	if _started:
		return
	_started = true
	var hud := get_tree().get_first_node_in_group("hud")
	var rig := get_tree().get_first_node_in_group("camera_rig") as CameraRig
	if rig:
		rig.set_framing(arena_camera_distance, arena_camera_extra_fov)
	tataka.enter_arena()
	if hud:
		hud.show_boss(tataka)
		if not intro_lines.is_empty():
			hud.queue_captions("Tataka", intro_lines)


func _on_phase_changed(phase: int) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	if phase == 2:
		hud.show_banner("Tataka calls her brood")
	elif phase == 3:
		hud.show_banner("Tataka is enraged")
