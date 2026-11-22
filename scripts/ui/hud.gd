extends CanvasLayer
## On-screen UI: health and astra bars, chakra status, lock-on reticle, bow
## charge, takedown prompt, story captions, banners, objective and boss bars,
## pause menu, death screen, and the gritty vignette/grain overlay.
## Built in code to keep the greybox simple; it gets a proper art pass later.

const GOLD := Color(1.0, 0.78, 0.3)
const HEALTH_FILL := Color(0.85, 0.2, 0.15)
const ASTRA_FILL := Color(0.45, 0.6, 1.0)

var _player: Player
var _health_bar: ProgressBar
var _health_lag: ProgressBar
var _astra_bar: ProgressBar
var _ability_label: Label
var _banner: Label
var _location: Label
var _toast: Label
var _center: Label
var _prompt: Label
var _caption_speaker: Label
var _caption_text: Label
var _caption_box: PanelContainer
var _objective_label: Label
var _objective_bar: ProgressBar
var _boss_box: VBoxContainer
var _boss_bar: ProgressBar
var _boss_label: Label
var _fps: Label
var _reticle: Reticle
var _crosshair: Crosshair
var _pause_menu: VBoxContainer
var _overlay_mat: ShaderMaterial
var _hurt := 0.0
var _banner_tween: Tween
var _toast_tween: Tween
var _location_tween: Tween
var _captions: Array = []  # [speaker, text] pairs
var _caption_left := 0.0
var _objective_node: Node
var _boss: Enemy
var _astra_hint_shown := false


func _ready() -> void:
	add_to_group("hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_connect_player.call_deferred()


func _connect_player() -> void:
	_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null:
		return
	_player.health_changed.connect(_on_health_changed)
	_player.died.connect(func() -> void: _caption_box.visible = false)
	_player.astra_ready.connect(_on_astra_ready)
	_health_bar.max_value = _player.max_health
	_health_lag.max_value = _player.max_health
	_health_bar.value = _player.health
	_health_lag.value = _player.health
	_astra_bar.max_value = _player.astra_max


func _process(delta: float) -> void:
	# Real-time delta, so the UI keeps moving during hit-stop.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	_fps.text = "%d FPS" % Engine.get_frames_per_second()
	_health_lag.value = move_toward(_health_lag.value, _health_bar.value, 40.0 * real_delta)
	if _health_lag.value < _health_bar.value:
		_health_lag.value = _health_bar.value
	_hurt = maxf(_hurt - real_delta * 2.5, 0.0)
	_overlay_mat.set_shader_parameter("hurt_amount", _hurt)
	_update_player_ui()
	_update_captions(real_delta)
	_update_objective()
	_update_boss()


func _unhandled_input(event: InputEvent) -> void:
	# Clicking back into the game re-locks the mouse (browsers release it on Esc).
	if event is InputEventMouseButton and event.pressed and not get_tree().paused 			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and get_tree().current_scene.has_node("CameraRig"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("pause") and not (_player and _player.is_dead()):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()


# --- Public API -------------------------------------------------------------

func show_banner(text: String) -> void:
	if _banner_tween and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner.text = text
	_banner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner, "modulate:a", 1.0, 0.25)
	_banner_tween.tween_interval(1.6)
	_banner_tween.tween_property(_banner, "modulate:a", 0.0, 0.6)


func show_toast(text: String) -> void:
	if _toast_tween and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.8)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


func show_location(text: String) -> void:
	if _location_tween and _location_tween.is_valid():
		_location_tween.kill()
	_location.text = text
	_location.modulate.a = 0.0
	_location_tween = create_tween()
	_location_tween.tween_property(_location, "modulate:a", 1.0, 1.0)
	_location_tween.tween_interval(2.5)
	_location_tween.tween_property(_location, "modulate:a", 0.0, 1.2)


func queue_captions(speaker: String, lines: PackedStringArray) -> void:
	for line in lines:
		_captions.append([speaker, line])
	if _caption_left <= 0.0:
		_next_caption()


func show_death(text: String) -> void:
	_center.text = text
	_center.modulate.a = 0.0
	create_tween().tween_property(_center, "modulate:a", 1.0, 0.8)


func track_objective(text: String, node: Node) -> void:
	_objective_node = node
	_objective_label.text = text
	_objective_label.visible = text != ""
	_objective_bar.visible = node != null and "health" in node


func show_boss(enemy: Enemy) -> void:
	_boss = enemy
	_boss_label.text = enemy.get("boss_name") if enemy.get("boss_name") else "BOSS"
	_boss_bar.max_value = enemy.max_health
	_boss_bar.value = enemy.health
	_boss_box.visible = true


func hide_boss() -> void:
	_boss = null
	_boss_box.visible = false


# --- Updates ----------------------------------------------------------------

func _on_health_changed(current: float, _maximum: float) -> void:
	if current < _health_bar.value:
		_hurt = 1.0
	_health_bar.value = current


func _on_astra_ready() -> void:
	show_toast("ASTRA READY  —  R / LB")
	if not _astra_hint_shown:
		_astra_hint_shown = true
		queue_captions("Vishwamitra", PackedStringArray(["The divine weapon answers you, Rama. Loose the astra! (R / LB)"]))


