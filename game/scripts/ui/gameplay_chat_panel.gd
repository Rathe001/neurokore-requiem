extends Control
class_name GameplayChatPanel

## In-game chat overlay, mounted under the HUD's `Root`. Press chat_toggle
## (Enter) to open the input; press it again or Return to send; Escape to
## cancel without sending. Messages live in a small bottom-left rolling
## log that fades after a few seconds when the panel isn't focused.
##
## Coupled to GameplayChatState via the autoload's chat_received signal —
## the panel is purely a renderer + input surface; all networking lives
## in the autoload.

# How many lines the log keeps visible at once. Older entries fall off
# the top as new ones arrive.
const MAX_VISIBLE_LINES: int = 6
# Each line stays at full opacity for this long after arrival when the
# input is closed; after this it fades over FADE_DURATION to invisible.
# Active-input mode pins all visible lines at full opacity regardless.
const HOLD_DURATION: float = 8.0
const FADE_DURATION: float = 2.0
# Width of the chat overlay in pixels — log width and input width both.
# Tuned to match the AvatarPanel column on the left side of the HUD.
const PANEL_WIDTH: float = 480.0
# Vertical offset of the input row from the bottom edge of the screen.
# Sits above the AvatarPanel / hotbar so it doesn't overlap them.
const INPUT_BOTTOM_MARGIN: float = 110.0
# Stack the log just above the input row.
const LOG_BOTTOM_MARGIN: float = 140.0
const LOG_HEIGHT: float = 140.0
# Background dim behind the log when the input is open — reads as a
# focused chat session vs the passive translucent log.
const ACTIVE_BG_COLOR := Color(0.0, 0.0, 0.0, 0.45)
const PASSIVE_BG_COLOR := Color(0.0, 0.0, 0.0, 0.0)


var _log_bg: ColorRect
var _log_box: VBoxContainer
var _input_row: HBoxContainer
var _input_prefix: Label
var _input_field: LineEdit
var _is_active: bool = false
# Each entry: { line: RichTextLabel, arrived_at: float }
var _lines: Array = []


func _ready() -> void:
	# Full-screen anchor; mouse only intercepted when the input row is
	# active. Otherwise this Control passes clicks through to the world.
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_log_bg = ColorRect.new()
	_log_bg.color = PASSIVE_BG_COLOR
	_log_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bottom-anchored fixed-size strip: anchor_top = 1 too so the rect
	# is defined by the offsets relative to the parent's BOTTOM edge,
	# not stretched between top and bottom.
	_log_bg.anchor_left = 0.0
	_log_bg.anchor_right = 0.0
	_log_bg.anchor_top = 1.0
	_log_bg.anchor_bottom = 1.0
	_log_bg.offset_left = 12.0
	_log_bg.offset_right = 12.0 + PANEL_WIDTH
	_log_bg.offset_top = -LOG_BOTTOM_MARGIN - LOG_HEIGHT
	_log_bg.offset_bottom = -LOG_BOTTOM_MARGIN
	add_child(_log_bg)

	_log_box = VBoxContainer.new()
	_log_box.alignment = BoxContainer.ALIGNMENT_END
	_log_box.add_theme_constant_override(&"separation", 2)
	_log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_box.anchor_left = 0.0
	_log_box.anchor_top = 0.0
	_log_box.anchor_right = 1.0
	_log_box.anchor_bottom = 1.0
	_log_box.offset_left = 8.0
	_log_box.offset_right = -8.0
	_log_box.offset_top = 4.0
	_log_box.offset_bottom = -4.0
	_log_bg.add_child(_log_box)

	_input_row = HBoxContainer.new()
	_input_row.visible = false
	# Same bottom-anchored strip pattern as the log background.
	_input_row.anchor_left = 0.0
	_input_row.anchor_right = 0.0
	_input_row.anchor_top = 1.0
	_input_row.anchor_bottom = 1.0
	_input_row.offset_left = 12.0
	_input_row.offset_right = 12.0 + PANEL_WIDTH
	_input_row.offset_top = -INPUT_BOTTOM_MARGIN - 28.0
	_input_row.offset_bottom = -INPUT_BOTTOM_MARGIN
	add_child(_input_row)

	_input_prefix = Label.new()
	_input_prefix.text = "Say:"
	_input_prefix.add_theme_color_override(&"font_color", Color(0.85, 0.85, 0.85, 1.0))
	_input_row.add_child(_input_prefix)

	_input_field = LineEdit.new()
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.max_length = GameplayChatState.MAX_MESSAGE_LENGTH
	_input_field.placeholder_text = ""
	_input_field.text_submitted.connect(_on_text_submitted)
	# Esc cancels even when the LineEdit has focus — Godot otherwise
	# routes Escape into the LineEdit's clear-then-unfocus default.
	_input_field.gui_input.connect(_on_input_field_gui_input)
	_input_row.add_child(_input_field)

	GameplayChatState.chat_received.connect(_on_chat_received)
	set_process(true)


