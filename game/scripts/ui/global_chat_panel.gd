extends Control
class_name GlobalChatPanel

## Landing panel for the MP flow. Shows the persistent global chat lobby
## (chat history + scrolling members list) plus the action buttons that
## actually launch a coop session (Create Lobby / Browse Lobbies). The
## global chat lobby is owned by GlobalChatState and stays joined across
## panel transitions — leaving this panel for the lobby browser doesn't
## drop the chat.

signal back_pressed
signal create_lobby_pressed
signal browse_lobbies_pressed

const TITLE_FONT_SIZE := 16
const SECTION_FONT_SIZE := 12
const ROW_FONT_SIZE := 11
const MEMBER_ROW_HEIGHT := 44.0
const AVATAR_SIZE := 36.0
const HISTORY_MAX_LINES := 200
const MEMBER_PANEL_WIDTH := 260.0

var _chat_history: RichTextLabel
var _chat_input: LineEdit
var _members_box: VBoxContainer
var _status_label: Label
var _create_btn: Button
var _browse_btn: Button
# References to nodes / styles that get re-tinted whenever the panel
# is shown — the panel is built ONCE at startup (before any character
# is loaded into PlayerState), so the initial theme is the default
# blue palette. refresh() re-applies the live class accent each time
# the panel becomes visible, which is post-character-select.
var _title_label: Label
var _members_title_label: Label
var _history_panel: PanelContainer
var _history_style: StyleBoxFlat


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	_connect_signals()


func _exit_tree() -> void:
	if GlobalChatState.chat_received.is_connected(_on_chat_received):
		GlobalChatState.chat_received.disconnect(_on_chat_received)
	if GlobalChatState.members_changed.is_connected(_on_members_changed):
		GlobalChatState.members_changed.disconnect(_on_members_changed)
	if GlobalChatState.joined.is_connected(_on_joined):
		GlobalChatState.joined.disconnect(_on_joined)
	if GlobalChatState.left.is_connected(_on_left):
		GlobalChatState.left.disconnect(_on_left)


func _connect_signals() -> void:
	GlobalChatState.chat_received.connect(_on_chat_received)
	GlobalChatState.members_changed.connect(_on_members_changed)
	GlobalChatState.joined.connect(_on_joined)
	GlobalChatState.left.connect(_on_left)


## Class accent for the local player's character — drives panel borders
## and section-title colors so global chat reads as "yours" rather than
## a neutral overlay. Read at build time; if the player swaps class
## mid-session a re-show recolors via refresh().
func _player_accent() -> Color:
	var p := UIThemeState.palette
	if p == null:
		p = UIThemeState.get_palette_for(PlayerState.class_id, PlayerState.spec_id)
	if p == null:
		return Color(0.5, 0.7, 1.0)
	return p.accent


