extends Control
class_name CharacterPanel

const PANEL_SIZE := Vector2(380.0, 420.0)
const SHEET_HEIGHT := 240.0
const STATS_POS := Vector2(16.0, 34.0)
const STATS_SIZE := Vector2(200.0, 200.0)
const STAT_FONT_SIZE := 11
const EQUIP_SLOT_SIZE := Vector2(38.0, 38.0)
const EQUIP_GAP := 4.0
const EQUIP_COLS := 3
const EQUIP_ROWS := 3
const INV_SLOT_SIZE := Vector2(26.0, 26.0)
const INV_GAP := 2.0
const INV_COLS := 8

const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 0.55)


const EQUIP_SLOTS: Array[Dictionary] = [
	{"row": 0, "col": 0, "label_key": "EQUIP_HEAD", "id": &"head", "accepts": &"head"},
	{"row": 0, "col": 1, "label_key": "EQUIP_CHEST", "id": &"chest", "accepts": &"chest"},
	{"row": 0, "col": 2, "label_key": "EQUIP_HANDS", "id": &"hands", "accepts": &"hands"},
	{"row": 1, "col": 0, "label_key": "EQUIP_WEAPON", "id": &"weapon", "accepts": &"weapon"},
	{"row": 1, "col": 1, "label_key": "EQUIP_BACKPACK", "id": &"backpack", "accepts": &"backpack"},
	{"row": 1, "col": 2, "label_key": "EQUIP_OFFHAND", "id": &"offhand", "accepts": &"offhand"},
	{"row": 2, "col": 0, "label_key": "EQUIP_LEGS", "id": &"legs", "accepts": &"legs"},
	{"row": 2, "col": 1, "label_key": "EQUIP_FEET", "id": &"feet", "accepts": &"feet"},
	{"row": 2, "col": 2, "label_key": "", "id": &"", "accepts": &""},
]

# Forged Amalgamation perk-gated extra weapon slots. Rendered on row 3 to
# the right of the standard 3x3 grid; visibility flips when the
# extra_weapon_slots aggregate changes (PerkState.perks_changed signal).
const EXTRA_WEAPON_SLOTS_LAYOUT: Array[Dictionary] = [
	{"row": 3, "col": 0, "label_key": "EQUIP_WEAPON_2", "id": &"weapon_2", "accepts": &"weapon"},
	{"row": 3, "col": 1, "label_key": "EQUIP_WEAPON_3", "id": &"weapon_3", "accepts": &"weapon"},
	{"row": 3, "col": 2, "label_key": "EQUIP_WEAPON_4", "id": &"weapon_4", "accepts": &"weapon"},
]

var _level_label: Label
var _hp_label: Label
var _resource_label: Label
var _credits_label: Label
var _dmg_red_label: Label
var _crit_label: Label
var _atk_spd_label: Label
var _hit_label: Label
var _move_spd_label: Label
var _cdr_label: Label
var _player: Node = null
# Per-slot ItemSlot nodes for the Forged Amalgamation extra weapon slots.
# Built once during _build_layout; visibility is toggled by
# _refresh_extra_weapon_slot_visibility on perk changes. Order matches
# SlotRegistry.EXTRA_WEAPON_SLOTS so we can show the first N when N
# extras are unlocked.
var _extra_weapon_slots: Array[ItemSlot] = []
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
	# Forged Amalgamation perk gates the extra weapon slots — toggle their
	# visibility whenever the perk set recomputes (gear swap, tier change,
	# class respec).
	PerkState.perks_changed.connect(_refresh_extra_weapon_slot_visibility)
	_refresh_extra_weapon_slot_visibility()
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
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	var inside := _panel_node != null and _panel_node.get_global_rect().has_point(mb.global_position)
	if _held_item != null:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if inside:
				_cancel_held()
			else:
				var item := _held_item
				_clear_held()
				get_tree().call_group(&"world_item_dropper", &"drop_item", item)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_held()
			accept_event()
	elif mb.button_index == MOUSE_BUTTON_LEFT and not inside:
		close_menu()
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if _held_item != null:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_held()
				get_viewport().set_input_as_handled()
				return
			# Left-click outside the panel drops the item into the world.
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and not visible:
				var item := _held_item
				_clear_held()
				get_tree().call_group(&"world_item_dropper", &"drop_item", item)
				get_viewport().set_input_as_handled()
				return
		# Escape cancels the held item at any time.
		if event.is_action_pressed(&"ui_cancel"):
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
	# If the player re-opens the panel while still holding an item,
	# reparent the cursor back so slot placement works normally.
	if _held_cursor != null and _held_cursor.get_parent() != self:
		_held_cursor.get_parent().remove_child(_held_cursor)
		add_child(_held_cursor)
		_update_slot_highlights()

