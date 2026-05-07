extends Control
class_name MultiplayerPanel

## Multiplayer entry — Create Game / Browse Games / Back. Mirrors the
## ContinuePanel structure so the startup screen flow stays consistent.

signal back_pressed
signal create_pressed
signal browse_pressed

const TITLE_FONT_SIZE := 16
const BUTTON_SIZE := Vector2(280.0, 40.0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func _build_ui() -> void:
	var back := Button.new()
	back.text = "COMMON_BACK"
	back.custom_minimum_size = Vector2(120.0, 32.0)
	back.position = Vector2(16.0, 16.0)
	back.size = Vector2(120.0, 32.0)
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "MENU_MULTIPLAYER"
	title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override(&"font_color", Color(0.85, 0.92, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var create_btn := Button.new()
	create_btn.text = "MENU_MP_CREATE"
	create_btn.custom_minimum_size = BUTTON_SIZE
	create_btn.pressed.connect(func() -> void: create_pressed.emit())
	vbox.add_child(create_btn)

	var browse_btn := Button.new()
	browse_btn.text = "MENU_MP_BROWSE"
	browse_btn.custom_minimum_size = BUTTON_SIZE
	browse_btn.pressed.connect(func() -> void: browse_pressed.emit())
	vbox.add_child(browse_btn)
