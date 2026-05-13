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
var _icon: TextureRect
var _is_drag_source: bool = false
var _bg: ColorRect
var _border_overlay: Control
var _border_color: Color = Color.TRANSPARENT
var _border_width: int = 0

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
	if _empty_label != null:
		_empty_label.add_theme_color_override(&"font_color", Color(p.text_dim.r, p.text_dim.g, p.text_dim.b, 0.85))
	_refresh()

func _on_mouse_entered() -> void:
	var item := current_item()
	if item != null:
		get_tree().call_group(&"interactable_tooltip", &"show_item", item)

func _on_mouse_exited() -> void:
	if is_inside_tree():
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")


## Public: re-evaluate the tooltip against the slot's current contents.
## Called by CharacterPanel after right-click equip/unequip so the tooltip
## swaps to the displaced item (or hides) without forcing the player to
## move the cursor out of the slot and back in to retrigger mouse_entered.
func refresh_tooltip() -> void:
	var item := current_item()
	if item != null:
		get_tree().call_group(&"interactable_tooltip", &"show_item", item)
	else:
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

	_icon = TextureRect.new()
	_icon.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = MOUSE_FILTER_IGNORE
	_icon.visible = false
	add_child(_icon)

	# Border overlay — last child so it draws ON TOP of icon/glyph.
	# Uses _draw() via draw signal to render the border outline directly.
	_border_overlay = Control.new()
	_border_overlay.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_border_overlay.mouse_filter = MOUSE_FILTER_IGNORE
	_border_overlay.draw.connect(_on_border_draw)
	add_child(_border_overlay)

func _on_border_draw() -> void:
	if _border_width <= 0 or _border_color.a <= 0.0:
		return
	var s := _border_overlay.size
	var w := float(_border_width)
	# Draw four filled rects forming the border frame so it's crisp at any size.
	_border_overlay.draw_rect(Rect2(0, 0, s.x, w), _border_color)              # top
	_border_overlay.draw_rect(Rect2(0, s.y - w, s.x, w), _border_color)        # bottom
	_border_overlay.draw_rect(Rect2(0, w, w, s.y - 2 * w), _border_color)      # left
	_border_overlay.draw_rect(Rect2(s.x - w, w, w, s.y - 2 * w), _border_color) # right

func _set_border(color: Color, w: int) -> void:
	_border_color = color
	_border_width = w
	if _border_overlay != null:
		_border_overlay.queue_redraw()

func set_highlight(color: Color) -> void:
	var w: int = 2 if color != UIThemeState.palette.slot_border else 1
	_set_border(color, w)

func clear_highlight() -> void:
	_refresh_border()

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
	# Icon takes precedence when the item has one and the file loads;
	# fall back to the unicode glyph label otherwise. Rarity color
	# tints both paths so the quality signal survives the swap.
	var icon_tex: Texture2D = null
	if has_item and item.icon_path != "":
		icon_tex = load(item.icon_path) as Texture2D
	if icon_tex != null:
		_icon.texture = icon_tex
		_icon.modulate = item.glyph_color
		_icon.visible = true
		_glyph.visible = false
	else:
		_icon.visible = false
		_glyph.visible = has_item
		if has_item:
			_glyph.text = item.glyph
			_glyph.modulate = item.glyph_color
	_refresh_border()

func _refresh_border() -> void:
	var item := current_item()
	if item != null and item.rarity != &"common":
		_set_border(item.glyph_color, 2)
		_bg.color = Color(item.glyph_color, 0.15)
	else:
		_set_border(UIThemeState.palette.slot_border, 1)
		_bg.color = UIThemeState.palette.slot_bg

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
	# Drag preview prefers the icon when the item has one; falls back
	# to the glyph label otherwise. Same precedence as the in-slot
	# display so the cursor matches the source visually mid-drag.
	var preview: Control = null
	if item.icon_path != "":
		var icon_tex := load(item.icon_path) as Texture2D
		if icon_tex != null:
			var icon_preview := TextureRect.new()
			icon_preview.texture = icon_tex
			# EXPAND_IGNORE_SIZE so the texture's intrinsic dimensions
			# can't inflate the rect — STRETCH_KEEP_ASPECT_CENTERED fits
			# the icon into the explicit size while preserving aspect.
			icon_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_preview.modulate = item.glyph_color
			icon_preview.custom_minimum_size = Vector2(32, 32)
			preview = icon_preview
	if preview == null:
		var label := Label.new()
		label.text = item.glyph
		label.theme_type_variation = &"DragPreview"
		label.modulate = item.glyph_color
		label.custom_minimum_size = Vector2(32, 32)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview = label
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
	# Pre-unequip offhand before equipping a 2H — set_equipped's internal
	# add_to_inventory could place the offhand in source's slot, which
	# source._assign then overwrites, silently losing the offhand.
	if role == Role.EQUIPMENT and slot_id == &"weapon" \
			and incoming != null and incoming.two_handed:
		var oh: Item = InventoryState.get_equipped(&"offhand")
		if oh != null:
			InventoryState.set_equipped(&"offhand", null)
			if not InventoryState.add_to_inventory(oh):
				get_tree().call_group(&"world_item_dropper", &"drop_item", oh)
	_assign(incoming)
	source._assign(my_prev)

func _assign(item: Item) -> void:
	if role == Role.EQUIPMENT:
		InventoryState.set_equipped(slot_id, item)
	else:
		InventoryState.set_inventory_item(inventory_index, item)
