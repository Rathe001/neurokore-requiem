extends Control
class_name MissionsPanel

## Mission tracker panel — stacked under the Combat Effects panel in
## the top-right corner. Reads from the MissionState autoload and
## re-renders on its `changed` signal. Phase transitions (switches done
## → boss alive → boss dead) animate the previously-active line into a
## green checkmark before the new phase replaces it.

const PANEL_WIDTH: float = 210.0
const PANEL_TITLE: String = "Missions"
const STACK_GAP: float = 4.0
const TITLE_FONT_SIZE: int = 11
const HEADER_FONT_SIZE: int = 9
const TIP_FONT_SIZE: int = 8
const TITLE_COLOR := Color(0.95, 0.92, 0.85, 1.0)
const HEADER_COLOR := Color(0.95, 0.85, 0.5, 1.0)
const TIP_COLOR := Color(0.78, 0.78, 0.78, 0.85)
const CHECK_COLOR := Color(0.45, 1.0, 0.55, 1.0)
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.55)
const TITLE_DIVIDER_COLOR := Color(0.95, 0.85, 0.5, 0.35)
const EMPTY_PLACEHOLDER := "No active missions"

# Checkmark animation timing.
const CHECK_POP_IN: float = 0.22   # scale 0 → 1.25 → 1.0
const CHECK_HOLD: float = 1.1      # stay legible after the pop
const CHECK_FADE_OUT: float = 0.35 # fade alpha 1 → 0 before swap

var _bg: ColorRect
var _vbox: VBoxContainer
var _quirk_panel: WeaponQuirkPanel = null
var _last_phase: StringName = MissionState.PHASE_NONE
var _last_label: String = ""
var _check_label: Label = null
var _check_tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	var map_margin := Minimap.CORNER_MARGIN
	offset_left = -PANEL_WIDTH - map_margin
	offset_right = -map_margin
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)

	_bg = ColorRect.new()
	_bg.color = PANEL_BG
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	_vbox = VBoxContainer.new()
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override(&"separation", 1)
	_vbox.offset_left = 5.0
	_vbox.offset_top = 3.0
	_vbox.offset_right = -5.0
	_vbox.offset_bottom = -3.0
	add_child(_vbox)

	# Track the sibling combat-effects panel so we can dock just below
	# its bottom edge. The panel may resize whenever the player swaps
	# weapons, so we listen to its layout_changed signal and reposition.
	_quirk_panel = get_tree().get_first_node_in_group(&"weapon_quirk_panel") as WeaponQuirkPanel
	if _quirk_panel == null:
		# Fall back to a sibling lookup — HUD scene parents both panels
		# under Root so a sibling named WeaponQuirkPanel is the usual case.
		var sib := get_parent().get_node_or_null(^"WeaponQuirkPanel") if get_parent() != null else null
		if sib is WeaponQuirkPanel:
			_quirk_panel = sib
	if _quirk_panel != null:
		_quirk_panel.layout_changed.connect(_reposition_under_quirks)

	MissionState.changed.connect(_on_mission_state_changed)
	_last_phase = MissionState.current_phase()
	_last_label = MissionState.current_label()
	refresh()
	_reposition_under_quirks()


func _on_mission_state_changed() -> void:
	var new_phase: StringName = MissionState.current_phase()
	# Phase transition (not just a switch-count tick): the previously
	# active phase just completed. Play the checkmark animation over the
	# old label before swapping to the new one. Resetting to PHASE_NONE
	# (level reset) is a wipe, not a completion — skip the animation.
	if new_phase != _last_phase and _last_phase != MissionState.PHASE_NONE and new_phase != MissionState.PHASE_NONE:
		_play_checkmark(_last_label)
	_last_phase = new_phase
	_last_label = MissionState.current_label()
	refresh()


