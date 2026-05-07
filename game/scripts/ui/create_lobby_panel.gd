extends Control
class_name CreateLobbyPanel

## Form for creating a Steam lobby — name + party size + privacy. Submit
## emits `submit_pressed(name, size, lobby_type)`; the parent (startup
## screen) calls `NetState.create_lobby` and listens for the result.

signal back_pressed
signal submit_pressed(lobby_name: String, max_members: int, lobby_type: int)

const TITLE_FONT_SIZE := 16
const FIELD_WIDTH := 280.0
const ROW_LABEL_WIDTH := 100.0

var _name_field: LineEdit
var _size_option: OptionButton
var _privacy_option: OptionButton


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


# Optional default name passed from the parent — populated with
# "<persona>'s Game" when the panel is shown.
func set_default_name(default_name: String) -> void:
	if _name_field != null:
		_name_field.text = default_name


func _build_ui() -> void:
	var back := Button.new()
	back.text = "COMMON_BACK"
	back.custom_minimum_size = Vector2(120.0, 32.0)
	back.position = Vector2(16.0, 16.0)
	back.size = Vector2(120.0, 32.0)
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "MENU_MP_CREATE"
	title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override(&"font_color", Color(0.85, 0.92, 1.0, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Lobby name"
	_name_field.custom_minimum_size = Vector2(FIELD_WIDTH, 32.0)
	vbox.add_child(_make_row("MENU_MP_LOBBY_NAME", _name_field))

	_size_option = OptionButton.new()
	# Cap at 4 — see docs/multiplayer.md for the perf rationale.
	_size_option.add_item("2", 2)
	_size_option.add_item("3", 3)
	_size_option.add_item("4", 4)
	_size_option.selected = 2  # default to 4 players (index 2)
	_size_option.custom_minimum_size = Vector2(FIELD_WIDTH, 32.0)
	vbox.add_child(_make_row("MENU_MP_PARTY_SIZE", _size_option))

	_privacy_option = OptionButton.new()
	_privacy_option.add_item("MENU_MP_PRIVACY_PUBLIC", NetState.LobbyType.PUBLIC)
	_privacy_option.add_item("MENU_MP_PRIVACY_FRIENDS", NetState.LobbyType.FRIENDS)
	_privacy_option.add_item("MENU_MP_PRIVACY_PRIVATE", NetState.LobbyType.PRIVATE)
	_privacy_option.selected = 0  # PUBLIC by default
	_privacy_option.custom_minimum_size = Vector2(FIELD_WIDTH, 32.0)
	vbox.add_child(_make_row("MENU_MP_PRIVACY", _privacy_option))

	var submit := Button.new()
	submit.text = "MENU_MP_CREATE_SUBMIT"
	submit.custom_minimum_size = Vector2(FIELD_WIDTH, 40.0)
	submit.pressed.connect(_on_submit_pressed)
	vbox.add_child(submit)


func _make_row(label_key: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.text = label_key
	label.custom_minimum_size = Vector2(ROW_LABEL_WIDTH, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	row.add_child(control)
	return row


func _on_submit_pressed() -> void:
	var lobby_name: String = _name_field.text.strip_edges()
	if lobby_name.is_empty():
		# Fall back to the placeholder if the user left the name blank.
		lobby_name = "%s's Game" % SteamState.persona_name
	var size: int = int(_size_option.get_item_id(_size_option.selected))
	var lobby_type: int = int(_privacy_option.get_item_id(_privacy_option.selected))
	submit_pressed.emit(lobby_name, size, lobby_type)
