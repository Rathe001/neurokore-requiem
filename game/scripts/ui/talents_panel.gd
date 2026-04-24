extends Control
class_name TalentsPanel

## Talents panel — 6 class rows (horizontal layout), each with a full-width
## progress bar and horizontal skill tree. Bar tier markers align with tree
## section edges. 5 tiers × 4 nodes = 20 nodes per class, 120 total.
## Talent points (1 per 5 levels) spent on nodes in unlocked tiers.
## Tier thresholds vary per row based on class relationship (own/team/opposing).
## Layout only — placeholder values, no real stat hookup.

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
const NODE_AVAILABLE_ALPHA := 0.12  # unlocked tier, no point spent
const NODE_ALLOCATED_ALPHA := 0.45  # talent point spent on this node
const TIER_MARKER_COLOR := Color(1.0, 1.0, 1.0, 0.45)
const TALENT_POINT_COLOR := Color(0.95, 0.85, 0.4, 1.0)
const TIER_LABEL_COLOR := Color(1.0, 1.0, 1.0, 0.25)

## Subtle origin group background tints (derived from Soul/Interface colors).
const ANALOG_GROUP_COLOR := Color(0.65, 0.45, 0.25, 0.06)
const CYBORG_GROUP_COLOR := Color(0.3, 0.85, 1.0, 0.06)
const GROUP_PADDING := Vector2(6.0, 4.0)
const GROUP_GAP := 14.0  # gap between the two origin groups

## Three-way tier thresholds based on class relationship.
const TIERS_OWN: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]  # always unlocked
const TIERS_TEAM: Array[float] = [0.10, 0.20, 0.35, 0.50, 0.70]
const TIERS_OPPOSING: Array[float] = [0.20, 0.30, 0.45, 0.60, 0.80]

## Origin → team stat IDs.
const ANALOG_STATS: Array[StringName] = [&"ort", &"ing", &"amb"]
const CYBORG_STATS: Array[StringName] = [&"dev", &"opt", &"cla"]

## The 6 rollable stats grouped by origin. Analog first, then Cyborg.
const STAT_ROWS: Array[Dictionary] = [
	{"stat": &"ort", "class": "Gentleman",   "short": "ORT", "origin": &"analog"},
	{"stat": &"ing", "class": "Survivalist", "short": "ING", "origin": &"analog"},
	{"stat": &"amb", "class": "Enculted",    "short": "AMB", "origin": &"analog"},
	{"stat": &"dev", "class": "Forged",      "short": "DEV", "origin": &"cyborg"},
	{"stat": &"opt", "class": "Automaton",   "short": "OPT", "origin": &"cyborg"},
	{"stat": &"cla", "class": "Polymath",    "short": "CLA", "origin": &"cyborg"},
]

const PLACEHOLDER_TALENT_POINTS := 20

## Realistic level 100 builds per class. Each entry:
##   "stat"   = class's primary stat (own tree)
##   "origin" = "analog" or "cyborg"
##   "pcts"   = stat distribution (sums to ~1.0)
##   "alloc"  = talent points per tier [T1,T2,T3,T4,T5] per stat (sums to 20)

