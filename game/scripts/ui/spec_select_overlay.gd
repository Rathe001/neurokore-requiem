class_name SpecSelectOverlay
extends CanvasLayer

# Full-screen overlay shown once after the first level clear (NG+1).
# Presents the player's origin class + its 3 specialized classes.
# Pauses the game tree while visible; unpauses on selection.

signal class_selected(class_id: StringName, spec_id: StringName)

const BG_COLOR := Color(0.02, 0.02, 0.04, 0.92)
const CARD_COL_GAP := 12.0
const CARD_ROW_GAP := 6.0


# Class label resolver. Reads from AttributeState.CLASS_DEFINITIONS /
# ORIGIN_DEFINITIONS so adding a class is one edit (the metadata dict),
# not three (label + glyph + backstory in parallel UI tables). Count
# remains the only gendered exception.
static func get_class_label(class_or_spec_id: StringName) -> String:
	if class_or_spec_id == &"count":
		return "STARTUP_PICK_ANALOG_COUNTESS" if PlayerState.gender == &"female" else "STARTUP_PICK_ANALOG_COUNT"
	if AttributeState.CLASS_DEFINITIONS.has(class_or_spec_id):
		return AttributeState.CLASS_DEFINITIONS[class_or_spec_id].get(&"label_key", "")
	if AttributeState.ORIGIN_DEFINITIONS.has(class_or_spec_id):
		return AttributeState.ORIGIN_DEFINITIONS[class_or_spec_id].get(&"label_key", "")
	return ""

static func get_class_glyph(class_or_spec_id: StringName) -> String:
	if AttributeState.CLASS_DEFINITIONS.has(class_or_spec_id):
		return AttributeState.CLASS_DEFINITIONS[class_or_spec_id].get(&"glyph", "?")
	if AttributeState.ORIGIN_DEFINITIONS.has(class_or_spec_id):
		return AttributeState.ORIGIN_DEFINITIONS[class_or_spec_id].get(&"glyph", "?")
	return "?"

static func get_class_backstory(class_or_spec_id: StringName) -> String:
	if AttributeState.CLASS_DEFINITIONS.has(class_or_spec_id):
		return AttributeState.CLASS_DEFINITIONS[class_or_spec_id].get(&"backstory_key", "")
	if AttributeState.ORIGIN_DEFINITIONS.has(class_or_spec_id):
		return AttributeState.ORIGIN_DEFINITIONS[class_or_spec_id].get(&"backstory_key", "")
	return ""

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

	# Tier-rules note: explains the perk-tier ceiling/floor difference between
	# specialized and origin classes so the player understands what "picking a
	# specialization" actually trades off before they commit.
	var note := RichTextLabel.new()
	note.bbcode_enabled = true
	note.text = TranslationServer.translate("SPEC_TIER_NOTE")
	note.fit_content = true
	note.scroll_active = false
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override(&"normal_font_size", 11)
	note.add_theme_color_override(&"default_color", Color(0.85, 0.9, 1.0, 0.7))
	note.anchor_left = 0.5
	note.anchor_right = 0.5
	note.offset_left = -360.0
	note.offset_right = 360.0
	note.offset_top = 104.0
	note.offset_bottom = 160.0
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(note)

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
		"label_key": get_class_label(origin),
		"glyph": get_class_glyph(origin),
		"stat": stat_key,
		"opposes": opposes_key,
		"backstory": get_class_backstory(origin),
	}

func _make_spec_entry(origin: StringName, spec_id: StringName) -> Dictionary:
	var stat: StringName = AttributeState.CLASS_DEFINITIONS[spec_id][&"stat"]
	var nemesis: StringName = AttributeState.NEMESIS_STAT.get(stat, &"")
	return {
		"class_id": origin,
		"spec_id": spec_id,
		"label_key": get_class_label(spec_id),
		"glyph": get_class_glyph(spec_id),
		"stat": AttributeState.STAT_I18N.get(stat, ""),
		"opposes": AttributeState.STAT_I18N.get(nemesis, ""),
		"backstory": get_class_backstory(spec_id),
	}

func _on_pick(cid: StringName, sid: StringName) -> void:
	visible = false
	get_tree().paused = false
	class_selected.emit(cid, sid)
	if _root != null:
		_root.queue_free()
		_root = null