func close_menu() -> void:
	if _held_item != null:
		# Keep the held item alive — player can drop it into the world
		# after closing the panel, or press Escape / right-click to cancel.
		# Reparent the cursor so it stays visible while the panel is hidden.
		if _held_cursor != null and _held_cursor.get_parent() == self:
			remove_child(_held_cursor)
			get_parent().add_child(_held_cursor)
	else:
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
	# Mirror the rejection rules in InventoryState.set_equipped — checking up
	# front avoids the "clear inventory slot, set_equipped no-ops, item lost"
	# trap.
	if equip_slot_id == &"offhand" and InventoryState.is_two_handed_equipped():
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
	# Re-show the panel's own content if hidden by close_menu.
	# Slot highlights were already cleared above.

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
	# IGNORE (not STOP) so clicks outside the inner panel pass through
	# to CharacterPanel._gui_input and reach the click-to-drop branch.
	# CharacterPanel itself is MOUSE_FILTER_STOP, so the click is still
	# absorbed by the modal — it just doesn't get eaten by the backdrop
	# before our handler sees it.
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var panel := Panel.new()
	panel.name = "Panel"
	panel.custom_minimum_size = PANEL_SIZE
	panel.size = PANEL_SIZE
	# Center horizontally, sit above the bottom HUD (98px clearance).
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_SIZE.x * 0.5
	panel.offset_top = -PANEL_SIZE.y * 0.5 - 30.0
	panel.offset_right = PANEL_SIZE.x * 0.5
	panel.offset_bottom = PANEL_SIZE.y * 0.5 - 30.0
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
	stats.add_theme_constant_override(&"separation", 1)
	parent.add_child(stats)
	# Use the player's chosen name from character creation; fall back to the
	# generic "Operator" label only when the prototype scene bypasses creation.
	var name_text: String = PlayerState.player_name if not PlayerState.player_name.is_empty() else tr("CHARACTER_PANEL_OPERATOR")
	stats.add_child(_make_stat_row("CHARACTER_PANEL_NAME", name_text))
	stats.add_child(_make_stat_row("CHARACTER_PANEL_CLASS", _class_label()))
	_level_label = _make_stat_value(str(PlayerState.level))
	stats.add_child(_make_stat_row_with_value("CHARACTER_PANEL_LEVEL", _level_label))
	_hp_label = _make_stat_value("— / —")
	stats.add_child(_make_stat_row_with_value("CHARACTER_PANEL_HEALTH", _hp_label))
	_resource_label = _make_stat_value("— / —")
	stats.add_child(_make_stat_row_with_value("CHARACTER_PANEL_RESOURCE", _resource_label))
	_credits_label = _make_stat_value("₢ 0")
	_credits_label.add_theme_color_override(&"font_color", p.credits)
	stats.add_child(_make_stat_row_with_value("CHARACTER_PANEL_CREDITS", _credits_label))

	# Combat stats — updated via stats_changed signal from the player.
	_dmg_red_label = _make_stat_value("0")
	stats.add_child(_make_stat_row_with_value("Armor", _dmg_red_label))
	_crit_label = _make_stat_value("0%")
	stats.add_child(_make_stat_row_with_value("Crit", _crit_label))
	_hit_label = _make_stat_value("100%")
	stats.add_child(_make_stat_row_with_value("Accuracy", _hit_label))
	_atk_spd_label = _make_stat_value("+0%")
	stats.add_child(_make_stat_row_with_value("Atk Spd", _atk_spd_label))
	_move_spd_label = _make_stat_value("+0%")
	stats.add_child(_make_stat_row_with_value("Move Spd", _move_spd_label))
	_cdr_label = _make_stat_value("0%")
	stats.add_child(_make_stat_row_with_value("CDR", _cdr_label))


	var equip_total_width := float(EQUIP_COLS) * EQUIP_SLOT_SIZE.x + float(EQUIP_COLS - 1) * EQUIP_GAP
	var equip_total_height := float(EQUIP_ROWS) * EQUIP_SLOT_SIZE.y + float(EQUIP_ROWS - 1) * EQUIP_GAP
	var equip := Control.new()
	equip.size = Vector2(equip_total_width, equip_total_height)
	equip.position = Vector2(PANEL_SIZE.x - equip_total_width - 18.0, 34.0)
	equip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(equip)
	for entry in EQUIP_SLOTS:
		var id: StringName = entry["id"]
		if id == &"":
			continue  # placeholder entry — skip
		var row: int = entry["row"]
		var col: int = entry["col"]
		var label_key: String = entry.get("label_key", "")
		var accepts: StringName = entry["accepts"]
		var slot := ItemSlot.new()
		slot.size = EQUIP_SLOT_SIZE
		slot.custom_minimum_size = EQUIP_SLOT_SIZE
		slot.configure_equipment(id, label_key, accepts)
		slot.position = Vector2(
			float(col) * (EQUIP_SLOT_SIZE.x + EQUIP_GAP),
			float(row) * (EQUIP_SLOT_SIZE.y + EQUIP_GAP),
		)
		slot.clicked.connect(_on_slot_clicked)
		slot.right_clicked.connect(_on_slot_right_clicked)
		equip.add_child(slot)
		_all_slots.append(slot)

	# Forged Amalgamation extra weapon slots — built once in row 3, then
	# shown/hidden by _refresh_extra_weapon_slot_visibility based on the
	# `extra_weapon_slots` perk aggregate.
	_extra_weapon_slots.clear()
	for entry in EXTRA_WEAPON_SLOTS_LAYOUT:
		var row: int = entry["row"]
		var col: int = entry["col"]
		var label_key: String = entry.get("label_key", "")
		var id: StringName = entry["id"]
		var accepts: StringName = entry["accepts"]
		var slot := ItemSlot.new()
		slot.size = EQUIP_SLOT_SIZE
		slot.custom_minimum_size = EQUIP_SLOT_SIZE
		slot.configure_equipment(id, label_key, accepts)
		slot.position = Vector2(
			float(col) * (EQUIP_SLOT_SIZE.x + EQUIP_GAP),
			float(row) * (EQUIP_SLOT_SIZE.y + EQUIP_GAP),
		)
		slot.visible = false
		slot.clicked.connect(_on_slot_clicked)
		slot.right_clicked.connect(_on_slot_right_clicked)
		equip.add_child(slot)
		_all_slots.append(slot)
		_extra_weapon_slots.append(slot)



