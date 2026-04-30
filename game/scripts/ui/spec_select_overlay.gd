class_name SpecSelectOverlay
extends CanvasLayer

# Full-screen overlay shown once after the first level clear (NG+1).
# Presents the player's origin class + its 3 specialized classes.
# Pauses the game tree while visible; unpauses on selection.

signal class_selected(class_id: StringName, spec_id: StringName)

const BG_COLOR := Color(0.02, 0.02, 0.04, 0.92)
const CARD_COL_GAP := 12.0
const CARD_ROW_GAP := 6.0

const SPEC_GLYPHS: Dictionary = {
	&"analog": "H", &"cyborg": "C",
	&"count": "G", &"survivalist": "S", &"enculted": "E",
	&"forged": "F", &"automaton": "A", &"polymath": "P",
}

const SPEC_BACKSTORIES: Dictionary = {
	&"analog": "STARTUP_BACKSTORY_ANALOG",
	&"cyborg": "STARTUP_BACKSTORY_CYBORG",
	&"count": "STARTUP_BACKSTORY_COUNT",
	&"survivalist": "STARTUP_BACKSTORY_SURVIVALIST",
	&"enculted": "STARTUP_BACKSTORY_ENCULTED",
	&"forged": "STARTUP_BACKSTORY_FORGED",
	&"automaton": "STARTUP_BACKSTORY_AUTOMATON",
	&"polymath": "STARTUP_BACKSTORY_POLYMATH",
}

const SPEC_LABELS: Dictionary = {
	&"analog": "STARTUP_PICK_ANALOG",
	&"cyborg": "STARTUP_PICK_CYBORG",
	&"survivalist": "STARTUP_PICK_ANALOG_SURVIVALIST",
	&"enculted": "STARTUP_PICK_ANALOG_ENCULTED",
	&"forged": "STARTUP_PICK_CYBORG_FORGED",
	&"automaton": "STARTUP_PICK_CYBORG_AUTOMATON",
	&"polymath": "STARTUP_PICK_CYBORG_POLYMATH",
}

static func get_spec_label(spec_id: StringName) -> String:
	if spec_id == &"count":
		return "STARTUP_PICK_ANALOG_COUNTESS" if PlayerState.gender == &"female" else "STARTUP_PICK_ANALOG_COUNT"
	return SPEC_LABELS.get(spec_id, "")

var _root: Control

func show_for_origin(origin: StringName) -> void:
	_build_ui(origin)
	visible = true
	get_tree().paused = true
	process_mode = Node.PROCESS_MODE_ALWAYS

func _build_ui(origin: StringName) -> void:
	if _root != null:
		_root.queue_free()

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UIThemeState.theme
	add_child(_root)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)

	var title := Label.new()
	title.text = "STARTUP_TITLE_SPEC"
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_top = 60.0
	title.offset_bottom = 96.0
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(title)

	# Build the list of choices: origin class + 3 specs
	var picks: Array[Dictionary] = []
	picks.append(_make_origin_entry(origin))
	for spec_id: StringName in AttributeState.CLASS_DEFINITIONS:
		if AttributeState.CLASS_DEFINITIONS[spec_id][&"origin"] == origin:
			picks.append(_make_spec_entry(origin, spec_id))

	var rows := int(ceil(float(picks.size()) / 2.0))
	var total_width := ClassCardBuilder.CARD_SIZE.x * 2.0 + CARD_COL_GAP
	var total_height := ClassCardBuilder.CARD_SIZE.y * float(rows) + CARD_ROW_GAP * float(rows - 1)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override(&"h_separation", int(CARD_COL_GAP))
	grid.add_theme_constant_override(&"v_separation", int(CARD_ROW_GAP))
	grid.anchor_left = 0.5
	grid.anchor_right = 0.5
	grid.anchor_top = 0.5
	grid.anchor_bottom = 0.5
	grid.offset_left = -total_width * 0.5
	grid.offset_right = total_width * 0.5
	grid.offset_top = -total_height * 0.5 + 10.0
	grid.offset_bottom = total_height * 0.5 + 10.0
	_root.add_child(grid)

	for entry in picks:
		var cid: StringName = entry["class_id"]
		var sid: StringName = entry["spec_id"]
		grid.add_child(ClassCardBuilder.build(entry, func() -> void: _on_pick(cid, sid)))

func _make_origin_entry(origin: StringName) -> Dictionary:
	var stat_key: String
	var opposes_key: String
	if origin == &"analog":
		stat_key = "STAT_SOUL"
		opposes_key = "STAT_INTERFACE"
	else:
		stat_key = "STAT_INTERFACE"
		opposes_key = "STAT_SOUL"
	return {
		"class_id": origin,
		"spec_id": &"",
		"label_key": get_spec_label(origin),
		"glyph": SPEC_GLYPHS.get(origin, "?"),
		"stat": stat_key,
		"opposes": opposes_key,
		"backstory": SPEC_BACKSTORIES.get(origin, ""),
	}

func _make_spec_entry(origin: StringName, spec_id: StringName) -> Dictionary:
	var stat: StringName = AttributeState.CLASS_DEFINITIONS[spec_id][&"stat"]
	var nemesis: StringName = AttributeState.NEMESIS_STAT.get(stat, &"")
	return {
		"class_id": origin,
		"spec_id": spec_id,
		"label_key": get_spec_label(spec_id),
		"glyph": SPEC_GLYPHS.get(spec_id, "?"),
		"stat": AttributeState.STAT_I18N.get(stat, ""),
		"opposes": AttributeState.STAT_I18N.get(nemesis, ""),
		"backstory": SPEC_BACKSTORIES.get(spec_id, ""),
	}

func _on_pick(cid: StringName, sid: StringName) -> void:
	visible = false
	get_tree().paused = false
	class_selected.emit(cid, sid)
	if _root != null:
		_root.queue_free()
		_root = null
