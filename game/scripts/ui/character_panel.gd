extends Control

const PANEL_SIZE := Vector2(440.0, 500.0)
const SHEET_HEIGHT := 290.0
const STATS_POS := Vector2(16.0, 34.0)
const STATS_SIZE := Vector2(220.0, 140.0)
const MORALITY_POS := Vector2(16.0, 170.0)
const EQUIP_SLOT_SIZE := Vector2(38.0, 38.0)
const EQUIP_GAP := 4.0
const EQUIP_COLS := 3
const EQUIP_ROWS := 3
const UTIL_SLOTS := 4
const INV_SLOT_SIZE := Vector2(34.0, 34.0)
const INV_GAP := 3.0
const INV_COLS := 8
const MORALITY_SIZE := Vector2(72.0, 72.0)

const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const MORALITY_DOT_COLOR := Color(1.0, 0.85, 0.2, 1.0)

const EQUIP_SLOTS: Array[Dictionary] = [
	{"row": 0, "col": 0, "label_key": "EQUIP_HEAD", "id": &"head", "accepts": &"head"},
	{"row": 0, "col": 1, "label_key": "EQUIP_LIGHT", "id": &"light", "accepts": &"light"},
	{"row": 0, "col": 2, "label_key": "EQUIP_BACKPACK", "id": &"backpack", "accepts": &"backpack"},
	{"row": 1, "col": 0, "label_key": "EQUIP_WEAPON", "id": &"weapon", "accepts": &"weapon"},
	{"row": 1, "col": 1, "label_key": "EQUIP_CHEST", "id": &"chest", "accepts": &"chest"},
	{"row": 1, "col": 2, "label_key": "EQUIP_OFFHAND", "id": &"offhand", "accepts": &"offhand"},
	{"row": 2, "col": 0, "label_key": "EQUIP_GLOVES", "id": &"gloves", "accepts": &"gloves"},
	{"row": 2, "col": 1, "label_key": "", "id": &"belt", "accepts": &"belt", "belt": true},
	{"row": 2, "col": 2, "label_key": "EQUIP_BOOTS", "id": &"boots", "accepts": &"boots"},
]

var _hp_label: Label
var _resource_label: Label
var _credits_label: Label
var _player: Node = null
var _utility_row: Control = null
var _utility_slots: Array[ItemSlot] = []
var _inventory_host: Control = null
var _inventory_grid: Control = null

func _ready() -> void:
	visible = false
	theme = UIThemeState.theme
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(&"ui_modal")
	_build_layout()
	_bind_player()
	UIThemeState.changed.connect(_on_theme_changed)
	InventoryState.capacity_changed.connect(_on_capacity_changed)
	_refresh_utility_visibility()
	_rebuild_inventory_grid()

func _on_theme_changed() -> void:
	theme = UIThemeState.theme

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_inventory"):
		if visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()

func open_menu() -> void:
	visible = true

func close_menu() -> void:
	visible = false

