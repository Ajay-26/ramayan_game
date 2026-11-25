extends Node
## Game-wide state that survives scene reloads: checkpoint progress, unlocked
## abilities, and moving between the menu, story cards, and the level.

const MAIN_MENU := "res://scenes/ui/main_menu.tscn"
const STORY := "res://scenes/ui/story.tscn"
const LEVEL := "res://scenes/levels/siddhashrama.tscn"
## Put your feedback form link here (Google Form, itch.io comments, etc.).
## The outro shows a "Leave feedback" button when this is set.
const FEEDBACK_URL := ""

## Checkpoints: 0 forest, 1 sentries, 2 camp, 3 ravine, 4 shrine, 5 yagna, 6 Tataka.
const CHECKPOINT_BOSS := 6

var checkpoint := 0
var has_chakra := false
var deaths := 0
## Tataka stage reached (only used when the boss fight has stage checkpoints).
var boss_stage := 0
## Which set of cards the story scene shows: "intro" or "outro".
var story := "intro"


func new_game() -> void:
	checkpoint = 0
	has_chakra = false
	deaths = 0
	boss_stage = 0
	show_story("intro")


## Straight to the Tataka fight (from the main menu), with the chakra.
func fight_boss() -> void:
	checkpoint = CHECKPOINT_BOSS
	has_chakra = true
	boss_stage = 0
	goto(LEVEL)


func continue_game() -> void:
	goto(LEVEL)


func has_progress() -> bool:
	return checkpoint > 0


func reach_checkpoint(index: int) -> bool:
	if index > checkpoint:
		checkpoint = index
		return true
	return false


func restart_from_checkpoint() -> void:
	deaths += 1
	goto(LEVEL)


func show_story(which: String) -> void:
	story = which
	goto(STORY)


func finish_level() -> void:
	show_story("outro")


func goto(path: String) -> void:
	Sfx.stop_loops(0.5)
	if path != LEVEL:
		Sfx.music("music_calm", 1.5)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file.call_deferred(path)
