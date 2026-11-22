extends Node3D
## The Siddhashrama level: puts Rama at the current checkpoint, fast-forwards
## past finished sections, and runs the yagna defense into the Tataka fight.

const YAGNA_SECTION := 5

@onready var player: Player = $Player
@onready var hud: CanvasLayer = $HUD
@onready var rig: CameraRig = $CameraRig

var sections: Array[Section] = []
var _ending := false


func _ready() -> void:
	Enemy.reset_tokens()
	for child in $Sections.get_children():
		if child is Section:
			sections.append(child)
	sections.sort_custom(func(a: Section, b: Section) -> bool: return a.index < b.index)

	var checkpoint := mini(Game.checkpoint, Game.CHECKPOINT_BOSS)
	for section in sections:
		if section.index < checkpoint:
			section.skip_completed()
	if checkpoint > 4 or Game.has_chakra:
		player.unlock_chakra()

	var spawn_section := sections[mini(checkpoint, sections.size() - 1)]
	var spawn := spawn_section.spawn_point()
	player.teleport(spawn.global_position, -spawn.global_basis.z)
	rig.snap()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED  # mouse steers the camera
	player.died.connect(_on_player_died)

	var yagna_section := sections[YAGNA_SECTION]
	var yagna := yagna_section.get_node("YagnaEncounter") as Encounter
	var boss := yagna_section.get_node("Boss")
	var altar := yagna_section.get_node("YagnaAltar")
	altar.destroyed.connect(_on_altar_destroyed)
	yagna.started.connect(func() -> void: hud.track_objective("Protect the yagna fire", altar))
	boss.defeated.connect(_on_boss_defeated)

	if checkpoint >= Game.CHECKPOINT_BOSS:
		yagna.skip()
		await get_tree().create_timer(1.2).timeout
		boss.start()
	else:
		yagna.completed.connect(func() -> void: _yagna_won(boss))
		hud.show_location(spawn_section.title if spawn_section.title != "" else "Siddhashrama")


func _yagna_won(boss: Node) -> void:
	hud.track_objective("", null)
	Game.reach_checkpoint(Game.CHECKPOINT_BOSS)
	player.heal(player.max_health)
	hud.queue_captions("Vishwamitra", PackedStringArray([
		"The rite holds... but the earth trembles. Something vast comes.",
		"Rama, beware: Tataka, mother of these rakshasas!",
	]))
	await get_tree().create_timer(4.5).timeout
	if is_inside_tree() and not player.is_dead():
		boss.start()


func _on_boss_defeated() -> void:
	if _ending:
		return
	_ending = true
	hud.hide_boss()
	hud.show_banner("Tataka is slain")
	Engine.time_scale = 0.4
	await get_tree().create_timer(1.2, true, false, true).timeout
	Engine.time_scale = 1.0
	hud.queue_captions("Vishwamitra", PackedStringArray([
		"It is done. The forest is free of her at last.",
		"Come, Rama. The fire will burn until dawn.",
	]))
	await get_tree().create_timer(6.0).timeout
	Game.finish_level()


func _on_player_died() -> void:
	if _ending:
		return
	hud.show_death("Rama has fallen…")
	await get_tree().create_timer(3.0).timeout
	Game.restart_from_checkpoint()


func _on_altar_destroyed() -> void:
	if _ending or player.is_dead():
		return
	_ending = true
	hud.show_death("The sacred fire is extinguished…")
	await get_tree().create_timer(3.0).timeout
	Game.restart_from_checkpoint()
