extends Control
class_name TalentsPanel

## Talents panel — 6 class stat rows. Progress bars are driven by equipped gear
## (AttributeState). Tier unlock thresholds and relationship logic live in
## AttributeState. Talent points are stored in PlayerState and persist.

const TIER_COUNT := AttributeState.TIER_COUNT                  # 3
const NODES_PER_TIER := AttributeState.TALENT_NODES_PER_TIER  # 8
const NODE_ROWS := 2
const NODE_COLS := 4

const PANEL_MARGIN := Vector2(20.0, 14.0)
const TITLE_HEIGHT := 18.0
const TALENT_HEIGHT := 12.0
const NOTE_HEIGHT := 0.0
const HEADER_GAP := 6.0
const ROW_GAP := 3.0
const COL_GAP := 12.0
const BAR_HEIGHT := 13.0
const BAR_NODE_GAP := 2.0
const SUMMARY_LABEL_HEIGHT := 9.0
const SUMMARY_LABEL_GAP := 5.0
const SUMMARY_BAR_HEIGHT := 10.0
const SUMMARY_BAR_GAP := 8.0
const SUMMARY_SEG_GAP := 2.0
const SUMMARY_SEG_MIN_WIDTH := 40.0
const NODE_GAP := 2.0
const TIER_GAP := 8.0
const TIER_MARKER_WIDTH := 2.0
const LABEL_WIDTH := 120.0
const LABEL_GAP := 8.0
const CLASS_NAME_HEIGHT := 15.0
const STAT_LINE_HEIGHT := 11.0

const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const BAR_BG_COLOR := Color(0.12, 0.12, 0.12, 0.9)
const NODE_AVAILABLE_ALPHA := 0.25
const NODE_ALLOCATED_ALPHA := 1.0
const NODE_GHOST_COLOR := Color(1.0, 1.0, 1.0, 0.04)
const TIER_MARKER_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const TALENT_POINT_COLOR := Color(0.95, 0.85, 0.4, 1.0)
const TIER_LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.25)
const ROW_LOCKED_ALPHA := 0.3

const ANALOG_GROUP_COLOR := Color(0.65, 0.45, 0.25, 0.06)
const CYBORG_GROUP_COLOR := Color(0.3, 0.85, 1.0, 0.06)
const GROUP_PADDING := Vector2(4.0, 3.0)
const ROW_HIGHLIGHT_W := 2.0

const STAT_ROWS: Array[Dictionary] = [
	{"stat": &"ort", "class": "Count",       "short": "ORT", "origin": &"analog"},
	{"stat": &"ing", "class": "Survivalist", "short": "ING", "origin": &"analog"},
	{"stat": &"amb", "class": "Enculted",    "short": "AMB", "origin": &"analog"},
	{"stat": &"dev", "class": "Forged",      "short": "DEV", "origin": &"cyborg"},
	{"stat": &"opt", "class": "Automaton",   "short": "OPT", "origin": &"cyborg"},
	{"stat": &"cla", "class": "Polymath",    "short": "CLA", "origin": &"cyborg"},
]

var _backdrop: ColorRect
var _panel: PanelContainer
var _content: Control
var _title_label: Label
var _talent_label: Label
var _analog_group_bg: ColorRect
var _cyborg_group_bg: ColorRect
var _summary_bar: Control
var _summary_labels: Array[Label] = []
var _summary_segments: Array[ColorRect] = []
var _summary_stat_order: Array[StringName] = []
var _summary_seg_bounds: Array[float] = []
var _summary_stat_pcts: Dictionary = {}
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
	PlayerState.leveled_up.connect(func(_lv: int, _hp: int) -> void: _repaint())
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
	get_tree().call_group(&"ui_modal", &"close_menu")
	visible = true

func close_menu() -> void:
	visible = false

# ── Click handling ─────────────────────────────────────────────────────────────

func _on_node_clicked(event: InputEvent, stat_id: StringName, tier: int, node_idx: int) -> void:
	if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	var unlocked := AttributeState.get_unlocked_tier(stat_id, PlayerState.class_id, PlayerState.spec_id)
	if tier + 1 > unlocked:
		return
	if PlayerState.is_talent_allocated(stat_id, tier, node_idx):
		PlayerState.set_talent_alloc(stat_id, tier, node_idx, false)
	elif PlayerState.get_talent_points_spent() < PlayerState.talent_points_total:
		PlayerState.set_talent_alloc(stat_id, tier, node_idx, true)