func _update_player_ui() -> void:
	if _player == null:
		return
	_astra_bar.value = _player.astra
	var full := _player.astra >= _player.astra_max
	(_astra_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = GOLD if full else ASTRA_FILL

	var parts: PackedStringArray = []
	if _player.has_chakra:
		parts.append("CHAKRA  Q" if _player.chakra_ready else "chakra returning…")
	if _player.is_sneaking:
		parts.append("SNEAKING")
	_ability_label.text = "    ".join(parts)

	if _player.takedown_candidate and not _player.is_dead():
		_prompt.text = "LMB / F  —  Takedown"
		_prompt.visible = true
	else:
		_prompt.visible = false

	var cam := get_viewport().get_camera_3d()
	var target := _player.current_target
	_crosshair.visible = _player.is_aiming
	if _player.is_aiming:
		_crosshair.position = get_viewport().get_visible_rect().size * 0.5
		_crosshair.charge = _player.bow_charge
		_crosshair.locked = _player.aim_assist_target() != null
		_crosshair.queue_redraw()
		_reticle.visible = false
	elif cam and Combat.is_alive_target(target) and not cam.is_position_behind(Combat.aim_point(target)):
		_reticle.visible = true
		_reticle.position = cam.unproject_position(Combat.aim_point(target))
		_reticle.charge = _player.bow_charge
		_reticle.queue_redraw()
	else:
		_reticle.visible = false


func _next_caption() -> void:
	if _captions.is_empty():
		_caption_box.visible = false
		_caption_left = 0.0
		return
	var entry: Array = _captions.pop_front()
	_caption_speaker.text = String(entry[0]).to_upper()
	_caption_speaker.visible = String(entry[0]) != ""
	_caption_text.text = String(entry[1])
	_caption_box.visible = true
	# Longer lines stay up longer.
	_caption_left = clampf(1.5 + String(entry[1]).length() * 0.055, 2.5, 7.0)


func _update_captions(real_delta: float) -> void:
	if get_tree().paused or _caption_left <= 0.0:
		return
	_caption_left -= real_delta
	if _caption_left <= 0.0:
		_next_caption()


func _update_objective() -> void:
	if _objective_bar.visible and is_instance_valid(_objective_node):
		_objective_bar.max_value = _objective_node.max_health
		_objective_bar.value = _objective_node.health


func _update_boss() -> void:
	if _boss and is_instance_valid(_boss):
		_boss_bar.value = maxf(_boss.health, 0.0)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	_pause_menu.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	if paused:
		(_pause_menu.get_child(1) as Button).grab_focus()


# --- Layout -----------------------------------------------------------------

func _build() -> void:
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = load("res://shaders/vignette_grain.gdshader")
	overlay.material = _overlay_mat
	add_child(overlay)

	_reticle = Reticle.new()
	_reticle.visible = false
	add_child(_reticle)
	_crosshair = Crosshair.new()
	_crosshair.visible = false
	add_child(_crosshair)

	var name_label := _label("RAMA", 20, GOLD)
	name_label.position = Vector2(28, 18)
	add_child(name_label)
	_health_lag = _bar(Color(1.0, 0.85, 0.6, 0.9), Color(0.05, 0.03, 0.05, 0.85), Vector2(28, 48), Vector2(320, 16))
	add_child(_health_lag)
	_health_bar = _bar(HEALTH_FILL, Color(0, 0, 0, 0), Vector2(28, 48), Vector2(320, 16))
	add_child(_health_bar)
	_astra_bar = _bar(ASTRA_FILL, Color(0.05, 0.03, 0.08, 0.85), Vector2(28, 70), Vector2(220, 8))
	add_child(_astra_bar)
	_ability_label = _label("", 15, Color(1, 0.9, 0.7, 0.9))
	_ability_label.position = Vector2(28, 84)
	add_child(_ability_label)

	_banner = _centered_label(44, GOLD, 70)
	_banner.modulate.a = 0.0
	add_child(_banner)
	_location = _centered_label(30, Color(1, 0.92, 0.8), 130)
	_location.modulate.a = 0.0
	add_child(_location)
	_toast = _centered_label(20, Color(1, 0.95, 0.85), 180)
	_toast.modulate.a = 0.0
	add_child(_toast)

	_objective_label = _label("", 18, Color(1, 0.9, 0.75))
	_objective_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_objective_label.offset_left = -330
	_objective_label.offset_top = 40
	_objective_label.visible = false
	add_child(_objective_label)
	_objective_bar = _bar(Color(1, 0.55, 0.15), Color(0.05, 0.03, 0.05, 0.85), Vector2.ZERO, Vector2(300, 12))
	_objective_bar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_objective_bar.position = Vector2(-330, 68)
	_objective_bar.visible = false
	add_child(_objective_bar)

	_boss_box = VBoxContainer.new()
	_boss_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_boss_box.offset_left = -360
	_boss_box.offset_right = 360
	_boss_box.offset_top = -78
	_boss_box.offset_bottom = -30
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_box.visible = false
	_boss_label = _label("", 22, Color(1, 0.55, 0.3))
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_box.add_child(_boss_label)
	_boss_bar = _bar(Color(0.75, 0.12, 0.08), Color(0.05, 0.03, 0.05, 0.85), Vector2.ZERO, Vector2(720, 18))
	_boss_bar.custom_minimum_size = Vector2(720, 18)
	_boss_box.add_child(_boss_bar)
	add_child(_boss_box)

	_caption_box = PanelContainer.new()
	var caption_style := StyleBoxFlat.new()
	caption_style.bg_color = Color(0.02, 0.01, 0.04, 0.72)
	caption_style.set_content_margin_all(14)
	caption_style.set_corner_radius_all(4)
	_caption_box.add_theme_stylebox_override("panel", caption_style)
	_caption_box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_caption_box.offset_left = -420
	_caption_box.offset_right = 420
	_caption_box.offset_top = -200
	_caption_box.offset_bottom = -110
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box.visible = false
	var caption_column := VBoxContainer.new()
	caption_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_speaker = _label("", 16, GOLD)
	_caption_text = _label("", 21, Color(1, 0.96, 0.9))
	_caption_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption_column.add_child(_caption_speaker)
	caption_column.add_child(_caption_text)
	_caption_box.add_child(caption_column)
	add_child(_caption_box)

	_prompt = _centered_label(22, Color(1, 0.95, 0.8), 0)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_top = 90
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.visible = false
	add_child(_prompt)

	_center = _label("", 40, Color(1, 0.9, 0.8))
	_center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_center.grow_vertical = Control.GROW_DIRECTION_BOTH
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_center)

	_fps = _label("", 13, Color(1, 1, 1, 0.45))
	_fps.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_fps.offset_left = -80
	_fps.offset_top = 12
	add_child(_fps)

	var hint := _label("Mouse look   WASD move   LMB punch   MMB sword   RMB aim + LMB shoot (hold: charge)   Shift dodge   Space jump   Q chakra   C sneak   R astra   Esc pause", 13, Color(1, 1, 1, 0.45))
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 24
	hint.offset_top = -30
	add_child(hint)

	_build_pause_menu()