const CLASS_BUILDS: Dictionary = {
	## --- Analog classes ---
	&"gentleman": {
		"stat": &"ort", "origin": &"analog",
		"pcts": {&"ort": 0.45, &"ing": 0.22, &"amb": 0.18, &"dev": 0.06, &"opt": 0.05, &"cla": 0.04},
		"alloc": {&"ort": [4,4,3,1,0], &"ing": [4,1,0,0,0], &"amb": [3,0,0,0,0], &"dev": [0,0,0,0,0], &"opt": [0,0,0,0,0], &"cla": [0,0,0,0,0]},
	},
	&"survivalist": {
		"stat": &"ing", "origin": &"analog",
		"pcts": {&"ort": 0.15, &"ing": 0.48, &"amb": 0.20, &"dev": 0.08, &"opt": 0.05, &"cla": 0.04},
		"alloc": {&"ort": [2,0,0,0,0], &"ing": [4,4,3,2,0], &"amb": [4,1,0,0,0], &"dev": [0,0,0,0,0], &"opt": [0,0,0,0,0], &"cla": [0,0,0,0,0]},
	},
	&"enculted": {
		"stat": &"amb", "origin": &"analog",
		"pcts": {&"ort": 0.10, &"ing": 0.12, &"amb": 0.55, &"dev": 0.09, &"opt": 0.07, &"cla": 0.07},
		"alloc": {&"ort": [1,0,0,0,0], &"ing": [2,0,0,0,0], &"amb": [4,4,4,3,2], &"dev": [0,0,0,0,0], &"opt": [0,0,0,0,0], &"cla": [0,0,0,0,0]},
	},
	## --- Cyborg classes ---
	&"forged": {
		"stat": &"dev", "origin": &"cyborg",
		"pcts": {&"ort": 0.08, &"ing": 0.05, &"amb": 0.03, &"dev": 0.42, &"opt": 0.28, &"cla": 0.14},
		"alloc": {&"ort": [0,0,0,0,0], &"ing": [0,0,0,0,0], &"amb": [0,0,0,0,0], &"dev": [4,4,2,1,1], &"opt": [4,1,0,0,0], &"cla": [3,0,0,0,0]},
	},
	&"automaton": {
		"stat": &"opt", "origin": &"cyborg",
		"pcts": {&"ort": 0.04, &"ing": 0.06, &"amb": 0.05, &"dev": 0.18, &"opt": 0.50, &"cla": 0.17},
		"alloc": {&"ort": [0,0,0,0,0], &"ing": [0,0,0,0,0], &"amb": [0,0,0,0,0], &"dev": [3,0,0,0,0], &"opt": [4,4,4,2,0], &"cla": [3,0,0,0,0]},
	},
	&"polymath": {
		"stat": &"cla", "origin": &"cyborg",
		"pcts": {&"ort": 0.07, &"ing": 0.04, &"amb": 0.06, &"dev": 0.12, &"opt": 0.25, &"cla": 0.46},
		"alloc": {&"ort": [0,0,0,0,0], &"ing": [0,0,0,0,0], &"amb": [0,0,0,0,0], &"dev": [2,0,0,0,0], &"opt": [4,1,0,0,0], &"cla": [4,4,3,1,1]},
	},
	## --- Origin classes (no own stat — all team or opposing) ---
	&"analog": {
		"stat": &"", "origin": &"analog",
		"pcts": {&"ort": 0.20, &"ing": 0.22, &"amb": 0.18, &"dev": 0.15, &"opt": 0.14, &"cla": 0.11},
		"alloc": {&"ort": [4,2,0,0,0], &"ing": [4,2,0,0,0], &"amb": [4,0,0,0,0], &"dev": [0,0,0,0,0], &"opt": [0,0,0,0,0], &"cla": [4,0,0,0,0]},
	},
	&"cyborg": {
		"stat": &"", "origin": &"cyborg",
		"pcts": {&"ort": 0.12, &"ing": 0.10, &"amb": 0.13, &"dev": 0.24, &"opt": 0.22, &"cla": 0.19},
		"alloc": {&"ort": [0,0,0,0,0], &"ing": [0,0,0,0,0], &"amb": [0,0,0,0,0], &"dev": [4,3,0,0,0], &"opt": [4,2,0,0,0], &"cla": [4,3,0,0,0]},
	},
}

## Class keys in cycle order — press Left/Right arrows to preview different builds.
const CLASS_ORDER: Array[StringName] = [
	&"gentleman", &"survivalist", &"enculted",
	&"forged", &"automaton", &"polymath",
	&"analog", &"cyborg",
]

var _class_index := 3  # default: forged
var _placeholder_pcts: Dictionary
var _placeholder_alloc: Dictionary
var _placeholder_class_stat: StringName
var _placeholder_class_origin: StringName

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
	_load_build(_class_index)
	theme = UIThemeState.theme
	UIThemeState.changed.connect(func() -> void: theme = UIThemeState.theme; _repaint())
	_build_layout()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_talents"):
		if visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()
	# Debug: cycle through class builds with Left/Right when panel is open.
	elif visible and event is InputEventKey and event.pressed:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_RIGHT:
			_class_index = (_class_index + 1) % CLASS_ORDER.size()
			_rebuild()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_LEFT:
			_class_index = (_class_index - 1 + CLASS_ORDER.size()) % CLASS_ORDER.size()
			_rebuild()
			get_viewport().set_input_as_handled()

func open_menu() -> void:
	visible = true

func close_menu() -> void:
	visible = false

