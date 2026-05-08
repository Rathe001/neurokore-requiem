class_name ItemSlot extends Control

enum Role { INVENTORY, EQUIPMENT }

signal clicked(slot: ItemSlot)
signal right_clicked(slot: ItemSlot)

var role: Role = Role.INVENTORY
var slot_id: StringName = &""
var accepts_kind: StringName = &""
var inventory_index: int = -1
var empty_label_text: String = ""

var _empty_label: Label
var _glyph: Label
var _is_drag_source: bool = false
var _bg: ColorRect
var _border: ReferenceRect

func configure_equipment(id: StringName, empty_text: String, accepts: StringName = &"") -> void:
	role = Role.EQUIPMENT
	slot_id = id
	accepts_kind = accepts if accepts != &"" else id
	empty_label_text = empty_text

func configure_inventory(index: int) -> void:
	role = Role.INVENTORY
	inventory_index = index
	empty_label_text = ""

func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	theme = UIThemeState.theme
	_build_visuals()
	InventoryState.equipment_changed.connect(_on_equipment_changed)
	InventoryState.inventory_changed.connect(_on_inventory_changed)
	UIThemeState.changed.connect(_on_theme_changed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	tree_exiting.connect(_on_tree_exiting)
	_refresh()


func _on_tree_exiting() -> void:
	_on_mouse_exited()
	InventoryState.equipment_changed.disconnect(_on_equipment_changed)
	InventoryState.inventory_changed.disconnect(_on_inventory_changed)
	UIThemeState.changed.disconnect(_on_theme_changed)

func _on_theme_changed() -> void:
	theme = UIThemeState.theme
	var p := UIThemeState.palette
	if _bg != null:
		_bg.color = p.slot_bg
	if _border != null:
		_border.border_color = p.slot_border
	if _empty_label != null:
		_empty_label.add_theme_color_override(&"font_color", Color(p.text_dim.r, p.text_dim.g, p.text_dim.b, 0.85))

func _on_mouse_entered() -> void:
	var item := current_item()
	if item != null:
		get_tree().call_group(&"interactable_tooltip", &"show_item", item)

func _on_mouse_exited() -> void:
	if is_inside_tree():
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func current_item() -> Item:
	if role == Role.EQUIPMENT:
		return InventoryState.get_equipped(slot_id)
	return InventoryState.get_inventory_item(inventory_index)

func _build_visuals() -> void:
	var p := UIThemeState.palette
	_bg = ColorRect.new()
	_bg.color = p.slot_bg
	_bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_bg)

	_border = ReferenceRect.new()
	_border.border_color = p.slot_border
	_border.border_width = 1.0
	_border.editor_only = false
	_border.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_border.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_border)

	_empty_label = Label.new()
	_empty_label.text = empty_label_text
	_empty_label.theme_type_variation = &"StatLabel"
	_empty_label.add_theme_color_override(&"font_color", Color(p.text_dim.r, p.text_dim.g, p.text_dim.b, 0.85))
	_empty_label.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_empty_label)

	_glyph = Label.new()
	_glyph.theme_type_variation = &"SlotGlyph"
	_glyph.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_glyph.mouse_filter = MOUSE_FILTER_IGNORE
	_glyph.visible = false
	add_child(_glyph)

func set_highlight(color: Color) -> void:
	if _border != null:
		_border.border_color = color
		_border.border_width = 2.0 if color != UIThemeState.palette.slot_border else 1.0

func clear_highlight() -> void:
	if _border != null:
		_border.border_color = UIThemeState.palette.slot_border
		_border.border_width = 1.0

func can_accept_item(item: Item) -> bool:
	if item == null:
		return false
	if role == Role.EQUIPMENT and item.kind != accepts_kind:
		return false
	if role == Role.EQUIPMENT and slot_id == &"offhand" and InventoryState.is_two_handed_equipped():
		return false
	# Forged Amalgamation extra weapon slots: 1H only, and only when the
	# perk has unlocked the slot. Mirroring the rules in
	# InventoryState.set_equipped — rejecting here too means a failed
	# drop returns the item to its source instead of vanishing (the click-
	# to-place path in CharacterPanel clears the held item after _assign
	# succeeds, so a silent set_equipped no-op would lose it).
	if role == Role.EQUIPMENT and SlotRegistry.is_extra_weapon_slot(slot_id):
		if item.two_handed:
			return false
		if not InventoryState.is_extra_weapon_slot_unlocked(slot_id):
			return false
	return true

func _refresh() -> void:
	var item := current_item()
	var has_item := item != null
	_empty_label.visible = not has_item and empty_label_text != ""
	_empty_label.text = empty_label_text
	_glyph.visible = has_item
	if has_item:
		_glyph.text = item.glyph
		_glyph.modulate = item.glyph_color

func _on_equipment_changed(slot: StringName) -> void:
	if role == Role.EQUIPMENT and slot == slot_id:
		_refresh()

func _on_inventory_changed(index: int) -> void:
	if role == Role.INVENTORY and index == inventory_index:
		_refresh()

func _notification(what: int) -> void:
	if what != NOTIFICATION_DRAG_END:
		return
	var was_source := _is_drag_source
	_is_drag_source = false
	if not was_source:
		return
	if get_viewport().gui_is_drag_successful():
		return
	var mouse := get_viewport().get_mouse_position()
	for inner in get_tree().get_nodes_in_group(&"modal_inner_panel"):
		if inner is Control and (inner as Control).is_visible_in_tree():
			if (inner as Control).get_global_rect().has_point(mouse):
				return
	var item := current_item()
	if item == null:
		return
	_assign(null)
	get_tree().call_group(&"world_item_dropper", &"drop_item", item)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			clicked.emit(self)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			right_clicked.emit(self)
			accept_event()

func _get_drag_data(_pos: Vector2) -> Variant:
	# Don't start a drag while the character panel has a held item (click-to-move mode)
	var panel := get_tree().get_first_node_in_group(&"ui_modal")
	if panel != null and panel.has_method(&"is_holding_item") and panel.is_holding_item():
		return null
	var item := current_item()
	if item == null:
		return null
	_is_drag_source = true
	var preview := Label.new()
	preview.text = item.glyph
	preview.theme_type_variation = &"DragPreview"
	preview.modulate = item.glyph_color
	preview.custom_minimum_size = Vector2(32, 32)
	preview.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	set_drag_preview(preview)
	return {"item": item, "source": self}

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var incoming = data.get("item")
	var source = data.get("source") as ItemSlot
	if incoming == null or source == self:
		return false
	# Same per-slot acceptance rules as can_accept_item (kept in sync —
	# native drag-drop uses _can_drop_data; click-to-place uses
	# can_accept_item; both must reject identically or items get lost).
	if not can_accept_item(incoming):
		return false
	var my_prev := current_item()
	if my_prev != null and source.role == Role.EQUIPMENT and my_prev.kind != source.accepts_kind:
		return false
	return true

func _drop_data(_pos: Vector2, data: Variant) -> void:
	var source := data.get("source") as ItemSlot
	var incoming: Item = data.get("item")
	if source == null or incoming == null or source == self:
		return
	var my_prev := current_item()
	_assign(incoming)
	source._assign(my_prev)

func _assign(item: Item) -> void:
	if role == Role.EQUIPMENT:
		InventoryState.set_equipped(slot_id, item)
	else:
		InventoryState.set_inventory_item(inventory_index, item)
