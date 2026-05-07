extends Control
class_name BrowseLobbiesPanel

## Lobby browser — refresh button + scrollable list of public lobbies.
## Emits `lobby_selected(lobby_id)` when a row is clicked; parent calls
## NetState.join_lobby and waits for the join result.

signal back_pressed
signal lobby_selected(target_lobby_id: int)

const TITLE_FONT_SIZE := 16
const ROW_SIZE := Vector2(420.0, 56.0)
const ROW_GAP := 6
const LIST_WIDTH := 460.0

var _list_box: VBoxContainer
var _empty_label: Label
var _refresh_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	NetState.lobby_match_list_updated.connect(_on_match_list)


func refresh() -> void:
	_clear_list()
	_empty_label.text = "MENU_MP_BROWSE_LOADING"
	_empty_label.visible = true
	_refresh_btn.disabled = true
	NetState.request_lobby_list()


func _build_ui() -> void:
	var back := Button.new()
	back.text = "COMMON_BACK"
	back.custom_minimum_size = Vector2(120.0, 32.0)
	back.position = Vector2(16.0, 16.0)
	back.size = Vector2(120.0, 32.0)
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)

	_refresh_btn = Button.new()
	_refresh_btn.text = "MENU_MP_REFRESH"
	_refresh_btn.custom_minimum_size = Vector2(120.0, 32.0)
	_refresh_btn.anchor_left = 1.0
	_refresh_btn.anchor_right = 1.0
	_refresh_btn.offset_left = -136.0
	_refresh_btn.offset_right = -16.0
	_refresh_btn.offset_top = 16.0
	_refresh_btn.offset_bottom = 48.0
	_refresh_btn.pressed.connect(refresh)
	add_child(_refresh_btn)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 64.0
	scroll.offset_bottom = -16.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "MENU_MP_BROWSE"
	title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override(&"font_color", Color(0.85, 0.92, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override(&"separation", ROW_GAP)
	_list_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_list_box)

	_empty_label = Label.new()
	_empty_label.text = ""
	_empty_label.add_theme_font_size_override(&"font_size", 12)
	_empty_label.add_theme_color_override(&"font_color", Color(0.6, 0.6, 0.65, 0.8))
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	vbox.add_child(_empty_label)


func _clear_list() -> void:
	for child in _list_box.get_children():
		child.queue_free()


func _on_match_list(lobbies: Array) -> void:
	_clear_list()
	_refresh_btn.disabled = false
	if lobbies.is_empty():
		_empty_label.text = "MENU_MP_BROWSE_EMPTY"
		_empty_label.visible = true
		return
	_empty_label.visible = false
	for info_variant in lobbies:
		var info: Dictionary = info_variant
		_add_row(info)


func _add_row(info: Dictionary) -> void:
	var lobby_id: int = int(info.get(&"lobby_id", 0))
	var lobby_name: String = String(info.get(&"name", ""))
	var host: String = String(info.get(&"host", "?"))
	var member_count: int = int(info.get(&"member_count", 0))
	var member_limit: int = int(info.get(&"member_limit", 0))

	var btn := Button.new()
	btn.custom_minimum_size = ROW_SIZE
	btn.toggle_mode = false
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Empty / unset name falls back to the host's name so the row is
	# never blank — Steam returns "" for lobby data that wasn't set.
	var display_name: String = lobby_name if not lobby_name.is_empty() else "%s's Game" % host
	btn.text = "%s   %s   %d/%d" % [display_name, host, member_count, member_limit]
	btn.pressed.connect(func() -> void: lobby_selected.emit(lobby_id))
	_list_box.add_child(btn)
