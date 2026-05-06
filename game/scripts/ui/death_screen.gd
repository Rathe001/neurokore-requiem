class_name DeathScreen
extends CanvasLayer

## Full-screen death overlay. Shows a dark-red tinted screen with a message
## and a single action button. Normal mode: "Continue" triggers respawn.
## Hardcore mode: "Back to Main Menu" returns to the startup screen.
##
## Usage:
##   var screen := DeathScreen.new()
##   add_child(screen)
##   screen.show_death(hardcore)
##   screen.continue_pressed.connect(_on_death_continue)

signal continue_pressed

const STARTUP_SCENE := "res://scenes/ui/startup_screen.tscn"
const OVERLAY_COLOR := Color(0.25, 0.02, 0.02, 0.72)
const FADE_DURATION := 0.6
const BUTTON_DELAY := 1.2
const BUTTON_SIZE := Vector2(200.0, 40.0)
const TITLE_FONT_SIZE := 28
const MSG_FONT_SIZE := 16
## Render above the HUD and everything else.
const DEATH_LAYER := 110

var _overlay: ColorRect
var _title: Label
var _message: Label
var _button: Button
var _hardcore: bool = false


func _ready() -> void:
	layer = DEATH_LAYER
	_build_ui()


func show_death(hardcore: bool) -> void:
	_hardcore = hardcore
	visible = true
	if hardcore:
		_title.text = "DEATH IS PERMANENT"
		_message.text = "Your journey ends here.\nThis character has been lost forever."
		_button.text = "Back to Main Menu"
	else:
		_title.text = "YOU HAVE DIED"
		_message.text = "Steel yourself and try again."
		_button.text = "Continue"

	# Fade the overlay in, then reveal the button after a short delay so
	# the player doesn't accidentally click through.
	_overlay.color.a = 0.0
	_title.modulate.a = 0.0
	_message.modulate.a = 0.0
	_button.visible = false

	var tween := create_tween()
	tween.tween_property(_overlay, "color:a", OVERLAY_COLOR.a, FADE_DURATION)
	tween.parallel().tween_property(_title, "modulate:a", 1.0, FADE_DURATION)
	tween.parallel().tween_property(_message, "modulate:a", 1.0, FADE_DURATION)
	tween.tween_interval(BUTTON_DELAY - FADE_DURATION)
	tween.tween_callback(_reveal_button)


func _reveal_button() -> void:
	_button.visible = true
	_button.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_button, "modulate:a", 1.0, 0.3)


func _on_button_pressed() -> void:
	if _hardcore:
		SaveManager.delete_save(PlayerState.active_save_id)
		PlayerState.reset()
		InventoryState.reset()
		get_tree().change_scene_to_file(STARTUP_SCENE)
	else:
		continue_pressed.emit()
		queue_free()


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = OVERLAY_COLOR
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.offset_left = -200.0
	vbox.offset_right = 200.0
	vbox.offset_top = -80.0
	vbox.offset_bottom = 80.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override(&"separation", 16)
	_overlay.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	_title.add_theme_color_override(&"font_color", Color(0.9, 0.15, 0.12))
	vbox.add_child(_title)

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override(&"font_size", MSG_FONT_SIZE)
	_message.add_theme_color_override(&"font_color", Color(0.78, 0.72, 0.7))
	vbox.add_child(_message)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	vbox.add_child(spacer)

	_button = Button.new()
	_button.custom_minimum_size = BUTTON_SIZE
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.pressed.connect(_on_button_pressed)
	_button.visible = false
	vbox.add_child(_button)
