extends Control
class_name TalentsPanel

## Talents panel — 6 class rows (one per rollable stat), each with a progress
## bar driven by equipped gear (AttributeState) and a clickable 5-tier skill
## tree. Talent points are stored in PlayerState and persist with the character.
##
## Tier unlock thresholds are determined by the player's class relationship to
## each stat tree (own / team / opposing). The own-class tree is always fully
## open; team and opposing trees require gear investment to unlock.

const TIER_COUNT := 5
const NODES_PER_TIER := 4
const NODE_ROWS := 2
const NODE_COLS := 2

const PANEL_MARGIN := Vector2(32.0, 28.0)
const TITLE_HEIGHT := 28.0
const TALENT_HEIGHT := 16.0
const NOTE_HEIGHT := 14.0
const HEADER_GAP := 10.0
const ROW_GAP := 10.0
const BAR_HEIGHT := 14.0
const BAR_NODE_GAP := 4.0
const NODE_SIZE := Vector2(24.0, 24.0)
const NODE_GAP := 4.0
const TIER_MARKER_WIDTH := 2.0
const LABEL_WIDTH := 130.0
const LABEL_GAP := 10.0
const CLASS_NAME_HEIGHT := 20.0
const STAT_LINE_HEIGHT := 14.0

const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const BAR_BG_COLOR := Color(0.12, 0.12, 0.12, 0.9)
const NODE_LOCKED_COLOR := Color(0.2, 0.2, 0.2, 0.6)
const NODE_AVAILABLE_ALPHA := 0.12
const NODE_ALLOCATED_ALPHA := 0.45
const TIER_MARKER_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const TALENT_POINT_COLOR := Color(0.95, 0.85, 0.4, 1.0)
const TIER_LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.25)

const ANALOG_GROUP_COLOR := Color(0.65, 0.45, 0.25, 0.06)
const CYBORG_GROUP_COLOR := Color(0.3, 0.85, 1.0, 0.06)
const GROUP_PADDING := Vector2(6.0, 4.0)
const GROUP_GAP := 14.0

const TIERS_OWN: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
const TIERS_TEAM: Array[float] = [0.10, 0.20, 0.35, 0.50, 0.70]
const TIERS_OPPOSING: Array[float] = [0.20, 0.30, 0.45, 0.60, 0.80]

const STAT_ROWS: Array[Dictionary] = [
	{"stat": &"ort", "class": "Gentleman",   "short": "ORT", "origin": &"analog"},
	{"stat": &"ing", "class": "Survivalist", "short": "ING", "origin": &"analog"},
	{"stat": &"amb", "class": "Enculted",    "short": "AMB", "origin": &"analog"},
	{"stat": &"dev", "class": "Forged",      "short": "DEV", "origin": &"cyborg"},
	{"stat": &"opt", "class": "Automaton",   "short": "OPT", "origin": &"cyborg"},
	{"stat": &"cla", "class": "Polymath",    "short": "CLA", "origin": &"cyborg"},
]

## Maps spec_id to the primary stat for that class.
const SPEC_STAT: Dictionary = {
	&"gentleman": &"ort", &"survivalist": &"ing", &"enculted": &"amb",
	&"forged": &"dev",    &"automaton":   &"opt", &"polymath":  &"cla",
}

## Maps spec_id to its origin group.
const SPEC_ORIGIN: Dictionary = {
	&"gentleman": &"analog", &"survivalist": &"analog", &"enculted": &"analog",
	&"forged": &"cyborg",   &"automaton":   &"cyborg", &"polymath":  &"cyborg",
}

var _backdrop: ColorRect
var _panel: PanelContainer
var _content: Control
var _title_label: Label
var _talent_label: Label
var _note_label: Label
var _analog_group_bg: ColorRect
var _cyborg_group_bg: ColorRect
var _rows: Array[Dictionary] = []

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(&"ui_modal")
	theme = UIThemeState.theme
	UIThemeState.changed.connect(func() -> void: theme = UIThemeState.theme; _repaint())
	PlayerState.class_changed.connect(_on_player_class_changed)
	PlayerState.spec_changed.connect(_on_player_class_changed)
	PlayerState.talents_changed.connect(_repaint)
	AttributeState.stats_changed.connect(_on_stats_changed)
	_build_layout()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_talents"):
		if visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()

