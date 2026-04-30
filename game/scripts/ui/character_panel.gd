extends Control
class_name CharacterPanel

const PANEL_SIZE := Vector2(440.0, 500.0)
const SHEET_HEIGHT := 290.0
const STATS_POS := Vector2(16.0, 34.0)
const STATS_SIZE := Vector2(220.0, 140.0)
const ATTR_POS := Vector2(16.0, 158.0)
const ATTR_WIDTH := 270.0
const EQUIP_SLOT_SIZE := Vector2(38.0, 38.0)
const EQUIP_GAP := 4.0
const EQUIP_COLS := 3
const EQUIP_ROWS := 3
const UTIL_SLOTS := 4
const INV_SLOT_SIZE := Vector2(34.0, 34.0)
const INV_GAP := 3.0
const INV_COLS := 8

const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 0.55)

const ALLOC_BAR_HEIGHT    := 10.0
const ALLOC_LABEL_HEIGHT  := 9.0
const ALLOC_LABEL_GAP     := 4.0
const ALLOC_SEG_GAP       := 2.0
const ALLOC_SEG_MIN_WIDTH := 40.0
const ALLOC_BAR_BG        := Color(0.12, 0.12, 0.12, 0.9)

const EQUIP_SLOTS: Array[Dictionary] = [
	{"row": 0, "col": 0, "label_key": "EQUIP_HEAD", "id": &"head", "accepts": &"head"},
	{"row": 0, "col": 1, "label_key": "EQUIP_OPTICS", "id": &"optics", "accepts": &"optics"},
	{"row": 0, "col": 2, "label_key": "EQUIP_BACKPACK", "id": &"backpack", "accepts": &"backpack"},
	{"row": 1, "col": 0, "label_key": "EQUIP_WEAPON", "id": &"weapon", "accepts": &"weapon"},
	{"row": 1, "col": 1, "label_key": "EQUIP_CHEST", "id": &"chest", "accepts": &"chest"},
	{"row": 1, "col": 2, "label_key": "EQUIP_OFFHAND", "id": &"offhand", "accepts": &"offhand"},
	{"row": 2, "col": 0, "label_key": "EQUIP_GLOVES", "id": &"gloves", "accepts": &"gloves"},
	{"row": 2, "col": 1, "label_key": "", "id": &"belt", "accepts": &"belt", "belt": true},
	{"row": 2, "col": 2, "label_key": "EQUIP_BOOTS", "id": &"boots", "accepts": &"boots"},
]

var _alloc_bar: Control = null
var _alloc_segments: Array[ColorRect] = []
var _alloc_labels: Array[Label] = []
var _alloc_seg_bounds: Array[float] = []
var _alloc_stat_order: Array[StringName] = []
var _alloc_stat_pcts: Dictionary = {}

var _hp_label: Label
var _resource_label: Label
var _credits_label: Label
var _attr_value_labels: Dictionary = {}
var _player: Node = null
var _utility_row: Control = null
var _utility_slots: Array[ItemSlot] = []
var _inventory_host: Control = null
var _inventory_grid: Control = null
var _panel_node: Panel = null
var _divider_node: ColorRect = null
var _held_item: Item = null
var _held_source: ItemSlot = null
var _held_cursor: Label = null
var _all_slots: Array[ItemSlot] = []

func _ready() -> void:
	visible = false
	theme = UIThemeState.theme
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(&"ui_modal")
	_build_layout()
	_bind_player.call_deferred()
	UIThemeState.changed.connect(_on_theme_changed)
	InventoryState.capacity_changed.connect(_on_capacity_changed)
	AttributeState.stats_changed.connect(_on_stats_changed)
	_refresh_utility_visibility()
	_rebuild_inventory_grid()

func _process(_delta: float) -> void:
	if _held_cursor != null:
		_held_cursor.position = get_viewport().get_mouse_position() - Vector2(12, 12)

func _on_theme_changed() -> void:
	theme = UIThemeState.theme
	var p := UIThemeState.palette
	if _panel_node != null:
		_panel_node.add_theme_stylebox_override(&"panel", _opaque_panel_style(p))
	if _divider_node != null:
		_divider_node.color = Color(p.accent_dim.r, p.accent_dim.g, p.accent_dim.b, 0.7)
	if _credits_label != null:
		_credits_label.add_theme_color_override(&"font_color", p.credits)

