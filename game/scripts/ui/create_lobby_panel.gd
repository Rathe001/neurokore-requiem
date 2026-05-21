extends Control
class_name CreateLobbyPanel

## Form for creating a Steam lobby — name + party size + privacy. Submit
## emits `submit_pressed(name, size, lobby_type)`; the parent (startup
## screen) calls `NetState.create_lobby` and listens for the result.

signal back_pressed
signal submit_pressed(lobby_name: String, max_members: int, lobby_type: int, password: String)

const TITLE_FONT_SIZE := 16
const FIELD_WIDTH := 280.0
const ROW_LABEL_WIDTH := 100.0

var _name_field: LineEdit
var _size_option: OptionButton
var _privacy_option: OptionButton
var _password_field: LineEdit
var _password_row: HBoxContainer
# Hardcoded-accent elements re-tinted on every show via apply_theme().
# Same rationale as GlobalChatPanel — the panel is built once at
# startup, before PlayerState has a class, so the initial palette is
# the neutral default. Caller (StartupScreen._show_create_lobby) re-
# applies via apply_theme() each time the panel becomes visible.
var _title_label: Label


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
	# CenterContainer covers the full rect and would otherwise eat clicks
	# meant for the back button below it (sibling z-order: back was added
	# first, so this container draws on top). Pass clicks through.
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override(&"separation", 12)
	center.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "MENU_MP_CREATE"
	_title_label.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Game name"
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
	_privacy_option.item_selected.connect(_on_privacy_changed)
	vbox.add_child(_make_row("MENU_MP_PRIVACY", _privacy_option))

	# Password field — only meaningful when Private is selected, hidden
	# otherwise. Steam doesn't gate lobby joins by password natively, so
	# the password is stamped onto lobby metadata and the join side
	# validates client-side. Plain-text in lobby metadata is fine for
	# casual coop gating; not for anything sensitive.
	_password_field = LineEdit.new()
	_password_field.placeholder_text = "Password"
	_password_field.secret = true
	_password_field.custom_minimum_size = Vector2(FIELD_WIDTH, 32.0)
	_password_row = _make_row("MENU_MP_PASSWORD", _password_field)
	_password_row.visible = false
	vbox.add_child(_password_row)

	var submit := Button.new()
	submit.text = "MENU_MP_CREATE_SUBMIT"
	submit.custom_minimum_size = Vector2(FIELD_WIDTH, 40.0)
	submit.pressed.connect(_on_submit_pressed)
	vbox.add_child(submit)


func _on_privacy_changed(_index: int) -> void:
	var lobby_type: int = int(_privacy_option.get_item_id(_privacy_option.selected))
	_password_row.visible = lobby_type == NetState.LobbyType.PRIVATE


# Public — called by StartupScreen every time the panel becomes
# visible so we re-tint against the live class palette. Build-time
# tinting was wrong because the panel is constructed before any
# character is loaded into PlayerState.
func apply_theme() -> void:
	var accent := _player_accent()
	if _title_label != null:
		_title_label.add_theme_color_override(&"font_color", accent)
	if _name_field != null:
		_apply_field_theme(_name_field, accent)
	if _password_field != null:
		_apply_field_theme(_password_field, accent)


# Pull the local player's class accent out of UIThemeState. Used to tint
# input field borders so the Create Game form reads as the player's
# class instead of a neutral form.
func _player_accent() -> Color:
	var p := UIThemeState.palette
	if p == null:
		p = UIThemeState.get_palette_for(PlayerState.class_id, PlayerState.spec_id)
	if p == null:
		return Color(0.5, 0.7, 1.0)
	return p.accent


# Stylebox the LineEdit borders to the class accent. Only the normal /
# focus styles need overriding — the global UIThemeState theme already
# colors the text + caret. Focus state gets a brighter rim so the
# active field reads at a glance.
func _apply_field_theme(field: LineEdit, accent: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.06, 0.07, 0.10, 0.85)
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	normal.set_border_width_all(1)
	normal.content_margin_left = 8
	normal.content_margin_right = 8
	normal.content_margin_top = 4
	normal.content_margin_bottom = 4
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = Color(accent.r, accent.g, accent.b, 0.95)
	field.add_theme_stylebox_override(&"normal", normal)
	field.add_theme_stylebox_override(&"focus", focus)


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
	var lobby_size: int = int(_size_option.get_item_id(_size_option.selected))
	var lobby_type: int = int(_privacy_option.get_item_id(_privacy_option.selected))
	# Password only carries through when the lobby type is Private — for
	# Public / Friends we ignore whatever's in the field so a stale
	# value doesn't accidentally lock the lobby.
	var password: String = ""
	if lobby_type == NetState.LobbyType.PRIVATE:
		password = _password_field.text
	submit_pressed.emit(lobby_name, lobby_size, lobby_type, password)