func _process(_delta: float) -> void:
	# Fade-out animation only runs when the panel ISN'T active. While
	# active, every visible line is pinned at alpha 1.0 so the user can
	# read the recent transcript while typing.
	if _is_active:
		return
	var now := _now()
	for entry in _lines:
		var age := now - float(entry["arrived_at"])
		var label: RichTextLabel = entry["line"]
		if not is_instance_valid(label):
			continue
		var alpha: float = 1.0
		if age > HOLD_DURATION:
			var fade_t: float = clampf((age - HOLD_DURATION) / FADE_DURATION, 0.0, 1.0)
			alpha = 1.0 - fade_t
		label.modulate.a = alpha


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"chat_toggle"):
		return
	if _is_active:
		# Pressing Enter while typing already fires text_submitted on the
		# LineEdit; this branch only fires if the input doesn't have focus
		# for some reason (modal overlay grabbed it). Submit + close.
		_submit_current()
		get_viewport().set_input_as_handled()
		return
	# Don't open chat over a focused modal (escape menu, etc) — those take
	# precedence and Enter often confirms a button. Inventory + character
	# panel are non-modal browse views, fine to type over.
	if _is_blocking_modal_open():
		return
	_open_input()
	get_viewport().set_input_as_handled()


# True when a modal that should block chat is visible. Inventory and the
# character panel are explicitly NOT blocking — players might want to
# discuss an item they're hovering. Only the escape menu blocks.
func _is_blocking_modal_open() -> bool:
	var root := get_parent()
	if root == null:
		return false
	var main_menu := root.get_node_or_null(^"MainMenu") as CanvasItem
	return main_menu != null and main_menu.visible


# ── Public API ──────────────────────────────────────────────────────

## Returns true while the input row has focus. The HUD / player input
## handler can poll this to suppress movement / skill keys so typing
## doesn't fire a skill or move the character.
func is_typing() -> bool:
	return _is_active


# ── Internals ───────────────────────────────────────────────────────

func _open_input() -> void:
	_is_active = true
	GameplayChatState.typing = true
	_input_row.visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_log_bg.color = ACTIVE_BG_COLOR
	# Pin all visible lines at full opacity for the active session so the
	# user has full context while typing.
	for entry in _lines:
		var label: RichTextLabel = entry["line"]
		if is_instance_valid(label):
			label.modulate.a = 1.0
	_input_field.text = ""
	_input_field.grab_focus()


func _close_input() -> void:
	_is_active = false
	GameplayChatState.typing = false
	_input_row.visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_bg.color = PASSIVE_BG_COLOR
	_input_field.release_focus()
	# Reset arrival timestamps so the fade clock starts NOW, not when the
	# message originally arrived. Otherwise opening chat then immediately
	# closing it would skip straight to the fade for already-aged lines.
	var now := _now()
	for entry in _lines:
		entry["arrived_at"] = now


func _submit_current() -> void:
	var text := _input_field.text.strip_edges()
	if not text.is_empty():
		GameplayChatState.send_chat(text)
	_close_input()


func _on_text_submitted(text: String) -> void:
	var trimmed := text.strip_edges()
	if not trimmed.is_empty():
		GameplayChatState.send_chat(trimmed)
	_close_input()


func _on_input_field_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		_close_input()
		get_viewport().set_input_as_handled()


func _on_chat_received(steam_id: int, member_name: String, text: String) -> void:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override(&"normal_font_size", 13)
	var name_color := _color_for_speaker(steam_id)
	var name_hex := "#%02x%02x%02x" % [
		int(name_color.r * 255), int(name_color.g * 255), int(name_color.b * 255)
	]
	# Escape BBCode in the message body so a player typing "[color=red]"
	# can't inject markup. RichTextLabel's escape_bbcode does the encode.
	var safe_name := member_name.replace("[", "(").replace("]", ")")
	var safe_text := text.replace("[", "(").replace("]", ")")
	label.text = "[color=%s]%s:[/color] %s" % [name_hex, safe_name, safe_text]
	_log_box.add_child(label)
	_lines.append({"line": label, "arrived_at": _now()})
	while _lines.size() > MAX_VISIBLE_LINES:
		var oldest = _lines.pop_front()
		var oldest_label: RichTextLabel = oldest["line"]
		if is_instance_valid(oldest_label):
			oldest_label.queue_free()


# Resolve the speaker's display color from PlayerState (self) or via
# Steam lobby member data (remote peers). GameplayChatState publishes
# every peer's class_id under CLASS_KEY on lobby join; Steam replicates
# the string and getLobbyMemberData returns it instantly. Falls back to
# a muted neutral if the data hasn't replicated yet (first frame after a
# peer joins) or if a peer is somehow in the lobby without publishing.
func _color_for_speaker(steam_id: int) -> Color:
	if steam_id == SteamState.steam_id:
		# resolved_self_class_id prefers spec_id over the origin class_id —
		# specced characters (Count, Forged, ...) get their spec color
		# instead of the muted origin (analog/cyborg) color.
		return AttributeState.color_for_id(GameplayChatState.resolved_self_class_id())
	if NetState.lobby_id != 0:
		var class_str: String = Steam.getLobbyMemberData(
			NetState.lobby_id, steam_id, GameplayChatState.CLASS_KEY)
		if not class_str.is_empty():
			return AttributeState.color_for_id(StringName(class_str))
	return Color(0.85, 0.85, 0.85, 1.0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
