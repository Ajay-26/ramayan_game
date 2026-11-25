extends Node
## Dev tool: loads the level at a few checkpoints and saves screenshots, for
## checking the look after lighting / post-processing changes.
## Run (needs a window, not --headless):
##   Godot --path . res://tools/screenshot.tscn -- <out_dir> [checkpoint ...]
## Checkpoint "6" waits for Tataka's entrance and frames her; "6:3" starts the
## fight at stage 3 (and so on), to see each stage's storm.

const LEVEL := "res://scenes/levels/siddhashrama.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "user://shots"
	var checkpoints := args.slice(1) if args.size() > 1 else PackedStringArray(["0", "2", "3", "5", "6"])
	DirAccess.make_dir_recursive_absolute(out_dir)
	for c in checkpoints:
		var parts := (c as String).split(":")
		await _shoot(int(parts[0]), out_dir, int(parts[1]) if parts.size() > 1 else 1)
	get_tree().quit()


func _shoot(checkpoint: int, out_dir: String, boss_stage: int) -> void:
	Game.checkpoint = checkpoint
	Game.boss_stage = boss_stage
	var level: Node = load(LEVEL).instantiate()
	level.get_node("Sections/S5/Boss").set("stage_checkpoints", boss_stage > 1)
	add_child(level)
	var rig := level.get_node("CameraRig") as CameraRig
	var player := level.get_node("Player") as Player
	var wait := 1.5
	if checkpoint >= Game.CHECKPOINT_BOSS:
		wait = 8.0
	await _wait(level, wait)
	if checkpoint >= Game.CHECKPOINT_BOSS:
		var boss := level.get_node("Sections/S5/Boss")
		var tataka := boss.get("tataka") as Node3D
		if tataka:
			var ground := Vector3(tataka.global_position.x, 0.0, tataka.global_position.z)
			player.teleport(Vector3(3, 0, -252), (ground - Vector3(3, 0, -252)).normalized())
			rig.snap()
			await _wait(level, 0.1)
			rig.look_toward(tataka.global_position + Vector3.UP * 3.0)
	else:
		rig.pitch = deg_to_rad(-10.0)
	await _wait(level, 0.6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var file := out_dir.path_join("cp%d%s.png" % [checkpoint, "_s%d" % boss_stage if boss_stage > 1 else ""])
	img.save_png(file)
	print("saved ", file)
	level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


## Waits, un-pausing if the window losing focus paused the game.
func _wait(level: Node, seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if get_tree().paused:
			level.get_node("HUD")._set_paused(false)
		await get_tree().process_frame