func _build_ui() -> void:
	# Back button (top-left).
	var back := Button.new()
	back.text = "COMMON_BACK"
	back.custom_minimum_size = Vector2(120.0, 32.0)
	back.position = Vector2(16.0, 16.0)
	back.size = Vector2(120.0, 32.0)
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)

	# Title — recolored on every refresh() since the panel is built once
	# at startup before PlayerState has a class.
	_title_label = Label.new()
	_title_label.text = "MENU_GLOBAL_CHAT"
	_title_label.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.anchor_left = 0.0
	_title_label.anchor_right = 1.0
	_title_label.offset_top = 20.0
	_title_label.offset_bottom = 44.0
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title_label)

	# Action buttons (top-right).
	_create_btn = Button.new()
	_create_btn.text = "MENU_MP_CREATE"
	_create_btn.custom_minimum_size = Vector2(160.0, 32.0)
	_create_btn.anchor_left = 1.0
	_create_btn.anchor_right = 1.0
	_create_btn.offset_left = -344.0
	_create_btn.offset_right = -184.0
	_create_btn.offset_top = 16.0
	_create_btn.offset_bottom = 48.0
	_create_btn.pressed.connect(func() -> void: create_lobby_pressed.emit())
	add_child(_create_btn)

	_browse_btn = Button.new()
	_browse_btn.text = "MENU_MP_BROWSE"
	_browse_btn.custom_minimum_size = Vector2(160.0, 32.0)
	_browse_btn.anchor_left = 1.0
	_browse_btn.anchor_right = 1.0
	_browse_btn.offset_left = -176.0
	_browse_btn.offset_right = -16.0
	_browse_btn.offset_top = 16.0
	_browse_btn.offset_bottom = 48.0
	_browse_btn.pressed.connect(func() -> void: browse_lobbies_pressed.emit())
	add_child(_browse_btn)

	# Status line below the title — tells the user whether they're in
	# global chat yet, member count, etc.
	_status_label = Label.new()
	_status_label.text = ""
	_status_label.add_theme_font_size_override(&"font_size", SECTION_FONT_SIZE)
	_status_label.add_theme_color_override(&"font_color", Color(0.6, 0.65, 0.72, 0.9))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.anchor_left = 0.0
	_status_label.anchor_right = 1.0
	_status_label.offset_top = 50.0
	_status_label.offset_bottom = 70.0
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_label)

	# Main split: left = chat history + input; right = member list.
	var main_split := HBoxContainer.new()
	main_split.add_theme_constant_override(&"separation", 12)
	main_split.anchor_left = 0.0
	main_split.anchor_right = 1.0
	main_split.anchor_top = 0.0
	main_split.anchor_bottom = 1.0
	main_split.offset_left = 16.0
	main_split.offset_right = -16.0
	main_split.offset_top = 80.0
	main_split.offset_bottom = -16.0
	add_child(main_split)

	# Chat column.
	var chat_col := VBoxContainer.new()
	chat_col.add_theme_constant_override(&"separation", 6)
	chat_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_split.add_child(chat_col)

	# Wrap chat history in a dark panel so the bright text reads cleanly
	# over the cyberpunk-grunge background. Border color is restamped on
	# refresh() to match the live class accent.
	_history_panel = PanelContainer.new()
	_history_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_style = StyleBoxFlat.new()
	_history_style.bg_color = Color(0.05, 0.06, 0.09, 0.85)
	_history_style.set_border_width_all(1)
	_history_style.content_margin_left = 8
	_history_style.content_margin_right = 8
	_history_style.content_margin_top = 6
	_history_style.content_margin_bottom = 6
	_history_panel.add_theme_stylebox_override(&"panel", _history_style)
	chat_col.add_child(_history_panel)

	_chat_history = RichTextLabel.new()
	_chat_history.bbcode_enabled = true
	_chat_history.scroll_following = true
	_chat_history.fit_content = false
	_chat_history.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_history.add_theme_font_size_override(&"normal_font_size", ROW_FONT_SIZE)
	_chat_history.add_theme_color_override(&"default_color", Color(0.92, 0.94, 0.97))
	_history_panel.add_child(_chat_history)

	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "MENU_GLOBAL_CHAT_PLACEHOLDER"
	_chat_input.custom_minimum_size = Vector2(0.0, 32.0)
	_chat_input.text_submitted.connect(_on_chat_submitted)
	chat_col.add_child(_chat_input)

	# Members column — fixed-width panel on the right.
	var members_col := VBoxContainer.new()
	members_col.add_theme_constant_override(&"separation", 4)
	members_col.custom_minimum_size = Vector2(MEMBER_PANEL_WIDTH, 0.0)
	main_split.add_child(members_col)

	_members_title_label = Label.new()
	_members_title_label.text = "MENU_GLOBAL_CHAT_MEMBERS"
	_members_title_label.add_theme_font_size_override(&"font_size", SECTION_FONT_SIZE)
	members_col.add_child(_members_title_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	members_col.add_child(scroll)

	_members_box = VBoxContainer.new()
	_members_box.add_theme_constant_override(&"separation", 4)
	_members_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_members_box)