func _build_pause_menu() -> void:
	_pause_menu = VBoxContainer.new()
	_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_pause_menu.offset_left = -140
	_pause_menu.offset_right = 140
	_pause_menu.offset_top = -110
	_pause_menu.offset_bottom = 110
	_pause_menu.add_theme_constant_override("separation", 12)
	_pause_menu.visible = false
	var title := _label("PAUSED", 40, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_menu.add_child(title)
	_pause_menu.add_child(_button("Resume", func() -> void: _set_paused(false)))
	_pause_menu.add_child(_button("Restart from checkpoint", func() -> void: Game.restart_from_checkpoint()))
	_pause_menu.add_child(_button("Main menu", func() -> void: Game.goto(Game.MAIN_MENU)))
	add_child(_pause_menu)


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(on_press)
	return button


func _bar(fill: Color, background: Color, pos: Vector2, bar_size: Vector2) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.position = pos
	bar.size = bar_size
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill_box := StyleBoxFlat.new()
	fill_box.bg_color = fill
	var bg_box := StyleBoxFlat.new()
	bg_box.bg_color = background
	if background.a > 0.0:
		bg_box.border_color = GOLD
		bg_box.set_border_width_all(2)
	bar.add_theme_stylebox_override("fill", fill_box)
	bar.add_theme_stylebox_override("background", bg_box)
	return bar


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", maxi(font_size / 6, 3))
	return label


func _centered_label(font_size: int, color: Color, top: float) -> Label:
	var label := _label("", font_size, color)
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	label.offset_top = top
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


## Bow crosshair at the center of the screen while aiming. Turns gold when
## aim assist has an enemy; the outer ring fills as the bow charges.
class Crosshair:
	extends Control

	var charge := -1.0
	var locked := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var color := Color(1, 0.8, 0.3, 0.95) if locked else Color(1, 1, 1, 0.85)
		var shadow := Color(0, 0, 0, 0.5)
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_line(d * 6.0, d * 14.0, shadow, 4.0)
			draw_line(d * 6.0, d * 14.0, color, 2.0)
		draw_circle(Vector2.ZERO, 1.8, color)
		if charge >= 0.0:
			var c := Color(1, 1, 1, 0.95) if charge >= 1.0 else Color(1, 0.6, 0.2, 0.95)
			draw_arc(Vector2.ZERO, 20.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 32, c, 3.0)


## Lock-on marker drawn over the current target; fills as the bow charges.
class Reticle:
	extends Control

	var charge := -1.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var color := Color(1, 0.85, 0.4, 0.9)
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, Color(0, 0, 0, 0.5), 4.0)
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 32, color, 2.0)
		draw_circle(Vector2.ZERO, 2.5, color)
		if charge >= 0.0:
			var c := Color(1, 1, 1, 0.95) if charge >= 1.0 else Color(1, 0.6, 0.2, 0.95)
			draw_arc(Vector2.ZERO, 22.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 32, c, 4.0)
