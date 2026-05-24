class_name HostMigratingScreen
extends CanvasLayer

## Full-screen overlay shown during a host-migration handshake. Mirror of
## [`HostDisconnectedScreen`] but expresses "we're trying to recover" instead
## of "session over." Reads HostMigration.state each tick so the player can
## see which phase is in flight; if migration fails, [`PrototypeRoot`]
## handles the swap to the disconnect screen — this overlay just goes away.
##
## Visibility is critical for async testing: with this on screen, a tester
## can screenshot what phase a migration stalled in and the log + screenshot
## together pinpoint the bug.
##
## Spawned by PrototypeRoot on HostMigration.migration_starting; frees
## itself on HostMigration.migration_completed.

const STATE_LABELS: Dictionary = {
	0: "Idle",            # HostMigration.State.IDLE
	1: "Electing host",   # ELECTING
	2: "Reconnecting",    # REBINDING
	3: "Restoring world", # REAUTHING
	4: "Resuming",        # RESUMING
}

const OVERLAY_COLOR := Color(0.04, 0.04, 0.10, 0.55)
const FADE_DURATION := 0.25
const TITLE_FONT_SIZE := 24
const MSG_FONT_SIZE := 13
const SCREEN_LAYER := 110

var _overlay: ColorRect
var _title: Label
var _state_label: Label
var _elapsed_label: Label
var _start_msec: int = 0


func _ready() -> void:
	layer = SCREEN_LAYER
	_start_msec = Time.get_ticks_msec()
	_build_ui()
	set_process(true)


func show_migrating() -> void:
	visible = true
	_title.text = "HOST DISCONNECTED"
	_state_label.text = "Migrating session…"
	_elapsed_label.text = "0.0s"
	_overlay.color.a = 0.0
	_title.modulate.a = 0.0
	_state_label.modulate.a = 0.0
	_elapsed_label.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_overlay, "color:a", OVERLAY_COLOR.a, FADE_DURATION)
	tween.parallel().tween_property(_title, "modulate:a", 1.0, FADE_DURATION)
	tween.parallel().tween_property(_state_label, "modulate:a", 1.0, FADE_DURATION)
	tween.parallel().tween_property(_elapsed_label, "modulate:a", 0.6, FADE_DURATION)


# Tick the readout so the tester can see which migration phase is active.
# Reads HostMigration.state each frame — cheap (single int compare).
func _process(_delta: float) -> void:
	var s: int = HostMigration.state
	var label: String = STATE_LABELS.get(s, "Unknown state %d" % s)
	if s == HostMigration.State.IDLE:
		# Migration completed (success or fail); PrototypeRoot will free us.
		# Stop updating to avoid flicker.
		return
	_state_label.text = label
	var elapsed: float = float(Time.get_ticks_msec() - _start_msec) / 1000.0
	_elapsed_label.text = "%.1fs" % elapsed


func hide_and_free() -> void:
	# Quick fade-out then queue_free. PrototypeRoot calls this when
	# HostMigration.migration_completed(true) fires.
	set_process(false)
	var tween := create_tween()
	tween.tween_property(_overlay, "color:a", 0.0, 0.2)
	tween.parallel().tween_property(_title, "modulate:a", 0.0, 0.2)
	tween.parallel().tween_property(_state_label, "modulate:a", 0.0, 0.2)
	tween.parallel().tween_property(_elapsed_label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(queue_free)


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = OVERLAY_COLOR
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Block input so the player can't interact while gameplay is paused.
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.offset_left = -220.0
	vbox.offset_right = 220.0
	vbox.offset_top = -60.0
	vbox.offset_bottom = 60.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override(&"separation", 12)
	_overlay.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	# Muted amber — same palette as HostDisconnectedScreen so the two
	# overlays read as related states of the same event.
	_title.add_theme_color_override(&"font_color", Color(0.9, 0.65, 0.3))
	vbox.add_child(_title)

	_state_label = Label.new()
	_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_state_label.add_theme_font_size_override(&"font_size", MSG_FONT_SIZE)
	_state_label.add_theme_color_override(&"font_color", Color(0.85, 0.85, 0.85))
	vbox.add_child(_state_label)

	_elapsed_label = Label.new()
	_elapsed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_elapsed_label.add_theme_font_size_override(&"font_size", MSG_FONT_SIZE - 2)
	_elapsed_label.add_theme_color_override(&"font_color", Color(0.6, 0.6, 0.6))
	vbox.add_child(_elapsed_label)
