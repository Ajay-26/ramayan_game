extends Control
## Title screen: Begin / Continue / Controls / Quit.

const GOLD := Color(1.0, 0.78, 0.3)

var _controls_panel: Control
var _buttons: VBoxContainer
var _glow: ColorRect
var _time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build()


func _process(delta: float) -> void:
	_time += delta
	# Slow firelight pulse behind the title.
	_glow.modulate.a = 0.55 + sin(_time * 1.7) * 0.1 + sin(_time * 4.3) * 0.04


func _build() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.02, 0.07)
	add_child(bg)

	_glow = ColorRect.new()
	_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	var glow_mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
void fragment() {
	vec2 p = UV - vec2(0.5, 0.75);
	p.x *= 1.6;
	float d = length(p);
	vec3 fire = vec3(1.0, 0.42, 0.12) * smoothstep(0.75, 0.0, d);
	vec3 sky = mix(vec3(0.03, 0.02, 0.1), vec3(0.28, 0.1, 0.2), smoothstep(0.0, 1.0, UV.y));
	COLOR = vec4(sky + fire * 0.55, 1.0);
}
"""
	glow_mat.shader = shader
	_glow.material = glow_mat
	add_child(_glow)

	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	column.offset_left = -300
	column.offset_right = 300
	column.offset_top = -230
	column.offset_bottom = 230
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 10)
	add_child(column)

	column.add_child(_label("RAMAYAN", 84, GOLD))
	column.add_child(_label("The Night of Tataka", 28, Color(1, 0.9, 0.8)))
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	column.add_child(spacer)

	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 10)
	column.add_child(_buttons)
	if Game.has_progress():
		_buttons.add_child(_button("Continue", Game.continue_game))
	_buttons.add_child(_button("Begin", Game.new_game))
	_buttons.add_child(_button("Controls", _toggle_controls))
	if not OS.has_feature("web"):
		_buttons.add_child(_button("Quit", get_tree().quit))
	(_buttons.get_child(0) as Button).grab_focus.call_deferred()

	var footer := _label("A fan-made prototype inspired by the Ramayana  ·  greybox build", 14, Color(1, 1, 1, 0.4))
	footer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	footer.offset_top = -40
	footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(footer)

	_controls_panel = _build_controls()
	_controls_panel.visible = false
	add_child(_controls_panel)


func _build_controls() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.01, 0.04, 0.95)
	style.border_color = GOLD
	style.set_border_width_all(2)
	style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -330
	panel.offset_right = 330
	panel.offset_top = -250
	panel.offset_bottom = 250
	var text := _label("", 18, Color(1, 0.95, 0.88))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.text = """CONTROLS                         Keyboard / Mouse        Gamepad

Look around                    Mouse                       Right stick
Move                               WASD                       Left stick
Punch (light)                   Left click / J             X / Square
Sword (heavy)                  Middle click / K         Y / Triangle
Aim bow                          Right click / E           LT / L2
Shoot (hold to charge)       Left click (aiming)     RT / R2
Throw chakra (homing)      Q                               RB / R1
Dodge roll                         Shift                         B / Circle
Jump / Sneak                    Space / C                 A / L3
Takedown (from behind)   Left click / F             X / Square
Astra (when full)              R                               LB / L1
Pause                              Esc / P                     Start

Combos:  L L L  ·  L H  ·  L L H   (H alone: slow sword swing)
Brutes block from the front: hit them from behind, or break
their guard with a charged arrow or the L L H sword slam."""
	var column := VBoxContainer.new()
	column.add_child(text)
	column.add_child(_button("Back", _toggle_controls))
	panel.add_child(column)
	return panel


func _toggle_controls() -> void:
	_controls_panel.visible = not _controls_panel.visible
	_buttons.visible = not _controls_panel.visible
	if _controls_panel.visible:
		(_controls_panel.get_child(0).get_child(1) as Button).grab_focus()
	else:
		(_buttons.get_child(0) as Button).grab_focus()


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(260, 48)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 22)
	button.pressed.connect(on_press)
	return button


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", maxi(font_size / 8, 3))
	return label
