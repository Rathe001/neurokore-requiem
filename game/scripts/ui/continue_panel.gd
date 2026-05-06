extends Control
class_name ContinuePanel

## Character list panel shown from the startup screen "Continue" button.
## Displays saved characters with avatar, name, class, level, and hardcore
## badge. Clicking a row loads the save and launches the game.

signal back_pressed
signal character_selected(save_id: String)

const ROW_SIZE := Vector2(360.0, 56.0)
const ROW_GAP := 6
const AVATAR_SIZE := 44.0
const TITLE_FONT_SIZE := 16
const DELETE_CONFIRM_DELAY := 1.5

var _vbox: VBoxContainer
var _rows_box: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func refresh() -> void:
	_clear_rows()
	var saves := SaveManager.list_saves()
	for save: Dictionary in saves:
		_add_character_row(save)
	if saves.is_empty():
		var empty := Label.new()
		empty.text = "No saved characters found."
		empty.add_theme_font_size_override(&"font_size", 12)
		empty.add_theme_color_override(&"font_color", Color(0.6, 0.6, 0.65, 0.8))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows_box.add_child(empty)


func _build_ui() -> void:
	var back := Button.new()
	back.text = "COMMON_BACK"
	back.custom_minimum_size = Vector2(120.0, 32.0)
	back.anchor_left = 0.0
	back.anchor_right = 0.0
	back.anchor_top = 0.0
	back.anchor_bottom = 0.0
	back.offset_left = 16.0
	back.offset_right = 136.0
	back.offset_top = 16.0
	back.offset_bottom = 48.0
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 64.0
	scroll.offset_bottom = -16.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override(&"separation", 12)
	center.add_child(_vbox)

	var title := Label.new()
	title.text = "Continue"
	title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override(&"font_color", Color(0.85, 0.92, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vbox.add_child(title)

	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override(&"separation", ROW_GAP)
	_rows_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_vbox.add_child(_rows_box)


func _clear_rows() -> void:
	for child in _rows_box.get_children():
		child.queue_free()


func _add_character_row(save: Dictionary) -> void:
	var save_id: String = save.get("save_id", "")
	var class_id: StringName = StringName(save.get("class_id", ""))
	var spec_id: StringName = StringName(save.get("spec_id", ""))
	var hardcore: bool = save.get("hardcore", false)

	var accent := UIThemeState.get_palette_for(class_id, spec_id).accent
	var bg_color := Color(accent.r * 0.08, accent.g * 0.08, accent.b * 0.08, 0.9)
	var hover_color := Color(accent.r * 0.16, accent.g * 0.16, accent.b * 0.16, 0.95)

	var row_btn := Button.new()
	row_btn.custom_minimum_size = ROW_SIZE
	row_btn.focus_mode = Control.FOCUS_NONE

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.border_color = Color(accent.r, accent.g, accent.b, 0.4)
	style_normal.set_border_width_all(1)
	style_normal.content_margin_left = 8
	style_normal.content_margin_right = 8
	style_normal.content_margin_top = 4
	style_normal.content_margin_bottom = 4

	var style_hover := style_normal.duplicate() as StyleBoxFlat
	style_hover.bg_color = hover_color
	style_hover.border_color = accent

	row_btn.add_theme_stylebox_override(&"normal", style_normal)
	row_btn.add_theme_stylebox_override(&"hover", style_hover)
	row_btn.add_theme_stylebox_override(&"pressed", style_hover)
	row_btn.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	row_btn.pressed.connect(func() -> void: character_selected.emit(save_id))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 10)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hbox.offset_left = 8.0
	hbox.offset_right = -8.0
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_btn.add_child(hbox)

	# Avatar
	var avatar_id: int = save.get("avatar_id", 0)
	var gender: String = save.get("gender", "male")
	var avatar_rect := _make_avatar(class_id, gender, avatar_id)
	hbox.add_child(avatar_rect)

	# Info column
	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(info)

	var name_label := Label.new()
	name_label.text = save.get("player_name", "Unknown")
	name_label.add_theme_font_size_override(&"font_size", 13)
	name_label.add_theme_color_override(&"font_color", Color(0.92, 0.94, 0.97))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(name_label)

	var detail_hbox := HBoxContainer.new()
	detail_hbox.add_theme_constant_override(&"separation", 8)
	detail_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(detail_hbox)

	var class_label := Label.new()
	var display_class := spec_id if spec_id != &"" else class_id
	class_label.text = SpecSelectOverlay.get_class_label(display_class) if display_class != &"" else "Unknown"
	class_label.add_theme_font_size_override(&"font_size", 10)
	class_label.add_theme_color_override(&"font_color", accent)
	class_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_hbox.add_child(class_label)

	var level_label := Label.new()
	level_label.text = "Lv. %d" % save.get("level", 1)
	level_label.add_theme_font_size_override(&"font_size", 10)
	level_label.add_theme_color_override(&"font_color", Color(0.65, 0.68, 0.72))
	level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_hbox.add_child(level_label)

	if hardcore:
		var hc_label := Label.new()
		hc_label.text = "HC"
		hc_label.add_theme_font_size_override(&"font_size", 10)
		hc_label.add_theme_color_override(&"font_color", Color(0.85, 0.25, 0.2))
		hc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail_hbox.add_child(hc_label)

	# Delete button
	var del_btn := Button.new()
	del_btn.text = "X"
	del_btn.custom_minimum_size = Vector2(28, 28)
	del_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	del_btn.add_theme_font_size_override(&"font_size", 10)
	del_btn.tooltip_text = "Delete character"
	var sid := save_id
	del_btn.pressed.connect(func() -> void: _on_delete_pressed(sid))
	hbox.add_child(del_btn)

	_rows_box.add_child(row_btn)


func _make_avatar(class_id: StringName, gender: String, avatar_id: int) -> Control:
	var container := ColorRect.new()
	container.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	container.color = Color(0.06, 0.07, 0.1, 0.8)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if avatar_id >= 1 and avatar_id <= 5:
		var path := "res://assets/ui/avatars/%s_%s%d.png" % [gender, class_id, avatar_id]
		var tex := load(path) as Texture2D
		if tex != null:
			var img := TextureRect.new()
			img.texture = tex
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			img.offset_left = 2.0
			img.offset_top = 2.0
			img.offset_right = -2.0
			img.offset_bottom = -2.0
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			container.add_child(img)
	return container


func _on_delete_pressed(save_id: String) -> void:
	SaveManager.delete_save(save_id)
	refresh()