func _load_build(index: int) -> void:
	var build: Dictionary = CLASS_BUILDS[CLASS_ORDER[index]]
	_placeholder_pcts = build["pcts"]
	_placeholder_alloc = build["alloc"]
	_placeholder_class_stat = build["stat"]
	_placeholder_class_origin = build["origin"]

func _rebuild() -> void:
	_load_build(_class_index)
	# Clear existing rows.
	for row: Dictionary in _rows:
		row["container"].queue_free()
	_rows.clear()
	# Rebuild rows with new build data.
	for row_def: Dictionary in STAT_ROWS:
		_rows.append(_build_row(row_def))
	# Update title and talent point display.
	var class_key: StringName = CLASS_ORDER[_class_index]
	_title_label.text = "TALENTS — %s  [←/→]" % [class_key.capitalize()]
	var total_spent := 0
	for alloc_arr: Array in _placeholder_alloc.values():
		for pts: int in alloc_arr:
			total_spent += pts
	_talent_label.text = "Talent Points: %d / %d" % [total_spent, PLACEHOLDER_TALENT_POINTS]
	_do_layout()
	_repaint()

# ---------------------------------------------------------------------------
# Threshold logic
# ---------------------------------------------------------------------------

## Returns the tier thresholds for a given row stat based on the player's class.
func _get_tiers_for_stat(row_stat: StringName, row_origin: StringName) -> Array[float]:
	# Own class tree — always unlocked (origin classes have no own stat).
	if _placeholder_class_stat != &"" and row_stat == _placeholder_class_stat:
		return TIERS_OWN
	# Same origin — team rates.
	if row_origin == _placeholder_class_origin:
		return TIERS_TEAM
	# Different origin — opposing rates.
	return TIERS_OPPOSING

## Returns how many tiers are unlocked given a percentage and threshold array.
func _calc_unlocked_tier(pct: float, tiers: Array[float]) -> int:
	var unlocked := 0
	for i in TIER_COUNT:
		if pct >= tiers[i]:
			unlocked = i + 1
	return unlocked

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

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
	var total_spent := 0
	for alloc_arr: Array in _placeholder_alloc.values():
		for pts: int in alloc_arr:
			total_spent += pts
	_talent_label.text = "Talent Points: %d / %d" % [total_spent, PLACEHOLDER_TALENT_POINTS]
	_content.add_child(_talent_label)

	_note_label = Label.new()
	_note_label.theme_type_variation = &"SmallLabel"
	_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note_label.text = "Percentages reflect share of total stat allocation from equipped gear"
	_content.add_child(_note_label)

	# Origin group backgrounds (added before rows so they render behind).
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
	var row_origin: StringName = row_def["origin"]
	var stat_color: Color = AttributeState.STAT_COLORS.get(stat_id, Color.WHITE)
	var pct: float = _placeholder_pcts.get(stat_id, 0.0)
	var tiers: Array[float] = _get_tiers_for_stat(stat_id, row_origin)
	var alloc: Array = _placeholder_alloc.get(stat_id, [0, 0, 0, 0, 0])

	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(container)

	# Class name — larger font.
	var header := Label.new()
	header.text = row_def["class"]
	header.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	container.add_child(header)

	# Stat name + percentage — smaller, below class name.
	var stat_i18n_key: StringName = AttributeState.STAT_I18N.get(stat_id, &"")
	var stat_display: String = tr(stat_i18n_key) if stat_i18n_key != &"" else str(stat_id)
	var stat_label := Label.new()
	stat_label.text = "%s  %d%%" % [stat_display, int(pct * 100)]
	stat_label.theme_type_variation = &"SmallLabel"
	stat_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	container.add_child(stat_label)

	# Progress bar background.
	var bar_bg := ColorRect.new()
	bar_bg.color = BAR_BG_COLOR
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bar_bg)

	# Progress bar fill.
	var bar_fill := ColorRect.new()
	bar_fill.color = stat_color
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bar_fill)

	# Tier markers on bar.
	var markers: Array[ColorRect] = []
	for i in TIER_COUNT:
		var marker := ColorRect.new()
		marker.color = TIER_MARKER_COLOR
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		container.add_child(marker)
		markers.append(marker)

	# Tier labels (T1–T5) centered in each section.
	var tier_labels: Array[Label] = []
	for i in TIER_COUNT:
		var lbl := Label.new()
		lbl.text = "T%d" % (i + 1)
		lbl.theme_type_variation = &"SmallLabel"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		container.add_child(lbl)
		tier_labels.append(lbl)

	# Skill nodes — 5 tiers × NODES_PER_TIER in a NODE_ROWS × NODE_COLS grid.
	var node_rects: Array[Array] = []
	for tier in TIER_COUNT:
		var tier_nodes: Array[ColorRect] = []
		for j in NODES_PER_TIER:
			var node_rect := ColorRect.new()
			node_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		"stat_color": stat_color,
		"pct": pct,
		"tiers": tiers,
		"alloc": alloc,
	}

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