func open_menu() -> void:
	visible = true

func close_menu() -> void:
	visible = false

# ── Player state helpers ───────────────────────────────────────────────────

func _player_class_stat() -> StringName:
	return SPEC_STAT.get(PlayerState.spec_id, &"")

func _player_class_origin() -> StringName:
	if PlayerState.spec_id != &"":
		return SPEC_ORIGIN.get(PlayerState.spec_id, &"analog")
	return PlayerState.class_id if PlayerState.class_id != &"" else &"analog"

func _compute_pcts() -> Dictionary:
	var rollable: Array[StringName] = [&"ort", &"ing", &"amb", &"dev", &"opt", &"cla"]
	var total := 0
	for s in rollable:
		total += AttributeState.get_stat(s)
	var pcts: Dictionary = {}
	for s in rollable:
		pcts[s] = float(AttributeState.get_stat(s)) / maxf(float(total), 1.0)
	return pcts

func _total_spent() -> int:
	return PlayerState.get_talent_points_spent()

# ── Threshold logic ────────────────────────────────────────────────────────

func _get_tiers_for_stat(row_stat: StringName, row_origin: StringName) -> Array[float]:
	var class_stat := _player_class_stat()
	if class_stat != &"" and row_stat == class_stat:
		return TIERS_OWN
	if row_origin == _player_class_origin():
		return TIERS_TEAM
	return TIERS_OPPOSING

func _calc_unlocked_tier(pct: float, tiers: Array[float]) -> int:
	var unlocked := 0
	for i in TIER_COUNT:
		if pct >= tiers[i]:
			unlocked = i + 1
	return unlocked

# ── Click handling ─────────────────────────────────────────────────────────

func _on_node_clicked(event: InputEvent, stat_id: StringName, tier: int, node_idx: int) -> void:
	if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var row := _find_row(stat_id)
	if row.is_empty():
		return
	var unlocked := _calc_unlocked_tier(row["pct"], row["tiers"])
	if tier + 1 > unlocked:
		return
	var tiers_data: Array = PlayerState.talent_allocations.get(stat_id, [])
	var is_allocated: bool = not tiers_data.is_empty() and tiers_data[tier][node_idx]
	if is_allocated:
		PlayerState.set_talent_alloc(stat_id, tier, node_idx, false)
	elif _total_spent() < PlayerState.talent_points_total:
		PlayerState.set_talent_alloc(stat_id, tier, node_idx, true)

func _find_row(stat_id: StringName) -> Dictionary:
	for row: Dictionary in _rows:
		if row["stat_id"] == stat_id:
			return row
	return {}

# ── Signals ────────────────────────────────────────────────────────────────

func _on_player_class_changed(_id: StringName) -> void:
	if _rows.is_empty():
		return
	_rebuild()

func _on_stats_changed() -> void:
	if _rows.is_empty():
		return
	_refresh_row_pcts()
	_do_layout()
	_repaint()

func _refresh_row_pcts() -> void:
	var pcts := _compute_pcts()
	for row: Dictionary in _rows:
		row["pct"] = pcts.get(row["stat_id"], 0.0)
		row["tiers"] = _get_tiers_for_stat(row["stat_id"], row["origin"])
		var key: StringName = AttributeState.STAT_I18N.get(row["stat_id"], &"")
		var display: String = tr(key) if key != &"" else str(row["stat_id"])
		(row["stat_label"] as Label).text = "%s  %d%%" % [display, int(row["pct"] * 100)]

func _rebuild() -> void:
	for row: Dictionary in _rows:
		(row["container"] as Control).queue_free()
	_rows.clear()
	var pcts := _compute_pcts()
	for row_def: Dictionary in STAT_ROWS:
		_rows.append(_build_row(row_def, pcts))
	_do_layout()
	_repaint()

