extends Node3D
## The Tataka fight: her entrance, the boss bar, a wider camera, the storm she
## brings (a low cloud deck over the fort, rain, darkness, lightning), stage
## banners and captions, healing herbs between stages, and the end of the
## level when she falls.

signal defeated

const STAGE_BANNERS := {
	2: "Tataka rises into the storm",
	3: "Tataka calls her brood",
	4: "Maya: she vanishes into the clouds",
	5: "Tataka is enraged",
}
const STAGE_CAPTIONS := {
	2: ["Vishwamitra", "She rides the storm! Your arrows, Rama: bring her down!"],
	3: ["Vishwamitra", "Her children answer her. Do not let them surround you."],
	4: ["Vishwamitra", "Maya... she hides inside the storm. Watch for the lightning!"],
	5: ["Vishwamitra", "She is wounded and mad with rage. Stand firm, Rama!"],
}
## The storm at each stage: [cloud deck density, rain, darkness 0..1].
const STORM := {
	1: [0.4, false, 0.0],
	2: [0.85, true, 0.2],
	3: [0.7, true, 0.15],
	4: [1.0, true, 0.6],
	5: [0.9, true, 0.35],
}
## Stages that drop healing herbs as they begin.
const HERB_STAGES := [3, 5]
const HERB_SCENE := preload("res://scenes/props/healing_herb.tscn")
const CLOUD_SHADER := preload("res://shaders/storm_clouds.gdshader")

@export var tataka_path: NodePath
@export var intro_lines: PackedStringArray = []
## How much further out the camera sits during the boss fight.
@export var arena_camera_distance := 1.5
@export var arena_camera_extra_fov := 4.0
## ...and while she's in the sky, so Rama can see her and the ground.
@export var air_camera_distance := 1.8
@export var air_camera_extra_fov := 8.0
## Restart a lost fight from the stage reached, instead of from the start.
## Off by default: the fight is meant to be learned and won in one go.
@export var stage_checkpoints := false
@export var cloud_deck_height := 19.0

var tataka: Tataka
var _started := false
var _deck_mat: ShaderMaterial
var _deck_density := 0.0
var _lightning_left := 6.0
var _was_airborne := false


func _ready() -> void:
	tataka = get_node(tataka_path) as Tataka
	var spawns: Array[Node3D] = []
	for marker in get_node("AddSpawns").get_children():
		spawns.append(marker as Node3D)
	tataka.add_spawn_points = spawns
	var center := get_node_or_null("ArenaCenter") as Node3D
	if center:
		tataka.arena_center = center.global_position
	var altar := get_node_or_null("../YagnaAltar") as Node3D
	if altar:
		tataka.keep_clear.append(altar.global_position)
	tataka.defeated.connect(func() -> void:
		_set_storm(0.15, false, 0.0, 4.0)
		Sfx.music("music_calm", 4.0)
		defeated.emit())
	tataka.stage_changed.connect(_on_stage_changed)
	tataka.finisher_ready.connect(_on_finisher_ready)
	set_process(false)


func start() -> void:
	if _started:
		return
	_started = true
	var hud := _hud()
	var rig := _rig()
	if rig:
		rig.set_framing(arena_camera_distance, arena_camera_extra_fov)
	_build_cloud_deck()
	var first_stage := Game.boss_stage if stage_checkpoints and Game.boss_stage > 1 else 1
	if first_stage > 1:
		tataka.start_at_stage(first_stage)
	_apply_stage_storm(first_stage, 3.0)
	Sfx.music("music_boss", 1.5)
	tataka.enter_arena()
	if hud:
		hud.show_boss(tataka)
		if not intro_lines.is_empty() and first_stage == 1:
			hud.queue_captions("Tataka", intro_lines)
	set_process(true)


func _process(delta: float) -> void:
	if tataka.is_dead():
		return
	# Far-off lightning once the storm is up (stage 4 has her own reveals too).
	if tataka.stage >= 2:
		_lightning_left -= delta
		if _lightning_left <= 0.0:
			_lightning_left = randf_range(5.0, 11.0)
			var atmosphere := _atmosphere()
			if atmosphere:
				var dir := Vector3(randf_range(-1, 1), randf_range(0.2, 0.6), randf_range(-1, 1))
				atmosphere.lightning(randf_range(0.35, 0.6), dir)
	# Pull the camera out while she flies.
	if tataka.airborne != _was_airborne:
		_was_airborne = tataka.airborne
		var rig := _rig()
		if rig:
			if _was_airborne:
				rig.set_framing(air_camera_distance, air_camera_extra_fov)
			else:
				rig.set_framing(arena_camera_distance, arena_camera_extra_fov)
	if _deck_mat:
		var atmosphere := _atmosphere()
		_deck_mat.set_shader_parameter("lightning", atmosphere.flash_level() if atmosphere else 0.0)


func _on_stage_changed(stage: int) -> void:
	if stage_checkpoints:
		Game.boss_stage = stage
	_apply_stage_storm(stage, 3.0)
	var hud := _hud()
	if hud == null:
		return
	if STAGE_BANNERS.has(stage):
		hud.show_banner(STAGE_BANNERS[stage])
	if STAGE_CAPTIONS.has(stage):
		var line: Array = STAGE_CAPTIONS[stage]
		hud.queue_captions(line[0], PackedStringArray([line[1]]))
	if stage in HERB_STAGES:
		_drop_herbs()


func _on_finisher_ready() -> void:
	var hud := _hud()
	if hud:
		hud.show_banner("Strike the final blow")


func _apply_stage_storm(stage: int, fade: float) -> void:
	var storm: Array = STORM.get(stage, STORM[1])
	_set_storm(storm[0], storm[1], storm[2], fade)


func _set_storm(density: float, rain: bool, darkness: float, fade: float) -> void:
	var atmosphere := _atmosphere()
	if atmosphere:
		atmosphere.set_storm(rain, darkness, fade)
	if _deck_mat:
		var tween := create_tween()
		tween.tween_method(func(v: float) -> void:
			_deck_density = v
			_deck_mat.set_shader_parameter("density", v), _deck_density, density, fade)


## Healing herbs sprout at the arena's edges when some stages begin.
func _drop_herbs() -> void:
	var spots := get_node_or_null("HerbSpawns")
	if spots == null:
		return
	for marker in spots.get_children():
		var herb := HERB_SCENE.instantiate() as Node3D
		add_child(herb)
		herb.global_position = (marker as Node3D).global_position
		FX.spawn_puff(herb.global_position)


## A low ceiling of storm cloud over the fort for her to vanish into.
func _build_cloud_deck() -> void:
	var atmosphere := _atmosphere()
	_deck_mat = ShaderMaterial.new()
	_deck_mat.shader = CLOUD_SHADER
	_deck_mat.set_shader_parameter("density", 0.0)
	if atmosphere and atmosphere.cloud_texture():
		_deck_mat.set_shader_parameter("clouds", atmosphere.cloud_texture())
	var plane := PlaneMesh.new()
	plane.size = Vector2(150, 150)
	plane.flip_faces = true  # seen from below
	plane.material = _deck_mat
	var deck := MeshInstance3D.new()
	deck.name = "CloudDeck"
	deck.mesh = plane
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(deck)
	deck.global_position = tataka.arena_center + Vector3.UP * cloud_deck_height


func _hud() -> Node:
	return get_tree().get_first_node_in_group("hud")


func _rig() -> CameraRig:
	return get_tree().get_first_node_in_group("camera_rig") as CameraRig


func _atmosphere() -> Atmosphere:
	return get_tree().get_first_node_in_group("atmosphere") as Atmosphere