func refresh() -> void:
	# Don't clobber an in-flight checkmark — the animation owns the panel
	# until it expires, then the next refresh() (kicked by _show_current
	# at the end of the tween) repaints from current state.
	if _check_label != null and is_instance_valid(_check_label):
		return
	for child in _vbox.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = PANEL_TITLE
	title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override(&"font_color", TITLE_COLOR)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(title)
	var divider := ColorRect.new()
	divider.color = TITLE_DIVIDER_COLOR
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(divider)
	var label_text: String = MissionState.current_label()
	if label_text == "":
		var empty := Label.new()
		empty.text = EMPTY_PLACEHOLDER
		empty.add_theme_font_size_override(&"font_size", TIP_FONT_SIZE)
		empty.add_theme_color_override(&"font_color", TIP_COLOR)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vbox.add_child(empty)
	else:
		var tip := Label.new()
		tip.text = label_text
		tip.add_theme_font_size_override(&"font_size", TIP_FONT_SIZE)
		tip.add_theme_color_override(&"font_color", TIP_COLOR)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size = Vector2(PANEL_WIDTH - 10.0, 0.0)
		tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vbox.add_child(tip)
	call_deferred(&"_resize_to_content")


# Replaces the active mission line with a green "✓ <previous label>"
# that pops in, holds, fades out, then triggers a normal refresh so the
# next phase's label takes over. Kill any in-flight checkmark first so
# back-to-back phase transitions don't pile up.
func _play_checkmark(prev_label: String) -> void:
	if _check_tween != null and _check_tween.is_valid():
		_check_tween.kill()
	if _check_label != null and is_instance_valid(_check_label):
		_check_label.queue_free()
		_check_label = null
	# Clear current children except the title + divider so the checkmark
	# sits where the active objective was.
	for child in _vbox.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = PANEL_TITLE
	title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override(&"font_color", TITLE_COLOR)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(title)
	var divider := ColorRect.new()
	divider.color = TITLE_DIVIDER_COLOR
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(divider)
	_check_label = Label.new()
	_check_label.text = "✓ %s" % prev_label
	_check_label.add_theme_font_size_override(&"font_size", TIP_FONT_SIZE)
	_check_label.add_theme_color_override(&"font_color", CHECK_COLOR)
	_check_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_check_label.custom_minimum_size = Vector2(PANEL_WIDTH - 10.0, 0.0)
	_check_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_check_label.pivot_offset = Vector2(0.0, 0.0)
	_check_label.scale = Vector2(0.6, 0.6)
	_check_label.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_vbox.add_child(_check_label)
	call_deferred(&"_resize_to_content")
	# Pop-in scale + alpha together, then hold, then fade out. On
	# completion the checkmark is removed and refresh() renders the new
	# phase label.
	_check_tween = create_tween()
	_check_tween.set_parallel(true)
	_check_tween.tween_property(_check_label, "scale", Vector2(1.25, 1.25), CHECK_POP_IN * 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_check_tween.tween_property(_check_label, "modulate:a", 1.0, CHECK_POP_IN * 0.6)
	_check_tween.chain()
	_check_tween.tween_property(_check_label, "scale", Vector2(1.0, 1.0), CHECK_POP_IN * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_check_tween.chain()
	_check_tween.tween_interval(CHECK_HOLD)
	_check_tween.chain()
	_check_tween.tween_property(_check_label, "modulate:a", 0.0, CHECK_FADE_OUT)
	_check_tween.chain()
	_check_tween.tween_callback(_on_check_finished)


func _on_check_finished() -> void:
	if _check_label != null and is_instance_valid(_check_label):
		_check_label.queue_free()
	_check_label = null
	_check_tween = null
	refresh()


func _resize_to_content() -> void:
	custom_minimum_size.y = _vbox.size.y + 8.0
	size.y = custom_minimum_size.y


# Position offset_top so this panel sits just below the quirks panel's
# bottom edge (or directly under the minimap when quirks is hidden).
# Triggered by quirks panel's layout_changed; also called once during
# _ready so the initial position is correct.
func _reposition_under_quirks() -> void:
	var map_margin := Minimap.CORNER_MARGIN
	var map_size := Minimap.CORNER_SIZE
	var minimap_bottom := map_margin + map_size + 4.0
	if _quirk_panel != null and _quirk_panel.visible:
		offset_top = _quirk_panel.bottom_edge_y + STACK_GAP
	else:
		offset_top = minimap_bottom