func _gui_input(event: InputEvent) -> void:
	if _held_item != null and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var inside := _panel_node != null and _panel_node.get_global_rect().has_point(mb.global_position)
			if inside:
				_cancel_held()
			else:
				var item := _held_item
				_clear_held()
				get_tree().call_group(&"world_item_dropper", &"drop_item", item)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_held()
			accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _held_item != null and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_held()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"toggle_inventory"):
		if visible:
			close_menu()
		else:
			open_menu()
		get_viewport().set_input_as_handled()

func is_holding_item() -> bool:
	return _held_item != null

func open_menu() -> void:
	get_tree().call_group(&"ui_modal", &"close_menu")
	visible = true

func close_menu() -> void:
	_cancel_held()
	visible = false

func _on_slot_clicked(slot: ItemSlot) -> void:
	if _held_item == null:
		# Pick up
		var item := slot.current_item()
		if item == null:
			return
		_held_item = item
		_held_source = slot
		slot._assign(null)
		_show_held_cursor(item)
		_update_slot_highlights()
	else:
		# Place
		if slot == _held_source:
			# Click same slot — cancel
			_held_source._assign(_held_item)
			_clear_held()
			return
		if not slot.can_accept_item(_held_item):
			return
		# Swap if target has an item
		var existing := slot.current_item()
		if existing != null and _held_source != null:
			if not _held_source.can_accept_item(existing):
				return
		slot._assign(_held_item) # This must happen before assigning existing back
		if existing != null and _held_source != null:
			_held_source._assign(existing)
		_clear_held()

func _on_slot_right_clicked(slot: ItemSlot) -> void:
	if _held_item != null:
		_cancel_held()
		return
	if slot.role == ItemSlot.Role.INVENTORY:
		_quick_equip(slot)
	else:
		_quick_unequip(slot)

func _quick_equip(slot: ItemSlot) -> void:
	var item := slot.current_item()
	if item == null:
		return
	var equip_slot_id := _find_equip_slot_for_kind(item.kind)
	if equip_slot_id == &"":
		return
	var displaced := InventoryState.get_equipped(equip_slot_id)
	# Free inventory slot first so set_equipped has room for 2H offhand displacement
	InventoryState.set_inventory_item(slot.inventory_index, null)
	InventoryState.set_equipped(equip_slot_id, item)
	if displaced != null:
		if not InventoryState.add_to_inventory(displaced):
			get_tree().call_group(&"world_item_dropper", &"drop_item", displaced)

func _quick_unequip(slot: ItemSlot) -> void:
	var item := slot.current_item()
	if item == null:
		return
	if not InventoryState.add_to_inventory(item):
		return
	InventoryState.set_equipped(slot.slot_id, null)

func _find_equip_slot_for_kind(kind: StringName) -> StringName:
	if kind == &"utility":
		var cap := InventoryState.get_utility_capacity()
		for i in cap:
			var uid := StringName("utility_%d" % (i + 1))
			if InventoryState.get_equipped(uid) == null:
				return uid
		return &"utility_1" if cap > 0 else &""
	for entry: Dictionary in EQUIP_SLOTS:
		if (entry["accepts"] as StringName) == kind:
			return entry["id"]
	return &""

func _cancel_held() -> void:
	if _held_item != null and _held_source != null:
		_held_source._assign(_held_item)
	_clear_held()

func _clear_held() -> void:
	_held_item = null
	_held_source = null
	if _held_cursor != null:
		_held_cursor.queue_free()
		_held_cursor = null
	_clear_slot_highlights()

func _show_held_cursor(item: Item) -> void:
	if _held_cursor != null:
		_held_cursor.queue_free()
	_held_cursor = Label.new()
	_held_cursor.text = item.glyph
	_held_cursor.theme_type_variation = &"DragPreview"
	_held_cursor.modulate = item.glyph_color
	_held_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_held_cursor.z_index = 100
	add_child(_held_cursor)

func _update_slot_highlights() -> void:
	if _held_item == null:
		_clear_slot_highlights()
		return
	var p := UIThemeState.palette
	for slot in _all_slots:
		if slot == _held_source:
			slot.set_highlight(p.accent_dim)
		elif slot.can_accept_item(_held_item):
			slot.set_highlight(p.accent)
		else:
			slot.clear_highlight()

func _clear_slot_highlights() -> void:
	for slot in _all_slots:
		slot.clear_highlight()

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
	_panel_node = panel

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
	_divider_node = divider

	var inv := Control.new()
	inv.name = "Inventory"
	inv.position = Vector2(0.0, SHEET_HEIGHT)
	inv.size = Vector2(PANEL_SIZE.x, PANEL_SIZE.y - SHEET_HEIGHT)
	inv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(inv)
	_build_inventory(inv)