# ── Build ──────────────────────────────────────────────────────────────────

func _build_layout() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = BACKDROP_COLOR
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	_content = Control.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_content)

	_title_label = Label.new()
	_title_label.text = "TALENTS"
	_title_label.theme_type_variation = &"CardTitle"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_title_label)

	_talent_label = Label.new()
	_talent_label.theme_type_variation = &"SmallLabel"
	_talent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(_talent_label)

	_note_label = Label.new()
	_note_label.theme_type_variation = &"SmallLabel"
	_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note_label.text = "Percentages reflect share of total stat allocation from equipped gear"
	_content.add_child(_note_label)

	_analog_group_bg = ColorRect.new()
	_analog_group_bg.color = ANALOG_GROUP_COLOR
	_analog_group_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_analog_group_bg)

	_cyborg_group_bg = ColorRect.new()
	_cyborg_group_bg.color = CYBORG_GROUP_COLOR
	_cyborg_group_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_cyborg_group_bg)

	var pcts := _compute_pcts()
	for row_def: Dictionary in STAT_ROWS:
		_rows.append(_build_row(row_def, pcts))

	_do_layout()
	_repaint()

func _build_row(row_def: Dictionary, pcts: Dictionary) -> Dictionary:
	var stat_id: StringName = row_def["stat"]
	var row_origin: StringName = row_def["origin"]
	var stat_color: Color = AttributeState.STAT_COLORS.get(stat_id, Color.WHITE)
	var pct: float = pcts.get(stat_id, 0.0)
	var tiers: Array[float] = _get_tiers_for_stat(stat_id, row_origin)

	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(container)

	var header := Label.new()
	header.text = row_def["class"]
	header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	container.add_child(header)

	var key: StringName = AttributeState.STAT_I18N.get(stat_id, &"")
	var display: String = tr(key) if key != &"" else str(stat_id)
	var stat_label := Label.new()
	stat_label.text = "%s  %d%%" % [display, int(pct * 100)]
	stat_label.theme_type_variation = &"SmallLabel"
	stat_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	container.add_child(stat_label)

	var bar_bg := ColorRect.new()
	bar_bg.color = BAR_BG_COLOR
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bar_bg)

	var bar_fill := ColorRect.new()
	bar_fill.color = stat_color
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bar_fill)

	var markers: Array[ColorRect] = []
	for _i in TIER_COUNT:
		var marker := ColorRect.new()
		marker.color = TIER_MARKER_COLOR
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(marker)
		markers.append(marker)

	var tier_labels: Array[Label] = []
	for i in TIER_COUNT:
		var lbl := Label.new()
		lbl.text = "T%d" % (i + 1)
		lbl.theme_type_variation = &"SmallLabel"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		container.add_child(lbl)
		tier_labels.append(lbl)

	var node_rects: Array[Array] = []
	for tier in TIER_COUNT:
		var tier_nodes: Array[ColorRect] = []
		for j in NODES_PER_TIER:
			var node_rect := ColorRect.new()
			node_rect.mouse_filter = Control.MOUSE_FILTER_STOP
			node_rect.gui_input.connect(_on_node_clicked.bind(stat_id, tier, j))
			container.add_child(node_rect)
			tier_nodes.append(node_rect)
		node_rects.append(tier_nodes)

	return {
		"container": container,
		"header": header,
		"stat_label": stat_label,
		"bar_bg": bar_bg,
		"bar_fill": bar_fill,
		"markers": markers,
		"tier_labels": tier_labels,
		"node_rects": node_rects,
		"stat_id": stat_id,
		"origin": row_origin,
		"stat_color": stat_color,
		"pct": pct,
		"tiers": tiers,
	}

# ── Layout ─────────────────────────────────────────────────────────────────

