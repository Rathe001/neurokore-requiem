class_name HostDisconnectedScreen
extends CanvasLayer

## Full-screen overlay shown to clients when the host (peer 1) disconnects
## mid-session. The architecture is a fixed peer-1 server with no failover
## authority — when the host drops, clients can't continue (no enemy
## spawning, no state sync, no host snapshots). This overlay freezes input,
## explains the situation, and offers a single "Return to Main Menu"
## action.
##
## Spawn pattern matches DeathScreen — instantiate, add as a child, call
## show_disconnected(). The screen owns its lifetime and frees itself on
## the menu transition.

const STARTUP_SCENE := "res://scenes/ui/startup_screen.tscn"
const OVERLAY_COLOR := Color(0.04, 0.04, 0.08, 0.65)
const FADE_DURATION := 0.4
const BUTTON_DELAY := 0.8
const BUTTON_SIZE := Vector2(220.0, 40.0)
const TITLE_FONT_SIZE := 28
const MSG_FONT_SIZE := 13
# Render above the HUD and the chat panel.
const SCREEN_LAYER := 110

var _overlay: ColorRect
var _title: Label
var _message: Label
var _button: Button


func _ready() -> void:
	layer = SCREEN_LAYER
	_build_ui()


func show_disconnected() -> void:
	visible = true
	_title.text = "HOST DISCONNECTED"
	_message.text = "The session host left the game.\nReturn to the main menu to start a new run."
	_button.text = "Return to Main Menu"
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
	# Tear down the multiplayer session before transitioning. leave_lobby
	# closes the peer, clears NetState's lobby_id, and emits lobby_left
	# so any other listeners (chat panel, etc) clean up too.
	NetState.leave_lobby()
	get_tree().change_scene_to_file(STARTUP_SCENE)


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = OVERLAY_COLOR
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# MOUSE_FILTER_STOP catches every click in the play area so buttons
	# behind the overlay can't be activated. The Return button is the
	# only interactive element while this is up.
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.offset_left = -220.0
	vbox.offset_right = 220.0
	vbox.offset_top = -80.0
	vbox.offset_bottom = 80.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override(&"separation", 16)
	_overlay.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	# Muted amber — signals "session over" without the alarm-red tone of
	# the death screen. This isn't a failure state, it's an end-of-run.
	_title.add_theme_color_override(&"font_color", Color(0.9, 0.65, 0.3))
	vbox.add_child(_title)

	_message = Label.new()
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override(&"font_size", MSG_FONT_SIZE)
	_message.add_theme_color_override(&"font_color", Color(0.78, 0.72, 0.7))
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(420.0, 0.0)
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
