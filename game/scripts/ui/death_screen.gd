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
const OVERLAY_COLOR := Color(0.25, 0.02, 0.02, 0.42)
const FADE_DURATION := 0.6
const BUTTON_DELAY := 1.2
const BUTTON_SIZE := Vector2(200.0, 40.0)
const TITLE_FONT_SIZE := 28
const MSG_FONT_SIZE := 13

# Cause-keyed snarky death messages. The death screen rolls a random entry
# from the matching list when shown. New environmental causes hook in by
# adding a key here AND calling player.set_death_cause(&"key") just before
# take_damage; if a cause has no entry the GENERIC list is used.
const _SNARK_GENERIC: Array[String] = [
	"Skill issue.",
	"Ow. That looked like it hurt.",
	"Maybe try not standing in the bullets next time?",
	"Your enemies send their regards.",
	"You died doing what you loved: making poor decisions.",
	"Have you considered dodging?",
	"Heroic. Briefly.",
	"That'll buff out.",
]
const _SNARK_PIT: Array[String] = [
	"You might want to try jumping harder next time.",
	"The floor wasn't your friend after all.",
	"Should've seen that hole coming.",
	"Gravity remains undefeated.",
	"That pit had your name on it. Specifically.",
]
const _SNARK_BY_CAUSE: Dictionary = {
	&"pit": _SNARK_PIT,
}
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


func show_death(hardcore: bool, cause: StringName = &"") -> void:
	_hardcore = hardcore
	visible = true
	if hardcore:
		_title.text = "DEATH IS PERMANENT"
		_message.text = "Your journey ends here.\nThis character has been lost forever."
		_button.text = "Back to Main Menu"
	else:
		_title.text = "YOU HAVE DIED"
		_message.text = _pick_snark(cause)
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


func _pick_snark(cause: StringName) -> String:
	var pool: Array[String] = _SNARK_BY_CAUSE.get(cause, _SNARK_GENERIC)
	if pool.is_empty():
		pool = _SNARK_GENERIC
	return pool[randi() % pool.size()]


func _reveal_button() -> void:
	_button.visible = true
	_button.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_button, "modulate:a", 1.0, 0.3)


func _on_button_pressed() -> void:
	if _hardcore:
		if PlayerState.active_save_id != "":
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
	# Snarky one-liners can run a touch long — wrap rather than overflow.
	# custom_minimum_size pins the wrap width so the label sizes vertically.
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.custom_minimum_size = Vector2(380.0, 0.0)
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
