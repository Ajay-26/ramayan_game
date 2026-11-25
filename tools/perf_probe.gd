extends Node
## Dev tool: loads the level and prints frame times with individual visual
## features switched off, to find what is expensive.
##   Godot --path . res://tools/perf_probe.tscn

const LEVEL := "res://scenes/levels/siddhashrama.tscn"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.checkpoint = 0
	var level: Node = load(LEVEL).instantiate()
	add_child(level)
	await _measure(level, "all on", 3.0)
	var env := (level.get_node("WorldEnvironment") as WorldEnvironment).environment
	var hud := level.get_node("HUD")
	var overlay: CanvasItem = hud.get_child(0)
	overlay.visible = false
	await _measure(level, "grade off", 2.0)
	level.get_node("Atmosphere").visible = false
	await _measure(level, "+ atmosphere off", 2.0)
	env.glow_enabled = false
	await _measure(level, "+ glow off", 2.0)
	env.fog_enabled = false
	await _measure(level, "+ fog off", 2.0)
	env.background_mode = Environment.BG_COLOR
	await _measure(level, "+ sky off", 2.0)
	get_tree().quit()


func _measure(level: Node, label: String, seconds: float) -> void:
	# Let any shader compiles from the change finish first.
	for i in 30:
		await get_tree().process_frame
	var frames := 0
	var start := Time.get_ticks_usec()
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		if get_tree().paused:
			level.get_node("HUD")._set_paused(false)
		await get_tree().process_frame
		frames += 1
	var ms := (Time.get_ticks_usec() - start) / 1000.0 / maxf(frames, 1)
	print("%-20s %6.1f ms/frame  (%d frames)" % [label, ms, frames])
