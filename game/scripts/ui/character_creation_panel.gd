extends Control
class_name CharacterCreationPanel
## Single-screen character creation with progressive disclosure. Four
## sections stack vertically; each appears once the previous is selected:
##   1. Class    (Analog / Cyborg — generalist origin; specs chosen later
##                in-game via SpecSelectOverlay after NG+1)
##   2. Gender   (Male / Female)
##   3. Avatar   (5 portraits filtered by class + gender)
##   4. Name     (LineEdit + Start button)
##
## Selecting an earlier section keeps the new selection but invalidates
## downstream sections that depend on it (avatar list rebuilds on
## class/gender change). The Start button stays disabled until every
## section has a value and the name is non-empty.

signal back_pressed
signal start_pressed

const SECTION_GAP := 12
const TITLE_BOTTOM_GAP := 4
const CARD_GAP := 8
const TITLE_FONT_SIZE := 16

const CLASS_CARD_SIZE := Vector2(180.0, 56.0)
const GENDER_CARD_SIZE := Vector2(140.0, 44.0)
const AVATAR_CARD_SIZE := Vector2(72.0, 72.0)

const ACCENT_MALE := Color(0.4, 0.6, 0.9, 1.0)
const ACCENT_FEMALE := Color(0.9, 0.45, 0.65, 1.0)

var _selected_class_id: StringName = &""
var _selected_gender: StringName = &""
var _selected_avatar_id: int = 0
var _name_value: String = ""

# State the avatar section was last built against — lets us skip rebuilds
# when downstream state changes.
var _avatar_built_class: StringName = &""
var _avatar_built_gender: StringName = &""

var _vbox: VBoxContainer
var _class_section: Control
var _gender_section: Control
var _avatar_section: Control
var _name_section: Control
var _class_cards_box: HBoxContainer
var _gender_cards_box: HBoxContainer
var _avatar_cards_box: HBoxContainer
var _name_input: LineEdit
var _start_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_build_class_cards()
	_build_gender_cards()
	_refresh()


# Public reset for re-entry from the main menu — wipes the form so a
# returning user starts fresh.
func reset_state() -> void:
	_selected_class_id = &""
	_selected_gender = &""
	_selected_avatar_id = 0
	_name_value = ""
	if _name_input != null:
		_name_input.text = ""
	_refresh()


# ── Layout ───────────────────────────────────────────────────────────────

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
	_vbox.add_theme_constant_override(&"separation", SECTION_GAP)
	center.add_child(_vbox)

	_class_section = _make_section(&"STARTUP_TITLE")
	_class_cards_box = _section_cards_box(_class_section)
	_vbox.add_child(_class_section)

	_gender_section = _make_section(&"STARTUP_TITLE_GENDER")
	_gender_cards_box = _section_cards_box(_gender_section)
	_vbox.add_child(_gender_section)

	_avatar_section = _make_section(&"STARTUP_TITLE_AVATAR")
	_avatar_cards_box = _section_cards_box(_avatar_section)
	_vbox.add_child(_avatar_section)

	_name_section = _make_name_section()
	_vbox.add_child(_name_section)