# Public re-entry — startup screen calls this every time the panel
# becomes visible so we re-render against latest state (member data
# may have changed while the panel was hidden).
func refresh() -> void:
	# Always editable — the user can compose pre-join, and send_chat
	# silently drops if we're not in the lobby yet. Locking the input
	# during the connect window felt like a freeze.
	_chat_input.editable = true
	_apply_class_accent()
	_refresh_status()
	_refresh_members()


# Re-tint anything we styled with a hardcoded class accent at build
# time. This panel is constructed ONCE in StartupScreen._ready, before
# the player has selected a character — so the initial palette is the
# default blue. Every show after character-select re-pulls the live
# accent here.
func _apply_class_accent() -> void:
	var accent := _player_accent()
	if _title_label != null:
		_title_label.add_theme_color_override(&"font_color", accent)
	if _members_title_label != null:
		_members_title_label.add_theme_color_override(&"font_color", accent)
	if _history_style != null:
		_history_style.border_color = Color(accent.r, accent.g, accent.b, 0.45)
	if _chat_input != null:
		_apply_field_theme(_chat_input, accent)


func _refresh_status() -> void:
	if not GlobalChatState.is_in_global_chat():
		_status_label.text = "MENU_GLOBAL_CHAT_CONNECTING"
		return
	_status_label.text = "%d / %d" % [
		GlobalChatState.members.size(),
		GlobalChatState.MAX_GLOBAL_MEMBERS,
	]


func _refresh_members() -> void:
	for child in _members_box.get_children():
		child.queue_free()
	# Sort members by level desc, then by name — keeps the highest-level
	# players visible at the top of the list without a hard rule.
	var entries: Array = []
	for steam_id in GlobalChatState.members.keys():
		var data: Dictionary = GlobalChatState.members[steam_id]
		entries.append({"steam_id": steam_id, "data": data})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var la := int(a["data"].get("level", 1))
		var lb := int(b["data"].get("level", 1))
		if la != lb:
			return la > lb
		return String(a["data"].get("name", "")) < String(b["data"].get("name", ""))
	)
	for entry: Dictionary in entries:
		_add_member_row(int(entry["steam_id"]), entry["data"])


