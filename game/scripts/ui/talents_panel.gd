extends Control
class_name TalentsPanel

## Talents panel — 6 class rows. Talent points are stored in PlayerState and
## persist. Tier gating: own spec first, same-origin after spec investment,
## opposing origin fully locked.

const TIER_COUNT := 5
const NODES_PER_TIER := 8
const NODE_ROWS := 4
const NODE_COLS := 2

const PANEL_MARGIN := Vector2(20.0, 14.0)
const TITLE_HEIGHT := 18.0
const TALENT_HEIGHT := 12.0
const HEADER_GAP := 6.0
const ROW_GAP := 3.0
const COL_GAP := 12.0
const BAR_HEIGHT := 13.0
const BAR_NODE_GAP := 2.0
const NODE_GAP := 2.0
const TIER_GAP := 8.0
const TIER_MARKER_WIDTH := 2.0
const LABEL_WIDTH := 120.0
const LABEL_GAP := 8.0
const CLASS_NAME_HEIGHT := 15.0
const STAT_LINE_HEIGHT := 11.0
const DESC_FONT_SIZE := 7
const DESC_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const DESC_GAP := 2.0

const PERK_DIR := "res://resources/perks/"

const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const BAR_BG_COLOR := Color(0.12, 0.12, 0.12, 0.9)
const NODE_AVAILABLE_ALPHA := 0.25
const NODE_ALLOCATED_ALPHA := 1.0
const NODE_GHOST_COLOR := Color(1.0, 1.0, 1.0, 0.04)
# "Unavailable" = structurally unreachable for the current class (sentinel
# threshold > 1.0). Tier nodes + label fade like the regular preview but
# get a lock icon overlay on top. The lock makes the restriction explicit
# without colour-coding the rest of the row red (which was hard to read at
# a glance and overloaded the alloc-bar's red = "opposing" signal).
const TIER_LOCK_GLYPH := "🔒"
const TIER_LOCK_COLOR := Color(1.0, 1.0, 1.0, 0.55)
const TIER_MARKER_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const TALENT_POINT_COLOR := Color(0.95, 0.85, 0.4, 1.0)
const TIER_LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.25)
const ROW_LOCKED_ALPHA := 0.3

const ANALOG_GROUP_COLOR := Color(0.65, 0.45, 0.25, 0.06)
const CYBORG_GROUP_COLOR := Color(0.3, 0.85, 1.0, 0.06)
const GROUP_PADDING := Vector2(4.0, 3.0)
const ROW_HIGHLIGHT_W := 2.0

# Each row maps a legacy tree ID (perk/talent .tres files still use the old
# 3-letter abbreviations) to its class display info. The "stat" key is the
# runtime key into PlayerState.talent_allocations and TalentState trees.
const STAT_ROWS: Array[Dictionary] = [
	{"stat": &"ort", "class": "Count",       "origin": &"analog"},
	{"stat": &"ing", "class": "Survivalist", "origin": &"analog"},
	{"stat": &"amb", "class": "Enculted",    "origin": &"analog"},
	{"stat": &"dev", "class": "Forged",      "origin": &"cyborg"},
	{"stat": &"opt", "class": "Automaton",   "origin": &"cyborg"},
	{"stat": &"cla", "class": "Polymath",    "origin": &"cyborg"},
]

var _backdrop: ColorRect
var _panel: PanelContainer
var _content: Control
var _title_label: Label
var _talent_label: Label
var _analog_group_bg: ColorRect
var _cyborg_group_bg: ColorRect
var _rows: Array[Dictionary] = []
var _perk_ladders: Dictionary = {}  # stat_id → PerkLadder

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(&"ui_modal")
	theme = UIThemeState.theme
	UIThemeState.changed.connect(_on_theme_changed)
	PlayerState.class_changed.connect(_on_player_class_changed)
	PlayerState.spec_changed.connect(_on_player_class_changed)
	PlayerState.talents_changed.connect(_repaint)
	PlayerState.leveled_up.connect(_on_leveled_up)
	_load_perk_ladders()
	_build_layout()