func _build_character_sheet(parent: Control) -> void:
	var p := UIThemeState.palette
	var title := _make_label("CHARACTER_PANEL_TITLE", &"SectionLabel", p.text)
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
	stats.add_child(_make_stat_row("CHARACTER_PANEL_LEVEL", "1"))
	_hp_label = _make_stat_value("— / —")
	stats.add_child(_make_stat_row_with_value("CHARACTER_PANEL_HEALTH", _hp_label))
	_resource_label = _make_stat_value("— / —")
	stats.add_child(_make_stat_row_with_value("CHARACTER_PANEL_RESOURCE", _resource_label))
	_credits_label = _make_stat_value("₢ 0")
	_credits_label.add_theme_color_override(&"font_color", p.credits)
	stats.add_child(_make_stat_row_with_value("CHARACTER_PANEL_CREDITS", _credits_label))

	_build_attribute_section(parent)
	_build_alloc_bar(parent)

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
		slot.clicked.connect(_on_slot_clicked)
		slot.right_clicked.connect(_on_slot_right_clicked)
		equip.add_child(slot)
		_all_slots.append(slot)

	# Utility/bus row must clear the attribute section (header 17px + grid 56px below ATTR_POS.y).
	var attr_bottom := ATTR_POS.y + 17.0 + 56.0
	var util_y := maxf(equip.position.y + equip_total_height + 12.0, attr_bottom + 12.0)
	_build_utility_row(parent, equip.position.x, util_y, equip_total_width)

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
		slot.clicked.connect(_on_slot_clicked)
		slot.right_clicked.connect(_on_slot_right_clicked)
		_utility_row.add_child(slot)
		_utility_slots.append(slot)
		_all_slots.append(slot)

func _refresh_utility_visibility() -> void:
	if _utility_slots.is_empty():
		return
	var cap := InventoryState.get_utility_capacity()
	for i in _utility_slots.size():
		_utility_slots[i].visible = i < cap