func _add_member_row(steam_id: int, data: Dictionary) -> void:
	# Defensive override for self — even if GlobalChatState's
	# _read_member_data returned empty fields (Steam local-read race
	# right after lobby create), PlayerState always has the right
	# values for the local player, so trust it directly here.
	if steam_id == SteamState.steam_id:
		data = data.duplicate()
		var live_name: String = PlayerState.player_name
		if live_name.is_empty():
			live_name = SteamState.persona_name
		if live_name.is_empty():
			live_name = "?"
		data["name"] = live_name
		data["level"] = PlayerState.level
		data["class_id"] = PlayerState.class_id
		data["spec_id"] = PlayerState.spec_id
		data["avatar_id"] = PlayerState.avatar_id
		data["gender"] = String(PlayerState.gender)
		data["hardcore"] = PlayerState.hardcore
	var class_id: StringName = data.get("class_id", &"")
	var spec_id: StringName = data.get("spec_id", &"")

	var palette := UIThemeState.get_palette_for(class_id, spec_id)
	var accent: Color = palette.accent if palette != null else Color(0.5, 0.7, 1.0)

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0.0, MEMBER_ROW_HEIGHT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(accent.r * 0.08, accent.g * 0.08, accent.b * 0.08, 0.85)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.4)
	style.set_border_width_all(1)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	row.add_theme_stylebox_override(&"panel", style)
	_members_box.add_child(row)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 8)
	row.add_child(hbox)

	hbox.add_child(_make_avatar(class_id, String(data.get("gender", "male")), int(data.get("avatar_id", 0))))

	var info := VBoxContainer.new()
	info.add_theme_constant_override(&"separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info)

	var name_label := Label.new()
	var member_name: String = String(data.get("name", "?"))
	if member_name.is_empty():
		member_name = "?"
	name_label.text = member_name
	name_label.add_theme_font_size_override(&"font_size", ROW_FONT_SIZE + 1)
	name_label.add_theme_color_override(&"font_color", Color(0.92, 0.94, 0.97))
	info.add_child(name_label)

	var detail := HBoxContainer.new()
	detail.add_theme_constant_override(&"separation", 6)
	info.add_child(detail)

	var class_label := Label.new()
	var display_id := spec_id if spec_id != &"" else class_id
	if display_id != &"":
		class_label.text = SpecSelectOverlay.get_class_label(display_id)
	else:
		class_label.text = ""
	class_label.add_theme_font_size_override(&"font_size", ROW_FONT_SIZE - 1)
	class_label.add_theme_color_override(&"font_color", accent)
	detail.add_child(class_label)

	var level_label := Label.new()
	level_label.text = "Lv. %d" % int(data.get("level", 1))
	level_label.add_theme_font_size_override(&"font_size", ROW_FONT_SIZE - 1)
	level_label.add_theme_color_override(&"font_color", Color(0.65, 0.68, 0.72))
	detail.add_child(level_label)

	if bool(data.get("hardcore", false)):
		var hc := Label.new()
		hc.text = "HC"
		hc.add_theme_font_size_override(&"font_size", ROW_FONT_SIZE - 1)
		hc.add_theme_color_override(&"font_color", Color(0.85, 0.25, 0.2))
		detail.add_child(hc)


func _make_avatar(class_id: StringName, gender: String, avatar_id: int) -> Control:
	var container := ColorRect.new()
	container.custom_minimum_size = Vector2(AVATAR_SIZE, AVATAR_SIZE)
	container.color = Color(0.06, 0.07, 0.1, 0.8)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if avatar_id < 1 or avatar_id > 5 or class_id == &"":
		return container
	var path := "res://assets/ui/avatars/%s_%s%d.png" % [gender, class_id, avatar_id]
	if not ResourceLoader.exists(path):
		return container
	var tex := load(path) as Texture2D
	if tex == null:
		return container
	var img := TextureRect.new()
	img.texture = tex
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(img)
	return container


func _on_chat_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return
	GlobalChatState.send_chat(trimmed)
	_chat_input.text = ""


func _on_chat_received(steam_id: int, member_name: String, text: String) -> void:
	_append_chat_line(steam_id, member_name, text)


func _append_chat_line(steam_id: int, member_name: String, text: String) -> void:
	# Each line: member name colored by THEIR class accent, then the
	# message body in default color. Class accent comes from each
	# member's published class_id in GlobalChatState.members; falls
	# back to a neutral accent for senders we don't have class data
	# for yet (just-joined peers, etc.).
	var color_hex := _color_for_member(steam_id)
	_chat_history.append_text("[color=%s]%s[/color]: %s\n" % [color_hex, member_name, text])
	var lines := _chat_history.get_line_count()
	if lines > HISTORY_MAX_LINES:
		# RichTextLabel doesn't expose a "drop first N lines" API, so we
		# reset content past the threshold. Edge case only — only fires
		# after very long sessions.
		_chat_history.clear()


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


func _color_for_member(steam_id: int) -> String:
	var data: Dictionary = GlobalChatState.members.get(steam_id, {})
	var class_id: StringName = data.get("class_id", &"")
	var spec_id: StringName = data.get("spec_id", &"")
	var palette := UIThemeState.get_palette_for(class_id, spec_id) if class_id != &"" else null
	var c: Color = palette.accent if palette != null else Color(0.66, 0.78, 1.0)
	return "#%02x%02x%02x" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]


func _on_members_changed() -> void:
	_refresh_members()
	_refresh_status()


func _on_joined() -> void:
	refresh()


func _on_left() -> void:
	refresh()