func _build_layout() -> void:
	var p := UIThemeState.palette
	var backdrop := ColorRect.new()
	backdrop.color = BACKDROP_COLOR
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.custom_minimum_size = PANEL_SIZE
	panel.size = PANEL_SIZE
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5
	panel.add_theme_stylebox_override(&"panel", _opaque_panel_style(p))
	panel.add_to_group(&"modal_inner_panel")
	add_child(panel)

	var sheet := Control.new()
	sheet.name = "CharacterSheet"
	sheet.position = Vector2.ZERO
	sheet.size = Vector2(PANEL_SIZE.x, SHEET_HEIGHT)
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(sheet)
	_build_character_sheet(sheet)

	var divider := ColorRect.new()
	divider.color = Color(p.accent_dim.r, p.accent_dim.g, p.accent_dim.b, 0.7)
	divider.position = Vector2(12.0, SHEET_HEIGHT)
	divider.size = Vector2(PANEL_SIZE.x - 24.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(divider)

	var inv := Control.new()
	inv.name = "Inventory"
	inv.position = Vector2(0.0, SHEET_HEIGHT)
	inv.size = Vector2(PANEL_SIZE.x, PANEL_SIZE.y - SHEET_HEIGHT)
	inv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(inv)
	_build_inventory(inv)

func _build_character_sheet(parent: Control) -> void:
	var p := UIThemeState.palette
	var title := _make_label("CHARACTER_PANEL_TITLE", 14, p.text)
	title.position = Vector2(14.0, 10.0)
	title.size = Vector2(PANEL_SIZE.x - 28.0, 20.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(title)

	var stats := VBoxContainer.new()
	stats.position = STATS_POS
	stats.size = STATS_SIZE
	stats.add_theme_constant_override(&"separation", 2)
	parent.add_child(stats)
	stats.add_child(_make_stat_row("CHARACTER_PANEL_NAME", "CHARACTER_PANEL_OPERATOR"))
	stats.add_child(_make_stat_row("CHARACTER_PANEL_CLASS", _class_label()))
	stats.add_child(_make_stat_row("CHARACTER_PANEL_SPEC", _spec_label()))
	stats.add_child(_make_stat_row("CHARACTER_PANEL_LEVEL", "1"))
	_hp_label = _make_stat_value("— / —")
	stats.add_child(_make_stat_row_with_value("CHARACTER_PANEL_HEALTH", _hp_label))
	_resource_label = _make_stat_value("— / —")
	stats.add_child(_make_stat_row_with_value("CHARACTER_PANEL_RESOURCE", _resource_label))
	_credits_label = _make_stat_value("₢ 0")
	_credits_label.add_theme_color_override(&"font_color", p.credits)
	stats.add_child(_make_stat_row_with_value("CHARACTER_PANEL_CREDITS", _credits_label))

	var morality := _build_morality_plane()
	morality.position = MORALITY_POS
	parent.add_child(morality)

	var morality_caption := _make_label("CHARACTER_PANEL_MORALITY", 9, p.text_dim)
	morality_caption.position = Vector2(MORALITY_POS.x, MORALITY_POS.y + MORALITY_SIZE.y + 2.0)
	morality_caption.size = Vector2(MORALITY_SIZE.x, 12.0)
	morality_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(morality_caption)

	var equip_total_width := float(EQUIP_COLS) * EQUIP_SLOT_SIZE.x + float(EQUIP_COLS - 1) * EQUIP_GAP
	var equip_total_height := float(EQUIP_ROWS) * EQUIP_SLOT_SIZE.y + float(EQUIP_ROWS - 1) * EQUIP_GAP
	var equip := Control.new()
	equip.size = Vector2(equip_total_width, equip_total_height)
	equip.position = Vector2(PANEL_SIZE.x - equip_total_width - 18.0, 34.0)
	equip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(equip)
	for entry in EQUIP_SLOTS:
		var row: int = entry["row"]
		var col: int = entry["col"]
		var label_key: String = entry.get("label_key", "")
		var id: StringName = entry["id"]
		var accepts: StringName = entry["accepts"]
		var is_belt: bool = entry.get("belt", false)
		var empty_text := tr(_belt_label_key()) if is_belt else label_key
		var slot := ItemSlot.new()
		slot.size = EQUIP_SLOT_SIZE
		slot.custom_minimum_size = EQUIP_SLOT_SIZE
		slot.configure_equipment(id, empty_text, accepts)
		slot.position = Vector2(
			float(col) * (EQUIP_SLOT_SIZE.x + EQUIP_GAP),
			float(row) * (EQUIP_SLOT_SIZE.y + EQUIP_GAP),
		)
		equip.add_child(slot)

	_build_utility_row(parent, equip.position.x, equip.position.y + equip_total_height + 12.0, equip_total_width)

func _build_utility_row(parent: Control, equip_x: float, y: float, _equip_width: float) -> void:
	var util_total_width := float(UTIL_SLOTS) * EQUIP_SLOT_SIZE.x + float(UTIL_SLOTS - 1) * EQUIP_GAP
	_utility_row = Control.new()
	_utility_row.size = Vector2(util_total_width, EQUIP_SLOT_SIZE.y)
	var util_x := equip_x + (float(EQUIP_COLS) * EQUIP_SLOT_SIZE.x + float(EQUIP_COLS - 1) * EQUIP_GAP) - util_total_width
	util_x = min(util_x, PANEL_SIZE.x - util_total_width - 18.0)
	util_x = max(util_x, 18.0)
	_utility_row.position = Vector2(util_x, y)
	_utility_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_utility_row)

	_utility_slots.clear()
	for i in UTIL_SLOTS:
		var slot := ItemSlot.new()
		slot.size = EQUIP_SLOT_SIZE
		slot.custom_minimum_size = EQUIP_SLOT_SIZE
		var id := StringName("utility_%d" % (i + 1))
		var empty_text := tr(_utility_format_key()) % (i + 1)
		slot.configure_equipment(id, empty_text, &"utility")
		slot.position = Vector2(float(i) * (EQUIP_SLOT_SIZE.x + EQUIP_GAP), 0.0)
		_utility_row.add_child(slot)
		_utility_slots.append(slot)

func _refresh_utility_visibility() -> void:
	if _utility_slots.is_empty():
		return
	var cap := InventoryState.get_utility_capacity()
	for i in _utility_slots.size():
		_utility_slots[i].visible = i < cap

func _build_inventory(parent: Control) -> void:
	var title := _make_label("CHARACTER_PANEL_INVENTORY", 12, UIThemeState.palette.text)
	title.position = Vector2(14.0, 8.0)
	title.size = Vector2(PANEL_SIZE.x - 28.0, 16.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(title)

	_inventory_host = parent

func _rebuild_inventory_grid() -> void:
	if _inventory_host == null:
		return
	if _inventory_grid != null:
		_inventory_grid.queue_free()
		_inventory_grid = null
	var capacity := InventoryState.get_inventory_capacity()
	var rows := int(ceil(float(capacity) / float(INV_COLS)))
	rows = max(rows, 1)
	var grid_width := float(INV_COLS) * INV_SLOT_SIZE.x + float(INV_COLS - 1) * INV_GAP
	var grid_height := float(rows) * INV_SLOT_SIZE.y + float(rows - 1) * INV_GAP
	var grid := Control.new()
	grid.size = Vector2(grid_width, grid_height)
	grid.position = Vector2((PANEL_SIZE.x - grid_width) * 0.5, 28.0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inventory_host.add_child(grid)
	for i in capacity:
		var r := i / INV_COLS
		var c := i % INV_COLS
		var slot := ItemSlot.new()
		slot.size = INV_SLOT_SIZE
		slot.custom_minimum_size = INV_SLOT_SIZE
		slot.configure_inventory(i)
		slot.position = Vector2(
			float(c) * (INV_SLOT_SIZE.x + INV_GAP),
			float(r) * (INV_SLOT_SIZE.y + INV_GAP),
		)
		grid.add_child(slot)
	_inventory_grid = grid

func _on_capacity_changed() -> void:
	_refresh_utility_visibility()
	_rebuild_inventory_grid()

func _build_morality_plane() -> Control:
	var p := UIThemeState.palette
	var root := Control.new()
	root.size = MORALITY_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg := ColorRect.new()
	bg.color = p.slot_bg
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	var border := ReferenceRect.new()
	border.border_color = p.slot_border
	border.border_width = 1.0
	border.editor_only = false
	border.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(border)

	var axis_color := Color(p.slot_border.r, p.slot_border.g, p.slot_border.b, 0.5)
	var v_axis := ColorRect.new()
	v_axis.color = axis_color
	v_axis.position = Vector2(MORALITY_SIZE.x * 0.5 - 0.5, 4.0)
	v_axis.size = Vector2(1.0, MORALITY_SIZE.y - 8.0)
	v_axis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(v_axis)

	var h_axis := ColorRect.new()
	h_axis.color = axis_color
	h_axis.position = Vector2(4.0, MORALITY_SIZE.y * 0.5 - 0.5)
	h_axis.size = Vector2(MORALITY_SIZE.x - 8.0, 1.0)
	h_axis.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(h_axis)

	var dot := ColorRect.new()
	dot.color = MORALITY_DOT_COLOR
	dot.size = Vector2(6.0, 6.0)
	dot.position = Vector2(MORALITY_SIZE.x * 0.5 - 3.0, MORALITY_SIZE.y * 0.5 - 3.0)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dot)

	return root

func _make_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var value := _make_stat_value(value_text)
	return _make_stat_row_with_value(label_text, value)

func _make_stat_row_with_value(label_text: String, value: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var key := Label.new()
	key.text = label_text
	key.add_theme_font_size_override(&"font_size", 11)
	key.add_theme_color_override(&"font_color", UIThemeState.palette.text_dim)
	key.custom_minimum_size = Vector2(64.0, 0.0)
	row.add_child(key)
	row.add_child(value)
	return row

func _make_stat_value(value_text: String) -> Label:
	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override(&"font_size", 11)
	value.add_theme_color_override(&"font_color", UIThemeState.palette.text)
	return value

func _make_label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _bind_player() -> void:
	_player = get_tree().get_first_node_in_group(&"player")
	if _player == null:
		return
	if _player.has_signal(&"health_changed"):
		_player.health_changed.connect(_on_health_changed)
	if _player.has_signal(&"resource_changed"):
		_player.resource_changed.connect(_on_resource_changed)
	if _player.has_signal(&"credits_changed"):
		_player.credits_changed.connect(_on_credits_changed)
	var max_hp: int = int(_player.max_health)
	_on_health_changed(max_hp, max_hp)
	var pool = _player.resource_pool
	if pool != null:
		_on_resource_changed(pool.start_value, pool.max_value)
	if _player.has_method(&"get_credits"):
		_on_credits_changed(int(_player.get_credits()))

func _on_health_changed(current: int, max_value: int) -> void:
	if _hp_label != null:
		_hp_label.text = "%d / %d" % [max(current, 0), max(max_value, 1)]

func _on_resource_changed(current: int, max_value: int) -> void:
	if _resource_label != null:
		_resource_label.text = "%d / %d" % [max(current, 0), max(max_value, 0)]

func _on_credits_changed(amount: int) -> void:
	if _credits_label != null:
		_credits_label.text = "₢ %d" % max(amount, 0)

func _class_label() -> String:
	match PlayerState.class_id:
		&"human":
			return "CLASS_HUMAN"
		&"cyborg":
			return "CLASS_CYBORG"
	return "COMMON_DASH"

func _belt_label_key() -> String:
	if PlayerState.class_id == &"cyborg":
		return "EQUIP_MAINBOARD"
	return "EQUIP_BELT"

func _utility_format_key() -> String:
	if PlayerState.class_id == &"cyborg":
		return "EQUIP_BUS_FORMAT"
	return "EQUIP_UTILITY_FORMAT"

func _opaque_panel_style(p: UIThemeConfig) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(p.panel_bg.r, p.panel_bg.g, p.panel_bg.b, 0.96)
	s.border_color = p.panel_border
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	return s

func _spec_label() -> String:
	if PlayerState.spec_id == &"":
		return "SPEC_NONE"
	var class_str := String(PlayerState.class_id).to_upper()
	var spec_str := String(PlayerState.spec_id).to_upper()
	return "SPEC_%s_%s" % [class_str, spec_str]