func _exit_tree() -> void:
	UIThemeState.changed.disconnect(_on_theme_changed)
	PlayerState.class_changed.disconnect(_on_player_class_changed)
	PlayerState.spec_changed.disconnect(_on_player_class_changed)
	PlayerState.talents_changed.disconnect(_repaint)
	PlayerState.leveled_up.disconnect(_on_leveled_up)


func _on_theme_changed() -> void:
	theme = UIThemeState.theme
	_repaint()


func _on_leveled_up(_lv: int, _hp: int) -> void:
	_repaint()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var inside := _panel != null and _panel.get_global_rect().has_point(mb.global_position)
		if not inside:
			close_menu()
			accept_event()

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

func _load_perk_ladders() -> void:
	for row_def: Dictionary in STAT_ROWS:
		var stat_id: StringName = row_def["stat"]
		var path := PERK_DIR + str(stat_id) + ".tres"
		if ResourceLoader.exists(path):
			var ladder := load(path) as PerkLadder
			if ladder != null:
				_perk_ladders[stat_id] = ladder

# ── Click handling ─────────────────────────────────────────────────────────────

func _on_node_clicked(event: InputEvent, stat_id: StringName, tier: int, node_idx: int) -> void:
	if not (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	# Tier unlock gating — per-tree rules based on class, spec, and origin.
	var unlocked := PlayerState.get_unlocked_tier(stat_id)
	if tier >= unlocked:
		_show_lock_reason(stat_id, tier)
		return
	var infinite_points := DebugState.config != null and DebugState.config.unlock_all_talents
	if PlayerState.is_talent_allocated(stat_id, tier, node_idx):
		PlayerState.set_talent_alloc(stat_id, tier, node_idx, false)
	elif infinite_points or PlayerState.get_talent_points_spent() < PlayerState.talent_points_total:
		PlayerState.set_talent_alloc(stat_id, tier, node_idx, true)

# ── Signals ────────────────────────────────────────────────────────────────────

func _on_player_class_changed(_id: StringName) -> void:
	if _rows.is_empty():
		return
	_rebuild()


func _rebuild() -> void:
	for row: Dictionary in _rows:
		(row["container"] as Control).queue_free()
	_rows.clear()
	for row_def: Dictionary in STAT_ROWS:
		_rows.append(_build_row(row_def))
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

	for row_def: Dictionary in STAT_ROWS:
		_rows.append(_build_row(row_def))

	_do_layout()
	_repaint()

func _build_row(row_def: Dictionary) -> Dictionary:
	var stat_id: StringName = row_def["stat"]
	var stat_color: Color = AttributeState.color_for_id(stat_id)

	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(container)

	var highlight_bar := ColorRect.new()
	highlight_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	highlight_bar.visible = false
	container.add_child(highlight_bar)

	var display: String = row_def.get("class", str(stat_id))
	var header := Label.new()
	header.text = display
	header.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	container.add_child(header)

	var desc := Label.new()
	desc.theme_type_variation = &"SmallLabel"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	desc.add_theme_font_size_override(&"font_size", DESC_FONT_SIZE)
	desc.add_theme_color_override(&"font_color", DESC_COLOR)
	desc.mouse_filter = Control.MOUSE_FILTER_STOP
	desc.mouse_entered.connect(_on_perk_desc_hovered.bind(stat_id))
	desc.mouse_exited.connect(_on_node_unhovered)
	container.add_child(desc)

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

	# Lock-icon overlay per tier section. Hidden by default; _paint_row
	# flips visibility for tiers whose threshold is the unreachable
	# sentinel. mouse_filter = IGNORE so the underlying node rects still
	# receive hover events (which deliver the class-restriction tooltip).
	var tier_locks: Array[Label] = []
	for _i in TIER_COUNT:
		var lock_lbl := Label.new()
		lock_lbl.text = TIER_LOCK_GLYPH
		lock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lock_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock_lbl.add_theme_color_override(&"font_color", TIER_LOCK_COLOR)
		lock_lbl.visible = false
		container.add_child(lock_lbl)
		tier_locks.append(lock_lbl)

	return {
		"container":         container,
		"highlight_bar":     highlight_bar,
		"header":            header,
		"desc_label":        desc,
		"bar_bg":            bar_bg,
		"bar_fill":          bar_fill,
		"markers":           markers,
		"tier_labels":       tier_labels,
		"node_rects":        node_rects,
		"tier_locks":        tier_locks,
		"stat_id":           stat_id,
		"stat_color":        stat_color,
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

	var panel_h: float = PANEL_MARGIN.y * 2.0 + TITLE_HEIGHT + TALENT_HEIGHT + HEADER_GAP + col_inner_h

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
	var body_y: float = PANEL_MARGIN.y + TITLE_HEIGHT + TALENT_HEIGHT + HEADER_GAP
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

	var label_y: float = BAR_HEIGHT + BAR_NODE_GAP
	row["header"].position = Vector2(0, label_y)
	row["header"].size = Vector2(LABEL_WIDTH, CLASS_NAME_HEIGHT)

	var desc_y: float = label_y + CLASS_NAME_HEIGHT + DESC_GAP
	row["desc_label"].position = Vector2(0, desc_y)
	row["desc_label"].size = Vector2(LABEL_WIDTH, node_grid_h - CLASS_NAME_HEIGHT - DESC_GAP)
	row["container"].clip_contents = true

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

	var tier_locks: Array = row.get("tier_locks", [])
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

		# Lock overlay sits centered over the tier's node grid. _paint_row
		# decides whether to show it.
		if ti < tier_locks.size():
			(tier_locks[ti] as Label).position = Vector2(tier_x, nodes_y)
			(tier_locks[ti] as Label).size = Vector2(tier_w, node_grid_h)

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
	for row: Dictionary in _rows:
		var unlocked := PlayerState.get_unlocked_tier(row["stat_id"])
		_paint_row(row, unlocked)

func _on_node_hovered(stat_id: StringName, tier: int, node_idx: int) -> void:
	# Resolve the user-visible class name (Count, Survivalist, etc.) from
	# the legacy 3-letter stat id. The 3-letter ids (ort/ing/amb/dev/opt/cla)
	# are an internal artifact of the prior moral-stat system; never surface
	# them in tooltip text — that was the "old attributes next to the name"
	# bug players were seeing.
	var class_id: StringName = AttributeState.STAT_TO_CLASS.get(stat_id, stat_id)
	var class_name_str: String = (class_id as String).capitalize()
	var node_def: TalentNode = TalentState.get_node_def(stat_id, tier, node_idx)
	var heading: String
	if node_def != null and node_def.label != "":
		heading = "%s · %s %s" % [node_def.label, class_name_str, AttributeState.TIER_ROMAN[tier]]
	else:
		heading = "%s %s · Node %d" % [class_name_str, AttributeState.TIER_ROMAN[tier], node_idx + 1]
	var title := heading
	var body: String
	if node_def != null and node_def.description != "":
		body = node_def.description
	else:
		body = "Node effect TBD."
	get_tree().call_group(&"interactable_tooltip", &"show_talent_node", title, body)

func _on_node_unhovered() -> void:
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")


func _unavailable_reason(_stat_id: StringName, tier: int, _stat_name: String) -> String:
	var tier_label := AttributeState.TIER_ROMAN[tier]
	return "Tier %s is currently unavailable." % tier_label

func _show_lock_reason(stat_id: StringName, tier: int) -> void:
	var tree_class: StringName = AttributeState.STAT_TO_CLASS.get(stat_id, &"")
	var tree_origin: StringName = AttributeState.get_spec_origin(tree_class) if tree_class != &"" else &""
	var player_origin: StringName = PlayerState.class_id
	var tier_label := AttributeState.TIER_ROMAN[tier]
	var class_name_str: String = (tree_class as String).capitalize()
	var reason: String
	if tree_origin != player_origin:
		reason = "%s talents are locked — opposing origin." % class_name_str
	elif PlayerState.spec_id != &"" and not PlayerState._has_own_spec_investment():
		var own_class: StringName = AttributeState.STAT_TO_CLASS.get(
			AttributeState.CLASS_TO_STAT.get(PlayerState.spec_id, &""), &"")
		var own_name: String = (own_class as String).capitalize()
		reason = "Invest in %s Tier II+ to unlock %s talents." % [own_name, class_name_str]
	else:
		var needed: int = PlayerState.TIER_POINT_THRESHOLDS[tier] if tier < PlayerState.TIER_POINT_THRESHOLDS.size() else 0
		var stat_id_local: StringName = AttributeState.CLASS_TO_STAT.get(tree_class, &"")
		var spent: int = PlayerState._points_in_track(stat_id_local)
		reason = "Tier %s requires %d points in this tree (%d spent)." % [tier_label, needed, spent]
	get_tree().call_group(&"interactable_tooltip", &"show_talent_node", "Locked", reason)

func _perk_desc_text(stat_id: StringName) -> String:
	var ladder: PerkLadder = _perk_ladders.get(stat_id)
	if ladder == null or ladder.perks.is_empty():
		return ""
	var active_perk := _get_active_perk(stat_id, ladder)
	if active_perk != null:
		return active_perk.label
	# Not yet unlocked — show the T1 perk name dimmed.
	var perk: Perk = ladder.perks[0]
	return perk.label.split(" ")[0] if perk != null else ""


func _get_active_perk(stat_id: StringName, ladder: PerkLadder) -> Perk:
	var alloc: Array = PlayerState.talent_allocations.get(stat_id, [])
	var max_alloc_tier := -1
	for tier_idx in alloc.size():
		var row: Array = alloc[tier_idx]
		for node_alloc in row:
			if node_alloc:
				max_alloc_tier = maxi(max_alloc_tier, tier_idx)
				break
	var perk_idx := mini(max_alloc_tier, ladder.perks.size() - 1)
	if perk_idx < 0:
		return null
	return ladder.perks[perk_idx]


func _on_perk_desc_hovered(stat_id: StringName) -> void:
	var ladder: PerkLadder = _perk_ladders.get(stat_id)
	if ladder == null or ladder.perks.is_empty():
		return
	var perk := _get_active_perk(stat_id, ladder)
	if perk == null:
		perk = ladder.perks[0]
		if perk == null:
			return
		get_tree().call_group(&"interactable_tooltip", &"show_talent_node",
			perk.label, perk.description)
		return
	var title: String = perk.label
	var body: String = perk.description
	var player := get_tree().get_first_node_in_group(&"player") as PrototypePlayer
	for line in EffectFormatter.buff_lines_for_stat(stat_id, player):
		body += "\n• " + line
	get_tree().call_group(&"interactable_tooltip", &"show_talent_node", title, body)


func _paint_row(row: Dictionary, unlocked_tier: int) -> void:
	# Determine if this row belongs to the opposing origin — fully locked
	# rows get heavier dimming than same-origin locked rows.
	var stat_id: StringName = row["stat_id"]
	var tree_class: StringName = AttributeState.STAT_TO_CLASS.get(stat_id, &"")
	var tree_origin: StringName = AttributeState.get_spec_origin(tree_class) if tree_class != &"" else &""
	var is_opposing := tree_origin != PlayerState.class_id and PlayerState.class_id != &""
	var fade := ROW_LOCKED_ALPHA if is_opposing else (ROW_LOCKED_ALPHA if unlocked_tier == 0 else 1.0)
	(row["container"] as Control).modulate = Color(1.0, 1.0, 1.0, fade)
	var stat_color: Color = row.get("stat_color", Color.WHITE)
	row["header"].add_theme_color_override(&"font_color", stat_color)
	if row.has("highlight_bar"):
		(row["highlight_bar"] as ColorRect).visible = false

	# Determine which tiers have at least one allocation — only those get
	# color in the bar, highlighted tier labels, and visible node colors.
	# Unlocked-but-empty tiers look the same as locked tiers (ghost nodes)
	# except they have no lock icon and remain clickable.
	var alloc: Array = PlayerState.talent_allocations.get(stat_id, [])
	var tier_has_alloc: Array[bool] = []
	tier_has_alloc.resize(TIER_COUNT)
	var max_alloc_tier := -1
	for ti in TIER_COUNT:
		var has := false
		if ti < alloc.size():
			var row_arr: Array = alloc[ti]
			for node_alloc in row_arr:
				if node_alloc:
					has = true
					break
		tier_has_alloc[ti] = has
		if has:
			max_alloc_tier = ti

	# Bar fill extends only to cover tiers with allocations.
	var bar_bg := row["bar_bg"] as ColorRect
	var bar_fill := row["bar_fill"] as ColorRect
	bar_fill.color = stat_color
	bar_fill.size.x = bar_bg.size.x * float(max_alloc_tier + 1) / float(TIER_COUNT) if max_alloc_tier >= 0 else 0.0

	# Tier labels: white+outline for allocated tiers, faded for all others.
	var tier_labels: Array = row["tier_labels"]
	for ti in tier_labels.size():
		var lbl := tier_labels[ti] as Label
		lbl.visible = true
		if tier_has_alloc[ti]:
			lbl.add_theme_color_override(&"font_color", Color.WHITE)
			lbl.add_theme_constant_override(&"outline_size", 4)
			lbl.add_theme_color_override(&"font_outline_color", Color.BLACK)
		else:
			lbl.add_theme_color_override(&"font_color", TIER_LABEL_COLOR)
			lbl.add_theme_constant_override(&"outline_size", 0)

	# Markers between tier sections — visible when both adjacent tiers have allocations.
	var markers: Array = row["markers"]
	for mi in markers.size():
		var show := mi < TIER_COUNT - 1 and tier_has_alloc[mi] and tier_has_alloc[mi + 1]
		(markers[mi] as ColorRect).visible = show

	# Node rects: allocated tiers get class color, everything else gets ghost.
	# Lock icons only on actually locked tiers (tier >= unlocked_tier).
	var node_rects: Array = row["node_rects"]
	var tier_locks: Array = row.get("tier_locks", [])
	for tier in node_rects.size():
		var is_locked := tier >= unlocked_tier
		# Lock icon only on truly locked tiers (not unlocked-but-empty)
		if tier < tier_locks.size():
			(tier_locks[tier] as Label).visible = is_locked
			if is_locked:
				var lock_alpha := 0.3 if is_opposing else 0.55
				(tier_locks[tier] as Label).add_theme_color_override(
					&"font_color", Color(1.0, 1.0, 1.0, lock_alpha))
		for j in NODES_PER_TIER:
			var rect: ColorRect = node_rects[tier][j]
			rect.visible = true
			# Unlocked tiers remain clickable even if visually ghosted.
			rect.mouse_filter = Control.MOUSE_FILTER_STOP if not is_locked else Control.MOUSE_FILTER_IGNORE
			if tier_has_alloc[tier]:
				var is_allocated := PlayerState.is_talent_allocated(stat_id, tier, j)
				rect.color = Color(stat_color.r, stat_color.g, stat_color.b,
					NODE_ALLOCATED_ALPHA if is_allocated else NODE_AVAILABLE_ALPHA)
			else:
				rect.color = NODE_GHOST_COLOR

	# Perk description below the class name.
	if row.has("desc_label"):
		(row["desc_label"] as Label).text = _perk_desc_text(stat_id)