func _do_layout() -> void:
	var screen := get_viewport_rect().size

	var node_grid_h: float = float(NODE_ROWS) * NODE_SIZE.y + float(NODE_ROWS - 1) * NODE_GAP
	var row_h: float = BAR_HEIGHT + BAR_NODE_GAP + node_grid_h
	var rows_per_group := 3
	var group_count := 2
	var group_inner_h: float = float(rows_per_group) * row_h + float(rows_per_group - 1) * ROW_GAP
	var body_h: float = float(group_count) * group_inner_h + GROUP_GAP

	var panel_h: float = PANEL_MARGIN.y * 2.0 + TITLE_HEIGHT + TALENT_HEIGHT + NOTE_HEIGHT + HEADER_GAP + body_h
	var panel_w: float = minf(screen.x * 0.9, 1000.0)

	_panel.position = Vector2((screen.x - panel_w) * 0.5, (screen.y - panel_h) * 0.5)
	_panel.size = Vector2(panel_w, panel_h)
	_content.size = _panel.size

	var p := UIThemeState.palette
	var style := StyleBoxFlat.new()
	style.bg_color = p.panel_bg
	style.border_color = p.panel_border
	style.set_border_width_all(1)
	style.set_content_margin_all(0)
	_panel.add_theme_stylebox_override(&"panel", style)

	_title_label.position = Vector2(0, 8)
	_title_label.size = Vector2(panel_w, TITLE_HEIGHT)
	_talent_label.position = Vector2(0, 8 + TITLE_HEIGHT)
	_talent_label.size = Vector2(panel_w, TALENT_HEIGHT)
	_note_label.position = Vector2(0, 8 + TITLE_HEIGHT + TALENT_HEIGHT)
	_note_label.size = Vector2(panel_w, NOTE_HEIGHT)

	var bar_w: float = panel_w - (PANEL_MARGIN.x + LABEL_WIDTH + LABEL_GAP) - PANEL_MARGIN.x
	var body_y: float = PANEL_MARGIN.y + TITLE_HEIGHT + TALENT_HEIGHT + NOTE_HEIGHT + HEADER_GAP

	_analog_group_bg.position = Vector2(PANEL_MARGIN.x - GROUP_PADDING.x, body_y - GROUP_PADDING.y)
	_analog_group_bg.size = Vector2(panel_w - PANEL_MARGIN.x * 2.0 + GROUP_PADDING.x * 2.0, group_inner_h + GROUP_PADDING.y * 2.0)

	_cyborg_group_bg.position = Vector2(PANEL_MARGIN.x - GROUP_PADDING.x, body_y + group_inner_h + GROUP_GAP - GROUP_PADDING.y)
	_cyborg_group_bg.size = Vector2(panel_w - PANEL_MARGIN.x * 2.0 + GROUP_PADDING.x * 2.0, group_inner_h + GROUP_PADDING.y * 2.0)

	var section_w: float = bar_w / float(TIER_COUNT)

	for ri in STAT_ROWS.size():
		var row: Dictionary = _rows[ri]
		var group_offset: float = GROUP_GAP if ri >= rows_per_group else 0.0
		var ry: float = body_y + float(ri) * (row_h + ROW_GAP) + group_offset

		row["container"].position = Vector2(PANEL_MARGIN.x, ry)
		row["container"].size = Vector2(panel_w - PANEL_MARGIN.x * 2.0, row_h)

		var label_block_h: float = CLASS_NAME_HEIGHT + STAT_LINE_HEIGHT
		var label_y: float = (row_h - label_block_h) * 0.5
		row["header"].position = Vector2(0, label_y)
		row["header"].size = Vector2(LABEL_WIDTH, CLASS_NAME_HEIGHT)
		row["stat_label"].position = Vector2(0, label_y + CLASS_NAME_HEIGHT)
		row["stat_label"].size = Vector2(LABEL_WIDTH, STAT_LINE_HEIGHT)

		var local_bar_x: float = LABEL_WIDTH + LABEL_GAP
		row["bar_bg"].position = Vector2(local_bar_x, 0)
		row["bar_bg"].size = Vector2(bar_w, BAR_HEIGHT)
		row["bar_fill"].position = Vector2(local_bar_x, 0)
		row["bar_fill"].size = Vector2(bar_w * clampf(row["pct"], 0.0, 1.0), BAR_HEIGHT)

		for mi in TIER_COUNT:
			var mx: float = local_bar_x + section_w * float(mi + 1)
			row["markers"][mi].position = Vector2(mx - TIER_MARKER_WIDTH * 0.5, 0)
			row["markers"][mi].size = Vector2(TIER_MARKER_WIDTH, BAR_HEIGHT)
			row["markers"][mi].visible = mi < TIER_COUNT - 1

		var nodes_y: float = BAR_HEIGHT + BAR_NODE_GAP
		var node_grid_w: float = float(NODE_COLS) * NODE_SIZE.x + float(NODE_COLS - 1) * NODE_GAP
		var inner_grid_h: float = float(NODE_ROWS) * NODE_SIZE.y + float(NODE_ROWS - 1) * NODE_GAP
		for ti in TIER_COUNT:
			var sx: float = local_bar_x + section_w * float(ti)
			row["tier_labels"][ti].position = Vector2(sx, 0)
			row["tier_labels"][ti].size = Vector2(section_w, BAR_HEIGHT)

			var grid_x: float = sx + (section_w - node_grid_w) * 0.5
			var grid_y: float = nodes_y + (node_grid_h - inner_grid_h) * 0.5
			for j in NODES_PER_TIER:
				var nr: int = j / NODE_COLS
				var nc: int = j % NODE_COLS
				row["node_rects"][ti][j].position = Vector2(grid_x + float(nc) * (NODE_SIZE.x + NODE_GAP), grid_y + float(nr) * (NODE_SIZE.y + NODE_GAP))
				row["node_rects"][ti][j].size = NODE_SIZE

