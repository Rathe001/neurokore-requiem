extends Control
class_name MissionsPanel

## Mission tracker panel — stacked under the Combat Effects panel in
## the top-right corner. Always visible (even when no missions are
## active, showing a placeholder); positions itself dynamically beneath
## WeaponQuirkPanel so the two panels stay glued together as the
## quirks panel grows / shrinks with equipped weapons.
##
## Content is placeholder for now — the mission system isn't built
## yet. Once it lands, replace `_gather_active_missions` with a read
## from MissionState (or whatever the eventual API is).

const PANEL_WIDTH: float = 210.0
const PANEL_TITLE: String = "Missions"
const STACK_GAP: float = 4.0
const TITLE_FONT_SIZE: int = 11
const HEADER_FONT_SIZE: int = 9
const TIP_FONT_SIZE: int = 8
const TITLE_COLOR := Color(0.95, 0.92, 0.85, 1.0)
const HEADER_COLOR := Color(0.95, 0.85, 0.5, 1.0)
const TIP_COLOR := Color(0.78, 0.78, 0.78, 0.85)
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.55)
const TITLE_DIVIDER_COLOR := Color(0.95, 0.85, 0.5, 0.35)
const EMPTY_PLACEHOLDER := "No active missions"

var _bg: ColorRect
var _vbox: VBoxContainer
var _quirk_panel: WeaponQuirkPanel = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	var map_margin := Minimap.CORNER_MARGIN
	offset_left = -PANEL_WIDTH - map_margin
	offset_right = -map_margin
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)

	_bg = ColorRect.new()
	_bg.color = PANEL_BG
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	_vbox = VBoxContainer.new()
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override(&"separation", 1)
	_vbox.offset_left = 5.0
	_vbox.offset_top = 3.0
	_vbox.offset_right = -5.0
	_vbox.offset_bottom = -3.0
	add_child(_vbox)

	# Track the sibling combat-effects panel so we can dock just below
	# its bottom edge. The panel may resize whenever the player swaps
	# weapons, so we listen to its layout_changed signal and reposition.
	_quirk_panel = get_tree().get_first_node_in_group(&"weapon_quirk_panel") as WeaponQuirkPanel
	if _quirk_panel == null:
		# Fall back to a sibling lookup — HUD scene parents both panels
		# under Root so a sibling named WeaponQuirkPanel is the usual case.
		var sib := get_parent().get_node_or_null(^"WeaponQuirkPanel") if get_parent() != null else null
		if sib is WeaponQuirkPanel:
			_quirk_panel = sib
	if _quirk_panel != null:
		_quirk_panel.layout_changed.connect(_reposition_under_quirks)

	refresh()
	_reposition_under_quirks()


func refresh() -> void:
	for child in _vbox.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = PANEL_TITLE
	title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override(&"font_color", TITLE_COLOR)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(title)
	var divider := ColorRect.new()
	divider.color = TITLE_DIVIDER_COLOR
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(divider)
	var entries: Array = _gather_active_missions()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = EMPTY_PLACEHOLDER
		empty.add_theme_font_size_override(&"font_size", TIP_FONT_SIZE)
		empty.add_theme_color_override(&"font_color", TIP_COLOR)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vbox.add_child(empty)
	else:
		for entry in entries:
			var header := Label.new()
			header.text = entry["header"]
			header.add_theme_font_size_override(&"font_size", HEADER_FONT_SIZE)
			header.add_theme_color_override(&"font_color", HEADER_COLOR)
			header.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_vbox.add_child(header)
			var tip := Label.new()
			tip.text = entry["tip"]
			tip.add_theme_font_size_override(&"font_size", TIP_FONT_SIZE)
			tip.add_theme_color_override(&"font_color", TIP_COLOR)
			tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			tip.custom_minimum_size = Vector2(PANEL_WIDTH - 10.0, 0.0)
			tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_vbox.add_child(tip)
	call_deferred(&"_resize_to_content")


func _resize_to_content() -> void:
	custom_minimum_size.y = _vbox.size.y + 8.0
	size.y = custom_minimum_size.y


# Position offset_top so this panel sits just below the quirks panel's
# bottom edge (or directly under the minimap when quirks is hidden).
# Triggered by quirks panel's layout_changed; also called once during
# _ready so the initial position is correct.
func _reposition_under_quirks() -> void:
	var map_margin := Minimap.CORNER_MARGIN
	var map_size := Minimap.CORNER_SIZE
	var minimap_bottom := map_margin + map_size + 4.0
	if _quirk_panel != null and _quirk_panel.visible:
		offset_top = _quirk_panel.bottom_edge_y + STACK_GAP
	else:
		offset_top = minimap_bottom


# Placeholder — returns an empty list until the mission system lands.
# Once MissionState (or whatever the API is) exists, read active
# missions here and return entries shaped as {header, tip} dicts.
func _gather_active_missions() -> Array:
	return []