func _make_section(title_key: StringName) -> Control:
	var section := VBoxContainer.new()
	section.add_theme_constant_override(&"separation", TITLE_BOTTOM_GAP)
	section.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var title := Label.new()
	title.text = title_key
	title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override(&"font_color", Color(0.85, 0.92, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section.add_child(title)
	return section


func _section_cards_box(section: Control) -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", CARD_GAP)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	section.add_child(hbox)
	return hbox


func _make_name_section() -> Control:
	var section := _make_section(&"STARTUP_TITLE_NAME")
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", CARD_GAP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	section.add_child(row)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "STARTUP_PLACEHOLDER_NAME"
	_name_input.custom_minimum_size = Vector2(220.0, 28.0)
	_name_input.max_length = 24
	_name_input.text_changed.connect(_on_name_text_changed)
	_name_input.text_submitted.connect(_on_name_submitted)
	row.add_child(_name_input)

	_start_button = Button.new()
	_start_button.text = "COMMON_START"
	_start_button.custom_minimum_size = Vector2(96.0, 28.0)
	_start_button.disabled = true
	_start_button.pressed.connect(_on_start_pressed)
	row.add_child(_start_button)
	return section


# ── Card builders ────────────────────────────────────────────────────────

func _build_class_cards() -> void:
	# Origin generalist picks only — specialised classes are picked later
	# in-game via SpecSelectOverlay after the player completes a level.
	# Compact pick cards here; SpecSelectOverlay uses the rich
	# ClassCardBuilder layout for the spec choice in-game.
	for class_id: StringName in AttributeState.ORIGIN_DEFINITIONS:
		var accent := UIThemeState.get_palette_for(class_id, &"").accent
		var label := SpecSelectOverlay.get_class_label(class_id)
		var card := _make_pick_card(label, "", accent, CLASS_CARD_SIZE)
		var cid := class_id  # capture by value
		card.pressed.connect(func() -> void: _on_class_selected(cid))
		card.set_meta(&"id", cid)
		_class_cards_box.add_child(card)


func _build_gender_cards() -> void:
	var male := _make_pick_card("STARTUP_GENDER_MALE", "STARTUP_GENDER_DESC_MALE", ACCENT_MALE, GENDER_CARD_SIZE)
	male.pressed.connect(func() -> void: _on_gender_selected(&"male"))
	male.set_meta(&"id", &"male")
	_gender_cards_box.add_child(male)

	var female := _make_pick_card("STARTUP_GENDER_FEMALE", "STARTUP_GENDER_DESC_FEMALE", ACCENT_FEMALE, GENDER_CARD_SIZE)
	female.pressed.connect(func() -> void: _on_gender_selected(&"female"))
	female.set_meta(&"id", &"female")
	_gender_cards_box.add_child(female)


func _rebuild_avatar_section() -> void:
	for child in _avatar_cards_box.get_children():
		child.queue_free()
	for i in range(1, 6):
		var path := "res://assets/ui/avatars/%s_%s%d.png" % [_selected_gender, _selected_class_id, i]
		var tex := load(path) as Texture2D
		var btn := _make_avatar_card(tex)
		var idx := i
		btn.pressed.connect(func() -> void: _on_avatar_selected(idx))
		btn.set_meta(&"id", idx)
		_avatar_cards_box.add_child(btn)
	_avatar_built_class = _selected_class_id
	_avatar_built_gender = _selected_gender


# ── Selection callbacks ─────────────────────────────────────────────────

func _on_class_selected(class_id: StringName) -> void:
	if _selected_class_id == class_id:
		return
	_selected_class_id = class_id
	# Class governs the avatar pool — reset avatar selection.
	_selected_avatar_id = 0
	_refresh()


func _on_gender_selected(gender: StringName) -> void:
	if _selected_gender == gender:
		return
	_selected_gender = gender
	# Gender also governs the avatar pool.
	_selected_avatar_id = 0
	_refresh()


func _on_avatar_selected(avatar_id: int) -> void:
	_selected_avatar_id = avatar_id
	_refresh()


func _on_name_text_changed(new_text: String) -> void:
	_name_value = new_text
	_update_start_enabled()


func _on_name_submitted(_text: String) -> void:
	if not _start_button.disabled:
		_on_start_pressed()


func _on_start_pressed() -> void:
	PlayerState.gender = _selected_gender
	# Spec stays empty here — picked later in-game via SpecSelectOverlay.
	PlayerState.set_class_and_spec(_selected_class_id, &"")
	PlayerState.avatar_id = _selected_avatar_id
	PlayerState.player_name = _name_value.strip_edges()
	start_pressed.emit()


# ── Refresh ──────────────────────────────────────────────────────────────

func _refresh() -> void:
	_gender_section.visible = _selected_class_id != &""
	_avatar_section.visible = _selected_gender != &""
	_name_section.visible = _selected_avatar_id > 0

	if _avatar_section.visible and (_avatar_built_class != _selected_class_id or _avatar_built_gender != _selected_gender):
		_rebuild_avatar_section()

	_apply_card_selection(_class_cards_box, _selected_class_id)
	_apply_card_selection(_gender_cards_box, _selected_gender)
	if _avatar_section.visible:
		_apply_card_selection(_avatar_cards_box, _selected_avatar_id)
	_update_start_enabled()


func _update_start_enabled() -> void:
	if _start_button == null:
		return
	var is_ready := _selected_avatar_id > 0 and not _name_value.strip_edges().is_empty()
	_start_button.disabled = not is_ready


# ── Helpers ──────────────────────────────────────────────────────────────

func _class_entry_for_origin(origin: StringName) -> Dictionary:
	var stat_key: String
	var opposes_key: String
	if origin == &"analog":
		stat_key = "STAT_SOUL"
		opposes_key = "STAT_INTERFACE"
	else:
		stat_key = "STAT_INTERFACE"
		opposes_key = "STAT_SOUL"
	return {
		"class_id": origin,
		"spec_id": &"",
		"label_key": SpecSelectOverlay.get_class_label(origin),
		"glyph": SpecSelectOverlay.get_class_glyph(origin),
		"stat": stat_key,
		"opposes": opposes_key,
		"backstory": SpecSelectOverlay.get_class_backstory(origin),
	}


# Highlight whichever button has set_meta(&"id") matching `selected_id`. Any
# unmatched buttons revert to a dimmed modulate.
static func _apply_card_selection(box: Container, selected_id) -> void:
	for child in box.get_children():
		if not child.has_meta(&"id"):
			continue
		var is_selected: bool = child.get_meta(&"id") == selected_id
		child.modulate = Color(1.0, 1.0, 1.0, 1.0) if is_selected else Color(0.55, 0.55, 0.6, 1.0)


func _make_pick_card(label_key: String, desc_key: String, accent: Color, card_size: Vector2) -> Button:
	var card := Button.new()
	card.custom_minimum_size = card_size
	card.focus_mode = Control.FOCUS_NONE

	var bg_color := Color(accent.r * 0.12, accent.g * 0.12, accent.b * 0.12, 0.92)
	var bg_hover := Color(accent.r * 0.22, accent.g * 0.22, accent.b * 0.22, 0.96)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = bg_color
	style_normal.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style_normal.set_border_width_all(1)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = bg_hover
	style_hover.border_color = accent
	style_hover.set_border_width_all(2)

	card.add_theme_stylebox_override(&"normal", style_normal)
	card.add_theme_stylebox_override(&"hover", style_hover)
	card.add_theme_stylebox_override(&"pressed", style_hover)
	card.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 2)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vbox)

	var name_label := Label.new()
	name_label.text = label_key
	name_label.theme_type_variation = &"CardTitle"
	name_label.add_theme_color_override(&"font_color", accent)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_label)

	if desc_key != "":
		var desc_label := Label.new()
		desc_label.text = desc_key
		desc_label.add_theme_font_size_override(&"font_size", 9)
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.add_theme_color_override(&"font_color", Color(1.0, 1.0, 1.0, 0.5))
		desc_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(desc_label)

	return card


func _make_avatar_card(tex: Texture2D) -> Button:
	var card := Button.new()
	card.custom_minimum_size = AVATAR_CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.04, 0.05, 0.08, 0.85)
	style_normal.border_color = Color(0.4, 0.55, 0.7, 0.6)
	style_normal.set_border_width_all(1)

	var style_hover := StyleBoxFlat.new()
	style_hover.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	style_hover.border_color = Color(0.6, 0.8, 1.0, 0.95)
	style_hover.set_border_width_all(2)

	card.add_theme_stylebox_override(&"normal", style_normal)
	card.add_theme_stylebox_override(&"hover", style_hover)
	card.add_theme_stylebox_override(&"pressed", style_hover)
	card.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())

	if tex != null:
		var img := TextureRect.new()
		img.texture = tex
		img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		img.offset_left = 4.0
		img.offset_top = 4.0
		img.offset_right = -4.0
		img.offset_bottom = -4.0
		img.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(img)
	return card