func _build_inventory(parent: Control) -> void:
	var title := _make_label("CHARACTER_PANEL_INVENTORY", &"SubLabel")
	title.position = Vector2(14.0, 8.0)
	title.size = Vector2(PANEL_SIZE.x - 28.0, 16.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(title)

	_inventory_host = parent

func _rebuild_inventory_grid() -> void:
	if _inventory_host == null:
		return
	var capacity := InventoryState.get_inventory_capacity()
	var rows := maxi(int(ceil(float(capacity) / float(INV_COLS))), 1)
	var grid_width := float(INV_COLS) * INV_SLOT_SIZE.x + float(INV_COLS - 1) * INV_GAP
	var grid_height := float(rows) * INV_SLOT_SIZE.y + float(rows - 1) * INV_GAP

	if _inventory_grid == null:
		var grid := Control.new()
		grid.size = Vector2(grid_width, grid_height)
		grid.position = Vector2((PANEL_SIZE.x - grid_width) * 0.5, 28.0)
		grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inventory_host.add_child(grid)
		_inventory_grid = grid

	_inventory_grid.size = Vector2(grid_width, grid_height)

	# Collect current inventory slots in index order.
	var inv_slots: Array[ItemSlot] = []
	for slot: ItemSlot in _inventory_grid.get_children():
		inv_slots.append(slot)

	var current := inv_slots.size()
	if capacity > current:
		for i in range(current, capacity):
			var r: int = floori(float(i) / INV_COLS)
			var c: int = i - r * INV_COLS
			var slot := ItemSlot.new()
			slot.size = INV_SLOT_SIZE
			slot.custom_minimum_size = INV_SLOT_SIZE
			slot.configure_inventory(i)
			slot.position = Vector2(
				float(c) * (INV_SLOT_SIZE.x + INV_GAP),
				float(r) * (INV_SLOT_SIZE.y + INV_GAP),
			)
			slot.clicked.connect(_on_slot_clicked)
			slot.right_clicked.connect(_on_slot_right_clicked)
			_inventory_grid.add_child(slot)
			_all_slots.append(slot)
	elif capacity < current:
		for i in range(capacity, current):
			var slot := inv_slots[i]
			_all_slots.erase(slot)
			slot.queue_free()

func _on_capacity_changed() -> void:
	_refresh_utility_visibility()
	_rebuild_inventory_grid()

func _build_alloc_bar(parent: Control) -> void:
	var bar_x := ATTR_POS.x
	var bar_w := PANEL_SIZE.x - ATTR_POS.x * 2.0
	var bar_area_h := ALLOC_LABEL_HEIGHT + ALLOC_LABEL_GAP + ALLOC_BAR_HEIGHT
	var bar_y := ATTR_POS.y + 17.0 + 56.0 + 12.0

	_alloc_bar = Control.new()
	_alloc_bar.position = Vector2(bar_x, bar_y)
	_alloc_bar.size = Vector2(bar_w, bar_area_h)
	_alloc_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_alloc_bar.mouse_exited.connect(func() -> void:
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip"))
	_alloc_bar.gui_input.connect(_on_alloc_bar_input)
	parent.add_child(_alloc_bar)

	var rollable: Array[StringName] = AttributeState.ANALOG_TEAM_STATS.duplicate()
	rollable.append_array(AttributeState.CYBORG_TEAM_STATS)
	for _stat in rollable:
		var lbl := Label.new()
		lbl.theme_type_variation = &"SmallLabel"
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_alloc_bar.add_child(lbl)
		_alloc_labels.append(lbl)

		var seg := ColorRect.new()
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg.color = ALLOC_BAR_BG
		_alloc_bar.add_child(seg)
		_alloc_segments.append(seg)

	_repaint_alloc_bar()

func _repaint_alloc_bar() -> void:
	if _alloc_bar == null:
		return
	var pcts := AttributeState.get_all_stat_pcts()
	_alloc_stat_pcts = pcts
	var total := 0.0
	for pct: float in pcts.values():
		total += pct

	# Sort: primary → team → opp_team → opposing (same priority as talents panel)
	var rollable: Array[StringName] = AttributeState.ANALOG_TEAM_STATS.duplicate()
	rollable.append_array(AttributeState.CYBORG_TEAM_STATS)
	var sorted: Array[StringName] = rollable.duplicate()
	sorted.sort_custom(func(a: StringName, b: StringName) -> bool:
		return AttributeState.get_stat_rel_priority(a, PlayerState.class_id, PlayerState.spec_id) \
			< AttributeState.get_stat_rel_priority(b, PlayerState.class_id, PlayerState.spec_id))
	_alloc_stat_order = sorted

	var bar_w := _alloc_bar.size.x
	var visible_count := 0
	for s: StringName in sorted:
		if pcts.get(s, 0.0) > 0.0:
			visible_count += 1
	# Reserve a minimum slice per visible segment so labels stay readable; the
	# remainder is split proportionally. Empty state splits evenly across all
	# segments as gray placeholders.
	var is_empty := total <= 0.001
	var visual_count: int = sorted.size() if is_empty else visible_count
	var gap_total := float(maxi(visual_count - 1, 0)) * ALLOC_SEG_GAP
	var avail_w := bar_w - gap_total
	var proportional_w := maxf(avail_w - float(visual_count) * ALLOC_SEG_MIN_WIDTH, 0.0)
	var label_y := 0.0
	var seg_y := ALLOC_LABEL_HEIGHT + ALLOC_LABEL_GAP
	_alloc_seg_bounds.clear()
	var x := 0.0
	for i in sorted.size():
		var stat_id: StringName = sorted[i]
		var pct: float = pcts.get(stat_id, 0.0)
		var seg_w: float
		if is_empty:
			seg_w = avail_w / float(sorted.size())
		elif pct > 0.0:
			seg_w = ALLOC_SEG_MIN_WIDTH + (pct / total) * proportional_w
		else:
			seg_w = 0.0
		_alloc_seg_bounds.append(x)
		var stat_color: Color = AttributeState.STAT_COLORS.get(stat_id, Color.WHITE)
		var short_name: String = AttributeState.STAT_SHORT.get(stat_id, (stat_id as String).to_upper())
		var lbl: Label = _alloc_labels[i]
		lbl.visible = pct > 0.0
		lbl.text = "%s %d%%" % [short_name, int(pct * 100)]
		lbl.position = Vector2(x, label_y)
		lbl.size = Vector2(seg_w, ALLOC_LABEL_HEIGHT)
		lbl.add_theme_color_override(&"font_color", Color(stat_color.r, stat_color.g, stat_color.b, 0.8))
		lbl.add_theme_font_size_override(&"font_size", 8)
		var seg: ColorRect = _alloc_segments[i]
		seg.position = Vector2(x, seg_y)
		seg.size = Vector2(seg_w, ALLOC_BAR_HEIGHT)
		var rel_key := AttributeState.get_stat_rel_color_key(stat_id, PlayerState.class_id, PlayerState.spec_id)
		var rel_color: Color = AttributeState.RELATIONSHIP_COLORS[rel_key]
		seg.color = Color(rel_color.r, rel_color.g, rel_color.b, 0.7 if not is_empty else 0.15)
		if seg_w > 0.0:
			x += seg_w + ALLOC_SEG_GAP
	_alloc_seg_bounds.append(x)

func _on_alloc_bar_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if _alloc_stat_order.is_empty() or _alloc_seg_bounds.size() < 2:
		return
	var mx: float = (event as InputEventMouseMotion).position.x
	var hover_idx := -1
	for i in _alloc_stat_order.size():
		if mx >= _alloc_seg_bounds[i]:
			hover_idx = i
	if hover_idx < 0:
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
		return
	var stat_id: StringName = _alloc_stat_order[hover_idx]
	var key: StringName = AttributeState.STAT_I18N.get(stat_id, &"")
	var stat_name: String = tr(key) if key != &"" else (stat_id as String).capitalize()
	var pct: float = _alloc_stat_pcts.get(stat_id, 0.0)
	var unlocked: int = AttributeState.get_unlocked_tier(stat_id, PlayerState.class_id, PlayerState.spec_id)
	var thresholds: Array[float] = AttributeState.get_tier_thresholds(stat_id, PlayerState.class_id, PlayerState.spec_id)
	var tier_text: String = "Tier %s unlocked" % AttributeState.TIER_ROMAN[unlocked - 1] if unlocked > 0 else "no tier unlocked"
	var next_text: String = "Tier %s at %d%%" % [AttributeState.TIER_ROMAN[unlocked], int(thresholds[unlocked] * 100)] if unlocked < AttributeState.TIER_COUNT else "maxed"
	get_tree().call_group(&"interactable_tooltip", &"show_text",
		"%s  %d%%\n%s · next: %s" % [stat_name, int(pct * 100), tier_text, next_text])

func _build_attribute_section(parent: Control) -> void:
	var header := _make_label("CHARACTER_PANEL_ATTRIBUTES", &"SectionLabel")
	header.position = Vector2(ATTR_POS.x, ATTR_POS.y)
	header.size = Vector2(ATTR_WIDTH, 14.0)
	parent.add_child(header)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override(&"separation", 8)
	grid.position = Vector2(ATTR_POS.x, ATTR_POS.y + 17.0)
	grid.size = Vector2(ATTR_WIDTH, 56.0)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(grid)

	var analog_col := VBoxContainer.new()
	analog_col.add_theme_constant_override(&"separation", 2)
	analog_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	analog_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(analog_col)

	var cyborg_col := VBoxContainer.new()
	cyborg_col.add_theme_constant_override(&"separation", 2)
	cyborg_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cyborg_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(cyborg_col)

	for stat_id in AttributeState.ANALOG_STATS:
		analog_col.add_child(_make_attr_row(stat_id))
	for stat_id in AttributeState.CYBORG_STATS:
		cyborg_col.add_child(_make_attr_row(stat_id))

const STAT_DESCRIPTIONS: Dictionary = {
	&"soul": "The essence of human willpower and spiritual resilience. Derived from the average of Orthodoxy, Ingenuity, and Ambition.",
	&"itf": "Mastery over machine integration and digital consciousness. Derived from the average of Deviation, Optimization, and Clarity.",
	&"ort": "Adherence to tradition and established order. Governs defensive fortitude and resistance to corruption.",
	&"ing": "Resourcefulness and adaptive thinking. Enhances crafting efficiency and environmental awareness.",
	&"amb": "Raw desire for power and forbidden knowledge. Fuels dark arts and amplifies risk-reward mechanics.",
	&"dev": "Willingness to push beyond safe boundaries. Increases raw damage output and critical potential.",
	&"opt": "Precision engineering and calculated efficiency. Improves cooldown recovery and resource management.",
	&"cla": "Depth of understanding and analytical insight. Broadens skill versatility and elemental mastery.",
}

func _make_attr_row(stat_id: StringName) -> HBoxContainer:
	var color: Color = AttributeState.STAT_COLORS[stat_id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_entered.connect(_on_attr_row_hovered.bind(stat_id))
	row.mouse_exited.connect(func() -> void:
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip"))

	var name_lbl := Label.new()
	name_lbl.text = AttributeState.STAT_I18N[stat_id]
	name_lbl.theme_type_variation = &"SmallLabel"
	name_lbl.add_theme_font_size_override(&"font_size", 9)
	name_lbl.add_theme_color_override(&"font_color", color)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var val_lbl := Label.new()
	val_lbl.text = _format_stat_value(stat_id)
	val_lbl.theme_type_variation = &"SmallLabel"
	val_lbl.add_theme_font_size_override(&"font_size", 9)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(val_lbl)

	_attr_value_labels[stat_id] = val_lbl
	return row

func _on_attr_row_hovered(stat_id: StringName) -> void:
	var key: StringName = AttributeState.STAT_I18N.get(stat_id, &"")
	var stat_name: String = tr(key) if key != &"" else (stat_id as String).capitalize()
	var desc: String = STAT_DESCRIPTIONS.get(stat_id, "")
	var val := AttributeState.get_stat(stat_id)

	var lines: Array[String] = []

	if stat_id in AttributeState.ROLLABLE_STATS:
		# Show the total value and percentage share.
		var total := 0
		for s in AttributeState.ROLLABLE_STATS:
			total += AttributeState.get_stat(s)
		if total > 0:
			var pct := int(round(float(val) / float(total) * 100.0))
			lines.append("Total: %d  (%d%% of %d)" % [val, pct, total])
		else:
			lines.append("Total: 0")

		# Break down contributions from each equipped item.
		var has_source := false
		for slot_id: StringName in InventoryState.equipment:
			var item: Item = InventoryState.equipment[slot_id]
			if item == null:
				continue
			var amount: int = int(item.stat_modifiers.get(stat_id, 0))
			if amount != 0:
				lines.append("  +%d from %s" % [amount, item.name_key])
				has_source = true
		if not has_source and val == 0:
			lines.append("  No equipment bonuses")
	else:
		# Derived stat (Soul / Interface) — show the average formula.
		var team: Array[StringName]
		if stat_id == &"soul":
			team = AttributeState.ANALOG_TEAM_STATS
		else:
			team = AttributeState.CYBORG_TEAM_STATS
		var parts: Array[String] = []
		for s in team:
			var s_key: StringName = AttributeState.STAT_I18N.get(s, &"")
			var s_name: String = tr(s_key) if s_key != &"" else String(s).capitalize()
			parts.append("%s %d" % [s_name, AttributeState.get_stat(s)])
		lines.append("Value: %d  (avg of %s)" % [val, ", ".join(parts)])

	if not desc.is_empty():
		lines.append("")
		lines.append(desc)

	get_tree().call_group(&"interactable_tooltip", &"show_talent_node", stat_name, "\n".join(lines))

func _format_stat_value(stat_id: StringName) -> String:
	return str(AttributeState.get_stat(stat_id))

func _on_stats_changed() -> void:
	for stat_id: StringName in _attr_value_labels:
		_attr_value_labels[stat_id].text = _format_stat_value(stat_id)
	_repaint_alloc_bar()

func _make_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var value := _make_stat_value(value_text)
	return _make_stat_row_with_value(label_text, value)

func _make_stat_row_with_value(label_text: String, value: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var key := Label.new()
	key.text = label_text
	key.theme_type_variation = &"BodyLabel"
	key.add_theme_color_override(&"font_color", UIThemeState.palette.text_dim)
	key.custom_minimum_size = Vector2(64.0, 0.0)
	row.add_child(key)
	row.add_child(value)
	return row

func _make_stat_value(value_text: String) -> Label:
	var value := Label.new()
	value.text = value_text
	value.theme_type_variation = &"BodyLabel"
	return value

func _make_label(text: String, variation: StringName, color: Color = Color.TRANSPARENT) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	if color != Color.TRANSPARENT:
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
	if PlayerState.spec_id != &"":
		var class_str := String(PlayerState.class_id).to_upper()
		var spec_str := String(PlayerState.spec_id).to_upper()
		if PlayerState.spec_id == &"count" and PlayerState.gender == &"female":
			return "SPEC_ANALOG_COUNTESS"
		return "SPEC_%s_%s" % [class_str, spec_str]
	match PlayerState.class_id:
		&"analog": return "CLASS_ANALOG"
		&"cyborg": return "CLASS_CYBORG"
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