# ── Signals ────────────────────────────────────────────────────────────────────

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
	var pcts := AttributeState.get_all_stat_pcts()
	for row: Dictionary in _rows:
		var sid: StringName = row["stat_id"]
		row["pct"] = pcts.get(sid, 0.0)
		var key: StringName = AttributeState.STAT_I18N.get(sid, &"")
		(row["header"] as Label).text = tr(key) if key != &"" else str(sid)

func _rebuild() -> void:
	for row: Dictionary in _rows:
		(row["container"] as Control).queue_free()
	_rows.clear()
	var pcts := AttributeState.get_all_stat_pcts()
	for row_def: Dictionary in STAT_ROWS:
		_rows.append(_build_row(row_def, pcts))
	_do_layout()
	_repaint()

# ── Build ──────────────────────────────────────────────────────────────────────

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

	_analog_group_bg = ColorRect.new()
	_analog_group_bg.color = ANALOG_GROUP_COLOR
	_analog_group_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_analog_group_bg)

	_cyborg_group_bg = ColorRect.new()
	_cyborg_group_bg.color = CYBORG_GROUP_COLOR
	_cyborg_group_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_cyborg_group_bg)

	_summary_bar = Control.new()
	_summary_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_summary_bar.mouse_exited.connect(func() -> void:
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip"))
	_summary_bar.gui_input.connect(_on_summary_bar_input)
	_content.add_child(_summary_bar)
	for _i in STAT_ROWS.size():
		var lbl := Label.new()
		lbl.theme_type_variation = &"SmallLabel"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_summary_bar.add_child(lbl)
		_summary_labels.append(lbl)
		var seg := ColorRect.new()
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg.color = BAR_BG_COLOR
		_summary_bar.add_child(seg)
		_summary_segments.append(seg)

	var pcts := AttributeState.get_all_stat_pcts()
	for row_def: Dictionary in STAT_ROWS:
		_rows.append(_build_row(row_def, pcts))

	_do_layout()
	_repaint()

func _build_row(row_def: Dictionary, pcts: Dictionary) -> Dictionary:
	var stat_id: StringName = row_def["stat"]
	var stat_color: Color = AttributeState.STAT_COLORS.get(stat_id, Color.WHITE)
	var pct: float = pcts.get(stat_id, 0.0)

	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(container)

	var highlight_bar := ColorRect.new()
	highlight_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight_bar.visible = false
	container.add_child(highlight_bar)

	var key: StringName = AttributeState.STAT_I18N.get(stat_id, &"")
	var display: String = tr(key) if key != &"" else str(stat_id)
	var header := Label.new()
	header.text = display
	header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	container.add_child(header)

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
		lbl.text = AttributeState.TIER_ROMAN[i]
		lbl.theme_type_variation = &"SmallLabel"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.z_index = 1
		container.add_child(lbl)
		tier_labels.append(lbl)

	var node_rects: Array[Array] = []
	for tier in TIER_COUNT:
		var tier_nodes: Array[ColorRect] = []
		for j in NODES_PER_TIER:
			var node_rect := ColorRect.new()
			node_rect.mouse_filter = Control.MOUSE_FILTER_STOP
			node_rect.gui_input.connect(_on_node_clicked.bind(stat_id, tier, j))
			node_rect.mouse_entered.connect(_on_node_hovered.bind(stat_id, tier, j))
			node_rect.mouse_exited.connect(_on_node_unhovered)
			container.add_child(node_rect)
			tier_nodes.append(node_rect)
		node_rects.append(tier_nodes)

	return {
		"container":     container,
		"highlight_bar": highlight_bar,
		"header":        header,
		"bar_bg":        bar_bg,
		"bar_fill":      bar_fill,
		"markers":       markers,
		"tier_labels":   tier_labels,
		"node_rects":    node_rects,
		"stat_id":       stat_id,
		"stat_color":    stat_color,
		"pct":           pct,
	}

# ── Layout ─────────────────────────────────────────────────────────────────────

func _do_layout() -> void:
	var screen := get_viewport_rect().size
	var panel_w: float = minf(screen.x * 0.75, 820.0)
	var content_w: float = panel_w - PANEL_MARGIN.x * 2.0
	var col_w: float = (content_w - COL_GAP) * 0.5
	var col_bar_w: float = col_w - LABEL_WIDTH - LABEL_GAP

	# Derive node size from available bar width so nodes always fit.
	var total_gaps: float = float(TIER_COUNT - 1) * TIER_GAP + float(TIER_COUNT) * float(NODE_COLS - 1) * NODE_GAP
	var node_side: float = floorf((col_bar_w - total_gaps) / float(TIER_COUNT * NODE_COLS))
	var node_size := Vector2(node_side, node_side)

	var node_grid_h: float = float(NODE_ROWS) * node_size.y + float(NODE_ROWS - 1) * NODE_GAP
	var row_h: float = BAR_HEIGHT + BAR_NODE_GAP + node_grid_h
	var rows_per_col := 3
	var col_inner_h: float = float(rows_per_col) * row_h + float(rows_per_col - 1) * ROW_GAP

	var summary_area_h: float = SUMMARY_LABEL_HEIGHT + SUMMARY_LABEL_GAP + SUMMARY_BAR_HEIGHT
	var panel_h: float = PANEL_MARGIN.y * 2.0 + TITLE_HEIGHT + TALENT_HEIGHT + NOTE_HEIGHT + HEADER_GAP + summary_area_h + SUMMARY_BAR_GAP + col_inner_h

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
	var header_bottom: float = PANEL_MARGIN.y + TITLE_HEIGHT + TALENT_HEIGHT + NOTE_HEIGHT + HEADER_GAP

	_summary_bar.position = Vector2(PANEL_MARGIN.x, header_bottom)
	_summary_bar.size = Vector2(content_w, summary_area_h)

	var body_y: float = header_bottom + summary_area_h + SUMMARY_BAR_GAP
	var cyborg_col_x: float = PANEL_MARGIN.x + col_w + COL_GAP

	_analog_group_bg.position = Vector2(PANEL_MARGIN.x - GROUP_PADDING.x, body_y - GROUP_PADDING.y)
	_analog_group_bg.size = Vector2(col_w + GROUP_PADDING.x * 2.0, col_inner_h + GROUP_PADDING.y * 2.0)
	_cyborg_group_bg.position = Vector2(cyborg_col_x - GROUP_PADDING.x, body_y - GROUP_PADDING.y)
	_cyborg_group_bg.size = Vector2(col_w + GROUP_PADDING.x * 2.0, col_inner_h + GROUP_PADDING.y * 2.0)

	for ri in STAT_ROWS.size():
		var row: Dictionary = _rows[ri]
		var is_cyborg: bool = ri >= rows_per_col
		var col_x: float = cyborg_col_x if is_cyborg else PANEL_MARGIN.x
		var local_ri: int = ri - rows_per_col if is_cyborg else ri
		var ry: float = body_y + float(local_ri) * (row_h + ROW_GAP)
		_layout_row(row, Vector2(col_x, ry), col_w, col_bar_w, node_size, TIER_COUNT)

func _layout_row(row: Dictionary, row_pos: Vector2, row_w: float, bar_w: float, node_size: Vector2, tier_count: int) -> void:
	var node_grid_h: float = float(NODE_ROWS) * node_size.y + float(NODE_ROWS - 1) * NODE_GAP
	var row_h: float = BAR_HEIGHT + BAR_NODE_GAP + node_grid_h

	row["container"].position = row_pos
	row["container"].size = Vector2(row_w, row_h)

	if row.has("highlight_bar"):
		(row["highlight_bar"] as ColorRect).position = Vector2(-ROW_HIGHLIGHT_W - 2.0, 0.0)
		(row["highlight_bar"] as ColorRect).size = Vector2(ROW_HIGHLIGHT_W, row_h)

	var label_y: float = (row_h - CLASS_NAME_HEIGHT) * 0.5
	row["header"].position = Vector2(0, label_y)
	row["header"].size = Vector2(LABEL_WIDTH, CLASS_NAME_HEIGHT)

	var local_bar_x: float = LABEL_WIDTH + LABEL_GAP
	row["bar_bg"].position = Vector2(local_bar_x, 0)
	row["bar_bg"].size = Vector2(bar_w, BAR_HEIGHT)

	row["bar_fill"].position = Vector2(local_bar_x, 0)
	row["bar_fill"].size = Vector2(0.0, BAR_HEIGHT)

	var nodes_y: float = BAR_HEIGHT + BAR_NODE_GAP
	var tier_labels: Array = row["tier_labels"]
	var node_rects: Array = row["node_rects"]

	# Tier width = nodes + intra-gaps. Any leftover bar space is added to intra-gaps.
	var fixed_gaps: float = float(tier_count - 1) * TIER_GAP + float(tier_count) * float(NODE_COLS - 1) * NODE_GAP
	var fixed_nodes: float = float(tier_count * NODE_COLS) * node_size.x
	var extra_per_intra: float = maxf((bar_w - fixed_nodes - fixed_gaps) / float(tier_count * (NODE_COLS - 1)), 0.0)
	var intra_gap: float = NODE_GAP + extra_per_intra
	var tier_w: float = float(NODE_COLS) * node_size.x + float(NODE_COLS - 1) * intra_gap

	for ti in tier_count:
		var tier_x: float = local_bar_x + float(ti) * (tier_w + TIER_GAP)
		tier_labels[ti].position = Vector2(tier_x, 0)
		tier_labels[ti].size = Vector2(tier_w, BAR_HEIGHT)

		for j in NODES_PER_TIER:
			var nr: int = floori(float(j) / NODE_COLS)
			var nc: int = j - nr * NODE_COLS
			(node_rects[ti][j] as ColorRect).position = Vector2(
				tier_x + float(nc) * (node_size.x + intra_gap),
				nodes_y + float(nr) * (node_size.y + NODE_GAP)
			)
			(node_rects[ti][j] as ColorRect).size = node_size

	# Position tier markers centered in the gap between tier groups.
	var markers: Array = row["markers"]
	for mi in markers.size():
		if mi < tier_count - 1:
			var marker_x: float = local_bar_x + float(mi + 1) * (tier_w + TIER_GAP) - TIER_GAP * 0.5 - TIER_MARKER_WIDTH * 0.5
			(markers[mi] as ColorRect).position = Vector2(marker_x, nodes_y)
			(markers[mi] as ColorRect).size = Vector2(TIER_MARKER_WIDTH, node_grid_h)
		(markers[mi] as ColorRect).visible = false

# ── Paint ──────────────────────────────────────────────────────────────────────

func _repaint() -> void:
	if _rows.is_empty():
		return
	var p := UIThemeState.palette
	var spent := PlayerState.get_talent_points_spent()
	var remaining := PlayerState.talent_points_total - spent

	var class_key: StringName = PlayerState.spec_id if PlayerState.spec_id != &"" else PlayerState.class_id
	var class_display: String
	if class_key == &"count":
		class_display = "Countess" if PlayerState.gender == &"female" else "Count"
	elif class_key != &"":
		class_display = String(class_key).capitalize()
	else:
		class_display = "—"
	_title_label.text = "TALENTS — %s" % class_display
	_title_label.add_theme_color_override(&"font_color", p.accent)

	_talent_label.text = "%d point%s remaining  (%d / %d spent)" % [
		remaining, "" if remaining == 1 else "s", spent, PlayerState.talent_points_total
	]
	_talent_label.add_theme_color_override(&"font_color", TALENT_POINT_COLOR)
	_repaint_summary()

	for row: Dictionary in _rows:
		_paint_row(row, _stat_rel_color(row["stat_id"]),
			AttributeState.get_unlocked_tier(row["stat_id"], PlayerState.class_id, PlayerState.spec_id))

func _stat_rel_color(stat_id: StringName) -> Color:
	var key := AttributeState.get_stat_rel_color_key(stat_id, PlayerState.class_id, PlayerState.spec_id)
	return AttributeState.RELATIONSHIP_COLORS[key]

func _rel_priority(stat_id: StringName) -> int:
	return AttributeState.get_stat_rel_priority(stat_id, PlayerState.class_id, PlayerState.spec_id)

func _repaint_summary() -> void:
	var pcts := AttributeState.get_all_stat_pcts()
	_summary_stat_pcts = pcts
	var total := 0.0
	for row_def: Dictionary in STAT_ROWS:
		total += pcts.get(row_def["stat"], 0.0)

	# Sort: primary(green) → team(dim green) → opp-team(yellow) → nemesis(red)
	var sorted: Array[StringName] = []
	for row_def: Dictionary in STAT_ROWS:
		sorted.append(row_def["stat"] as StringName)
	sorted.sort_custom(func(a: StringName, b: StringName) -> bool:
		return _rel_priority(a) < _rel_priority(b))
	_summary_stat_order = sorted

	var bar_w: float = _summary_bar.size.x
	var visible_count := 0
	for s: StringName in sorted:
		if pcts.get(s, 0.0) > 0.0:
			visible_count += 1
	# Reserve a minimum slice per visible segment so labels stay readable; the
	# remainder is split proportionally. Empty state splits evenly across all
	# segments as gray placeholders.
	var is_empty := total <= 0.001
	var visual_count: int = sorted.size() if is_empty else visible_count
	var gap_total := float(maxi(visual_count - 1, 0)) * SUMMARY_SEG_GAP
	var avail_w := bar_w - gap_total
	var proportional_w := maxf(avail_w - float(visual_count) * SUMMARY_SEG_MIN_WIDTH, 0.0)
	var bar_y: float = SUMMARY_LABEL_HEIGHT + SUMMARY_LABEL_GAP
	_summary_seg_bounds.clear()
	var x := 0.0
	for i in sorted.size():
		var stat_id: StringName = sorted[i]
		var lbl: Label = _summary_labels[i]
		var seg: ColorRect = _summary_segments[i]
		var pct: float = pcts.get(stat_id, 0.0)
		var seg_w: float
		if is_empty:
			seg_w = avail_w / float(sorted.size())
		elif pct > 0.0:
			seg_w = SUMMARY_SEG_MIN_WIDTH + (pct / total) * proportional_w
		else:
			seg_w = 0.0
		_summary_seg_bounds.append(x)
		var stat_color: Color = AttributeState.STAT_COLORS.get(stat_id, Color.WHITE)
		var short_name: String = AttributeState.STAT_SHORT.get(stat_id, (stat_id as String).to_upper())
		lbl.visible = pct > 0.0
		lbl.text = "%s %d%%" % [short_name, int(pct * 100)]
		lbl.position = Vector2(x, 0.0)
		lbl.size = Vector2(seg_w, SUMMARY_LABEL_HEIGHT)
		lbl.add_theme_color_override(&"font_color", Color(stat_color.r, stat_color.g, stat_color.b, 0.8))
		lbl.add_theme_font_size_override(&"font_size", 8)
		seg.position = Vector2(x, bar_y)
		seg.size = Vector2(seg_w, SUMMARY_BAR_HEIGHT)
		var rel_color := _stat_rel_color(stat_id)
		seg.color = Color(rel_color.r, rel_color.g, rel_color.b, 0.7 if not is_empty else 0.15)
		if seg_w > 0.0:
			x += seg_w + SUMMARY_SEG_GAP
	_summary_seg_bounds.append(x)

func _on_summary_bar_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if _summary_stat_order.is_empty() or _summary_seg_bounds.size() < 2:
		return
	var mx: float = (event as InputEventMouseMotion).position.x
	var hover_idx := -1
	for i in _summary_stat_order.size():
		if mx >= _summary_seg_bounds[i]:
			hover_idx = i
	if hover_idx < 0:
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
		return
	var stat_id: StringName = _summary_stat_order[hover_idx]
	var key: StringName = AttributeState.STAT_I18N.get(stat_id, &"")
	var stat_name: String = tr(key) if key != &"" else (stat_id as String).capitalize()
	var pct: float = _summary_stat_pcts.get(stat_id, 0.0)
	var unlocked: int = AttributeState.get_unlocked_tier(stat_id, PlayerState.class_id, PlayerState.spec_id)
	var thresholds: Array[float] = AttributeState.get_tier_thresholds(stat_id, PlayerState.class_id, PlayerState.spec_id)
	var tier_text: String = "%s unlocked" % AttributeState.TIER_ROMAN[unlocked - 1] if unlocked > 0 else "no tier unlocked"
	var next_text: String = "%s at %d%%" % [AttributeState.TIER_ROMAN[unlocked], int(thresholds[unlocked] * 100)] if unlocked < AttributeState.TIER_COUNT else "maxed"
	get_tree().call_group(&"interactable_tooltip", &"show_text",
		"%s  %d%%\n%s · next: %s" % [stat_name, int(pct * 100), tier_text, next_text])

func _on_node_hovered(stat_id: StringName, tier: int, node_idx: int) -> void:
	var key: StringName = AttributeState.STAT_I18N.get(stat_id, &"")
	var stat_name: String = tr(key) if key != &"" else (stat_id as String).capitalize()
	var unlocked := AttributeState.get_unlocked_tier(stat_id, PlayerState.class_id, PlayerState.spec_id)
	var is_locked := tier >= unlocked
	var title := "%s %s · Node %d" % [stat_name, AttributeState.TIER_ROMAN[tier], node_idx + 1]
	var body: String
	if is_locked:
		var thresholds := AttributeState.get_tier_thresholds(stat_id, PlayerState.class_id, PlayerState.spec_id)
		var needed_pct := int(thresholds[tier] * 100)
		title += "  ·  Locked (%d%%)" % needed_pct
		body = "Reach %d%% %s allocation to unlock this tier." % [needed_pct, stat_name]
	else:
		body = "Node effect TBD."
	get_tree().call_group(&"interactable_tooltip", &"show_talent_node", title, body)

func _on_node_unhovered() -> void:
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func _paint_row(row: Dictionary, rel_color: Color, unlocked_tier: int) -> void:
	var fade := ROW_LOCKED_ALPHA if unlocked_tier == 0 else 1.0
	(row["container"] as Control).modulate = Color(1.0, 1.0, 1.0, fade)
	var stat_color: Color = row.get("stat_color", rel_color)
	row["header"].add_theme_color_override(&"font_color", stat_color)
	var bar_bg := row["bar_bg"] as ColorRect
	var bar_fill := row["bar_fill"] as ColorRect
	bar_fill.color = stat_color
	bar_fill.size.x = bar_bg.size.x * float(unlocked_tier) / float(TIER_COUNT)
	if row.has("highlight_bar"):
		var is_primary := rel_color == AttributeState.RELATIONSHIP_COLORS[&"primary"]
		var hbar := row["highlight_bar"] as ColorRect
		hbar.visible = is_primary
		hbar.color = stat_color

	# tier_state = ti - unlocked_tier:
	#   < 0  → active (tier is unlocked)
	#   >= 0 → dim ghost preview (always visible so players can see what's ahead)
	var tier_labels: Array = row["tier_labels"]
	for ti in tier_labels.size():
		var tier_state: int = ti - unlocked_tier
		var lbl := tier_labels[ti] as Label
		if tier_state < 0:
			lbl.visible = true
			lbl.add_theme_color_override(&"font_color", Color.WHITE)
			lbl.add_theme_constant_override(&"outline_size", 4)
			lbl.add_theme_color_override(&"font_outline_color", Color.BLACK)
		else:
			lbl.visible = true
			lbl.add_theme_color_override(&"font_color", TIER_LABEL_COLOR)
			lbl.add_theme_constant_override(&"outline_size", 0)

	# Markers sit between sections. Show only within the visible range
	# (unlocked + one ghost tier). Hide orphaned markers beyond that.
	var markers: Array = row["markers"]
	for mi in markers.size():
		(markers[mi] as ColorRect).visible = (mi + 1) <= unlocked_tier and mi < markers.size() - 1

	var node_rects: Array = row["node_rects"]
	for tier in node_rects.size():
		var tier_state: int = tier - unlocked_tier
		for j in NODES_PER_TIER:
			var rect: ColorRect = node_rects[tier][j]
			if tier_state < 0:
				var is_allocated := PlayerState.is_talent_allocated(row["stat_id"], tier, j)
				rect.visible = true
				rect.mouse_filter = Control.MOUSE_FILTER_STOP
				rect.color = Color(stat_color.r, stat_color.g, stat_color.b,
					NODE_ALLOCATED_ALPHA if is_allocated else NODE_AVAILABLE_ALPHA)
			else:
				rect.visible = true
				rect.mouse_filter = Control.MOUSE_FILTER_STOP
				rect.color = NODE_GHOST_COLOR