func _do_layout() -> void:
	var screen := get_viewport_rect().size

	# Row height = bar + gap + node grid.
	var node_grid_h: float = float(NODE_ROWS) * NODE_SIZE.y + float(NODE_ROWS - 1) * NODE_GAP
	var row_h: float = BAR_HEIGHT + BAR_NODE_GAP + node_grid_h
	var rows_per_group := 3
	var group_count := 2
	# Each group: 3 rows + 2 inner gaps. Plus GROUP_GAP between the two groups.
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

	# Title + talent points + note.
	_title_label.position = Vector2(0, 8)
	_title_label.size = Vector2(panel_w, TITLE_HEIGHT)
	_talent_label.position = Vector2(0, 8 + TITLE_HEIGHT)
	_talent_label.size = Vector2(panel_w, TALENT_HEIGHT)
	_note_label.position = Vector2(0, 8 + TITLE_HEIGHT + TALENT_HEIGHT)
	_note_label.size = Vector2(panel_w, NOTE_HEIGHT)

	# The bar/tree area starts after the label column.
	var bar_x: float = PANEL_MARGIN.x + LABEL_WIDTH + LABEL_GAP
	var bar_w: float = panel_w - bar_x - PANEL_MARGIN.x
	var body_y: float = PANEL_MARGIN.y + TITLE_HEIGHT + TALENT_HEIGHT + NOTE_HEIGHT + HEADER_GAP

	# Position origin group backgrounds.
	var analog_y: float = body_y - GROUP_PADDING.y
	var analog_h: float = group_inner_h + GROUP_PADDING.y * 2.0
	_analog_group_bg.position = Vector2(PANEL_MARGIN.x - GROUP_PADDING.x, analog_y)
	_analog_group_bg.size = Vector2(panel_w - PANEL_MARGIN.x * 2.0 + GROUP_PADDING.x * 2.0, analog_h)

	var cyborg_y: float = body_y + group_inner_h + GROUP_GAP - GROUP_PADDING.y
	var cyborg_h: float = group_inner_h + GROUP_PADDING.y * 2.0
	_cyborg_group_bg.position = Vector2(PANEL_MARGIN.x - GROUP_PADDING.x, cyborg_y)
	_cyborg_group_bg.size = Vector2(panel_w - PANEL_MARGIN.x * 2.0 + GROUP_PADDING.x * 2.0, cyborg_h)

	# Uniform section width — all rows divide the bar into equal fifths.
	var section_w: float = bar_w / float(TIER_COUNT)

	var row_count: int = STAT_ROWS.size()
	for ri in row_count:
		var row: Dictionary = _rows[ri]
		# Insert GROUP_GAP between the two origin groups (after row index 2).
		var group_offset: float = GROUP_GAP if ri >= rows_per_group else 0.0
		var ry: float = body_y + float(ri) * (row_h + ROW_GAP) + group_offset

		row["container"].position = Vector2(PANEL_MARGIN.x, ry)
		row["container"].size = Vector2(panel_w - PANEL_MARGIN.x * 2.0, row_h)

		# Left label block: class name (larger) + stat line (smaller), vertically centered.
		var label_block_h: float = CLASS_NAME_HEIGHT + STAT_LINE_HEIGHT
		var label_y: float = (row_h - label_block_h) * 0.5
		row["header"].position = Vector2(0, label_y)
		row["header"].size = Vector2(LABEL_WIDTH, CLASS_NAME_HEIGHT)
		row["stat_label"].position = Vector2(0, label_y + CLASS_NAME_HEIGHT)
		row["stat_label"].size = Vector2(LABEL_WIDTH, STAT_LINE_HEIGHT)

		# Bar spans the right portion.
		var local_bar_x: float = LABEL_WIDTH + LABEL_GAP
		row["bar_bg"].position = Vector2(local_bar_x, 0)
		row["bar_bg"].size = Vector2(bar_w, BAR_HEIGHT)

		var fill_w: float = bar_w * clampf(row["pct"], 0.0, 1.0)
		row["bar_fill"].position = Vector2(local_bar_x, 0)
		row["bar_fill"].size = Vector2(fill_w, BAR_HEIGHT)

		# Tier markers at uniform equal divisions.
		for mi in TIER_COUNT:
			var mx: float = local_bar_x + section_w * float(mi + 1)
			row["markers"][mi].position = Vector2(mx - TIER_MARKER_WIDTH * 0.5, 0)
			row["markers"][mi].size = Vector2(TIER_MARKER_WIDTH, BAR_HEIGHT)
			# Hide the last marker (right edge of bar).
			row["markers"][mi].visible = mi < TIER_COUNT - 1

		# Tier labels + node grids — uniform sections.
		var nodes_y: float = BAR_HEIGHT + BAR_NODE_GAP
		for ti in TIER_COUNT:
			var sx: float = local_bar_x + section_w * float(ti)

			row["tier_labels"][ti].position = Vector2(sx, 0)
			row["tier_labels"][ti].size = Vector2(section_w, BAR_HEIGHT)

			# Nodes centered in section.
			var grid_w: float = float(NODE_COLS) * NODE_SIZE.x + float(NODE_COLS - 1) * NODE_GAP
			var grid_h: float = float(NODE_ROWS) * NODE_SIZE.y + float(NODE_ROWS - 1) * NODE_GAP
			var grid_x: float = sx + (section_w - grid_w) * 0.5
			var grid_y: float = nodes_y + (node_grid_h - grid_h) * 0.5

			for j in NODES_PER_TIER:
				var nr: int = j / NODE_COLS
				var nc: int = j % NODE_COLS
				var nx: float = grid_x + float(nc) * (NODE_SIZE.x + NODE_GAP)
				var ny: float = grid_y + float(nr) * (NODE_SIZE.y + NODE_GAP)
				row["node_rects"][ti][j].position = Vector2(nx, ny)
				row["node_rects"][ti][j].size = NODE_SIZE