# Show the first N extra weapon slots where N = perk-granted extras.
# Sized for the equipment block on row 3; the surrounding utility row's
# Y position was computed before extras were considered, so the row
# stays put — extras tuck under the standard grid without reflowing the
# rest of the panel.
func _refresh_extra_weapon_slot_visibility() -> void:
	var unlocked := InventoryState.get_extra_weapon_slot_count()
	for i in _extra_weapon_slots.size():
		_extra_weapon_slots[i].visible = i < unlocked


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
	_rebuild_inventory_grid()


func _make_stat_row(label_text: String, value_text: String) -> HBoxContainer:
	var value := _make_stat_value(value_text)
	return _make_stat_row_with_value(label_text, value)

func _make_stat_row_with_value(label_text: String, value: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 6)
	var key := Label.new()
	key.text = label_text
	key.theme_type_variation = &"BodyLabel"
	key.add_theme_font_size_override(&"font_size", STAT_FONT_SIZE)
	key.add_theme_color_override(&"font_color", UIThemeState.palette.text_dim)
	key.custom_minimum_size = Vector2(64.0, 0.0)
	row.add_child(key)
	row.add_child(value)
	return row

func _make_stat_value(value_text: String) -> Label:
	var value := Label.new()
	value.text = value_text
	value.theme_type_variation = &"BodyLabel"
	value.add_theme_font_size_override(&"font_size", STAT_FONT_SIZE)
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
	if _player.has_signal(&"stats_changed"):
		_player.stats_changed.connect(_on_stats_changed)
	PlayerState.leveled_up.connect(_on_leveled_up)
	var max_health: int = int(_player.max_health)
	_on_health_changed(max_health, max_health)
	var pool = _player.resource_pool
	if pool != null:
		_on_resource_changed(pool.start_value, pool.max_value)
	if _player.has_method(&"get_credits"):
		_on_credits_changed(int(_player.get_credits()))
	_on_stats_changed()
	_on_leveled_up(PlayerState.level, 0)

func _on_health_changed(current: int, max_value: int) -> void:
	if _hp_label != null:
		_hp_label.text = "%d / %d" % [max(current, 0), max(max_value, 1)]

func _on_resource_changed(current: int, max_value: int) -> void:
	if _resource_label != null:
		_resource_label.text = "%d / %d" % [max(current, 0), max(max_value, 0)]

func _on_credits_changed(amount: int) -> void:
	if _credits_label != null:
		_credits_label.text = "₢ %d" % max(amount, 0)

func _on_leveled_up(new_level: int, _hp_gain: int) -> void:
	if _level_label != null:
		_level_label.text = str(new_level)

func _on_stats_changed() -> void:
	if _player == null:
		return
	var p_node: PrototypePlayer = _player as PrototypePlayer
	if p_node == null:
		return
	if _dmg_red_label != null:
		_dmg_red_label.text = str(p_node._gear_damage_reduction)
	if _crit_label != null:
		var crit_pct: float = p_node._gear_crit_chance_bonus * 100.0
		_crit_label.text = "%d%%" % int(round(crit_pct))
	if _hit_label != null:
		var hit_pct: float = 100.0 + p_node._gear_hit_chance_bonus * 100.0
		_hit_label.text = "%d%%" % int(round(hit_pct))
	if _atk_spd_label != null:
		var atk_pct: float = p_node._gear_attack_speed_bonus * 100.0
		_atk_spd_label.text = "+%d%%" % int(round(atk_pct))
	if _move_spd_label != null:
		_move_spd_label.text = "+%d%%" % p_node._gear_move_speed_bonus
	if _cdr_label != null:
		var cdr_pct: float = p_node._gear_cooldown_reduction * 100.0
		_cdr_label.text = "%d%%" % int(round(cdr_pct))

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


func _opaque_panel_style(p: UIThemeConfig) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(p.panel_bg.r, p.panel_bg.g, p.panel_bg.b, 0.96)
	s.border_color = p.panel_border
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	return s
