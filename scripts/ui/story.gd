extends Control
## Story cards before and after the level. Any key / click / button advances;
## Esc skips. (Placeholder text on colored backgrounds until the painted art.)

const GOLD := Color(1.0, 0.78, 0.3)

const INTRO := [
	{"title": "Ayodhya", "text": "In the age of Treta, Prince Rama, eldest son of King Dasharatha, is barely more than a boy.", "tint": Color(0.18, 0.1, 0.05)},
	{"title": "The Sage's Request", "text": "The sage Vishwamitra comes to court. Rakshasas defile his sacred fire-rituals in the forest of Siddhashrama.\n\nOnly Rama, he says, can protect the yagna.", "tint": Color(0.14, 0.06, 0.12)},
	{"title": "Into the Forest", "text": "With his brother Lakshmana, Rama follows the sage into the darkening forest, his bow on his back and twin blades at his side.", "tint": Color(0.06, 0.08, 0.14)},
	{"title": "Siddhashrama", "text": "Night falls.\n\nThe forest is not empty.", "tint": Color(0.03, 0.02, 0.06)},
]

const OUTRO := [
	{"title": "Dawn", "text": "Tataka falls, and the forest breathes again.\n\nThe yagna fire burns until dawn. Vishwamitra's rite is complete.", "tint": Color(0.2, 0.1, 0.04)},
	{"title": "To be continued…", "text": "Rama's journey has only begun.", "tint": Color(0.06, 0.04, 0.1)},
	{"title": "Thank you for playing", "text": "This is an early prototype. Tell us what you liked, what felt off, and whether you'd play more.", "tint": Color(0.04, 0.03, 0.06), "end": true},
]

var _cards: Array = []
var _index := 0
var _bg: ColorRect
var _title: Label
var _text: Label
var _hint: Label
var _end_buttons: HBoxContainer
var _content: Control
var _accept_input_after := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_cards = OUTRO if Game.story == "outro" else INTRO
	_build()
	_show(0)


func _process(delta: float) -> void:
	_accept_input_after -= delta


func _unhandled_input(event: InputEvent) -> void:
	if _accept_input_after > 0.0 or _end_buttons.visible:
		return
	var pressed := (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed() and not event.is_echo()
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("pause") and Game.story == "intro":
		_finish()
	else:
		_show(_index + 1)


func _show(index: int) -> void:
	if index >= _cards.size():
		_finish()
		return
	_index = index
	var card: Dictionary = _cards[index]
	_title.text = card["title"]
	_text.text = card["text"]
	var is_end: bool = card.get("end", false)
	_end_buttons.visible = is_end
	_hint.visible = not is_end
	if is_end:
		(_end_buttons.get_child(0) as Button).grab_focus()
	_accept_input_after = 0.6
	_content.modulate.a = 0.0
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_content, "modulate:a", 1.0, 0.8)
	tween.tween_property(_bg, "color", card["tint"], 0.8)


func _finish() -> void:
	if Game.story == "intro":
		Game.goto(Game.LEVEL)
	else:
		Game.goto(Game.MAIN_MENU)


func _build() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.color = Color.BLACK
	add_child(_bg)

	_content = VBoxContainer.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_content.offset_left = -420
	_content.offset_right = 420
	_content.offset_top = -200
	_content.offset_bottom = 200
	(_content as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
	(_content as VBoxContainer).add_theme_constant_override("separation", 26)
	add_child(_content)

	_title = _label(46, GOLD)
	_content.add_child(_title)
	_text = _label(24, Color(1, 0.95, 0.88))
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content.add_child(_text)

	_end_buttons = HBoxContainer.new()
	_end_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	_end_buttons.add_theme_constant_override("separation", 16)
	if Game.FEEDBACK_URL != "":
		_end_buttons.add_child(_button("Leave feedback", func() -> void: OS.shell_open(Game.FEEDBACK_URL)))
	_end_buttons.add_child(_button("Main menu", _finish))
	_content.add_child(_end_buttons)

	_hint = _label(16, Color(1, 1, 1, 0.45))
	_hint.text = "Press any key to continue" + ("   ·   Esc to skip" if Game.story == "intro" else "")
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_top = -50
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	add_child(_hint)


func _button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(220, 46)
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(on_press)
	return button


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", maxi(font_size / 8, 3))
	return label