# ---------------------------------------------------------------------------
# Paint
# ---------------------------------------------------------------------------

func _repaint() -> void:
	var p := UIThemeState.palette
	_title_label.add_theme_color_override(&"font_color", p.accent)
	_talent_label.add_theme_color_override(&"font_color", TALENT_POINT_COLOR)
	_note_label.add_theme_color_override(&"font_color", Color(p.text_dim, 0.5))

	for row: Dictionary in _rows:
		var stat_color: Color = row["stat_color"]
		var pct: float = row["pct"]
		var tiers: Array[float] = row["tiers"]
		var unlocked_tier: int = _calc_unlocked_tier(pct, tiers)

		# Class name in stat color, stat line slightly muted.
		row["header"].add_theme_color_override(&"font_color", stat_color)
		row["stat_label"].add_theme_color_override(&"font_color", Color(stat_color, 0.6))

		# Tier labels.
		for ti in TIER_COUNT:
			var tier_unlocked: bool = (ti + 1) <= unlocked_tier
			var lbl_color: Color = stat_color if tier_unlocked else TIER_LABEL_COLOR
			row["tier_labels"][ti].add_theme_color_override(&"font_color", lbl_color)

		# Nodes — three states: allocated (point spent), available (unlocked, no point), locked.
		var alloc: Array = row["alloc"]
		for tier in TIER_COUNT:
			var tier_unlocked: bool = (tier + 1) <= unlocked_tier
			var points_in_tier: int = alloc[tier]
			for j in NODES_PER_TIER:
				var rect: ColorRect = row["node_rects"][tier][j]
				if tier_unlocked and j < points_in_tier:
					# Allocated — talent point spent.
					rect.color = Color(stat_color.r, stat_color.g, stat_color.b, NODE_ALLOCATED_ALPHA)
				elif tier_unlocked:
					# Available — tier unlocked but no point spent here.
					rect.color = Color(stat_color.r, stat_color.g, stat_color.b, NODE_AVAILABLE_ALPHA)
				else:
					# Locked — tier not reached.
					rect.color = NODE_LOCKED_COLOR