# ── Paint ──────────────────────────────────────────────────────────────────

func _repaint() -> void:
	if _rows.is_empty():
		return
	var p := UIThemeState.palette
	var spent := _total_spent()
	var remaining := PlayerState.talent_points_total - spent

	var class_key: StringName = PlayerState.spec_id if PlayerState.spec_id != &"" else PlayerState.class_id
	_title_label.text = "TALENTS — %s" % (class_key.capitalize() if class_key != &"" else "—")
	_title_label.add_theme_color_override(&"font_color", p.accent)

	_talent_label.text = "%d point%s remaining  (%d / %d spent)" % [
		remaining, "" if remaining == 1 else "s", spent, PlayerState.talent_points_total
	]
	_talent_label.add_theme_color_override(&"font_color", TALENT_POINT_COLOR)
	_note_label.add_theme_color_override(&"font_color", Color(p.text_dim, 0.5))

	for row: Dictionary in _rows:
		var stat_color: Color = row["stat_color"]
		var unlocked_tier: int = _calc_unlocked_tier(row["pct"], row["tiers"])

		row["header"].add_theme_color_override(&"font_color", stat_color)
		row["stat_label"].add_theme_color_override(&"font_color", Color(stat_color, 0.6))

		for ti in TIER_COUNT:
			var unlocked: bool = (ti + 1) <= unlocked_tier
			row["tier_labels"][ti].add_theme_color_override(&"font_color", stat_color if unlocked else TIER_LABEL_COLOR)

		var tiers_data: Array = PlayerState.talent_allocations.get(row["stat_id"], [])
		for tier in TIER_COUNT:
			var tier_unlocked: bool = (tier + 1) <= unlocked_tier
			for j in NODES_PER_TIER:
				var rect: ColorRect = row["node_rects"][tier][j]
				var is_allocated: bool = not tiers_data.is_empty() and tiers_data[tier][j]
				if tier_unlocked and is_allocated:
					rect.color = Color(stat_color.r, stat_color.g, stat_color.b, NODE_ALLOCATED_ALPHA)
				elif tier_unlocked:
					rect.color = Color(stat_color.r, stat_color.g, stat_color.b, NODE_AVAILABLE_ALPHA)
				else:
					rect.color = NODE_LOCKED_COLOR
