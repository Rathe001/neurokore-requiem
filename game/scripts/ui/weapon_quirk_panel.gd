extends Control
class_name WeaponQuirkPanel

## Always-visible HUD reminder of the player's currently-equipped weapon
## quirks. Each weapon archetype has a "signature passive" (Backstab,
## Wind-Up, Pierce, etc) that's easy to forget across 11 weapon classes;
## this panel surfaces a one-line play tip per equipped weapon so the
## player doesn't have to memorise the table.
##
## Refreshes on InventoryState.equipment_changed. Auto-hides if no
## equipped weapons have a known quirk (e.g. early-game with only an
## offhand). Layout: top-left of HUD, stack of small grey labels.

# One-line play tip per weapon_base_id. Phrased imperatively so the
# panel reads as instruction ("Strike from behind") rather than a
# tooltip-style description ("This weapon deals bonus damage when...").
const QUIRK_TIPS: Dictionary = {
	&"melee_1h": "Strike enemies from behind for +50% damage",
	&"melee_2h": "Stand still 1s — next swing deals +75%",
	&"ranged_1h": "Pause 1s between shots for a 1.5× charged shot",
	&"ranged_2h": "Bolts pierce through 1 enemy",
	&"smg_1h": "Every 5th shot deals 2× damage",
	&"lmg_2h": "Sustained fire stacks up to +50% damage",
	&"sniper_2h": "First shot on a fresh target deals +50%",
	&"rpg_2h": "Blast staggers every enemy caught in it",
	&"shotgun_2h": "Pellets at point-blank (<2m) deal +50%",
	&"taser_2h": "Every 10th hit on an enemy releases 3× damage",
	&"accelerator_2h": "Hold the stream — damage ramps up to +30%",
}

# Universal melee combo reminder shown alongside the per-archetype tip
# for any equipped melee weapon. Combo applies to both 1H and 2H, so
# a separate line keeps the per-archetype quirk uncluttered.
const MELEE_COMBO_TIP: String = "3-hit combo: wider, stronger, finisher applies status"

const PANEL_WIDTH: float = 380.0
const HEADER_FONT_SIZE: int = 12
const TIP_FONT_SIZE: int = 11
const HEADER_COLOR := Color(0.95, 0.85, 0.5, 1.0)
const TIP_COLOR := Color(0.78, 0.78, 0.78, 0.85)
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.35)

var _bg: ColorRect
var _vbox: VBoxContainer


func _ready() -> void:
	# Top-left, fixed-size panel. mouse_filter=IGNORE so it never eats
	# clicks; the panel is purely informational. visible toggles with
	# whether any equipped weapon has a known quirk.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 0.0
	anchor_top = 0.0
	offset_left = 12.0
	offset_top = 12.0
	custom_minimum_size = Vector2(PANEL_WIDTH, 0.0)

	_bg = ColorRect.new()
	_bg.color = PANEL_BG
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)

	_vbox = VBoxContainer.new()
	_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vbox.add_theme_constant_override(&"separation", 2)
	# Padding inside the bg.
	_vbox.offset_left = 8.0
	_vbox.offset_top = 4.0
	_vbox.offset_right = -8.0
	_vbox.offset_bottom = -4.0
	add_child(_vbox)

	InventoryState.equipment_changed.connect(_on_equipment_changed)
	refresh()


func _on_equipment_changed(_slot: StringName) -> void:
	refresh()


func refresh() -> void:
	# Clear old children. queue_free on each label is fine — VBoxContainer
	# repacks the rest. Building the panel fresh on every equip change is
	# cheap (max ~4 labels) and avoids state bookkeeping.
	for child in _vbox.get_children():
		child.queue_free()

	var entries: Array = _gather_active_quirks()
	if entries.is_empty():
		visible = false
		return
	visible = true
	for entry in entries:
		var header := Label.new()
		header.text = entry["header"]
		header.add_theme_font_size_override(&"font_size", HEADER_FONT_SIZE)
		header.add_theme_color_override(&"font_color", HEADER_COLOR)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vbox.add_child(header)
		var tip := Label.new()
		tip.text = "  " + entry["tip"]
		tip.add_theme_font_size_override(&"font_size", TIP_FONT_SIZE)
		tip.add_theme_color_override(&"font_color", TIP_COLOR)
		tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tip.custom_minimum_size = Vector2(PANEL_WIDTH - 16.0, 0.0)
		tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vbox.add_child(tip)
	# Re-fit the BG to the new content height after children layout.
	# Defer one frame so the VBoxContainer has reported its size.
	call_deferred(&"_resize_to_content")


func _resize_to_content() -> void:
	custom_minimum_size.y = _vbox.size.y + 8.0
	size.y = custom_minimum_size.y


# Build the list of active quirks for currently-equipped weapons. Each
# entry is {header: "Sniper Rifle (MK-7 Voidcaster)", tip: "First shot..."}.
# Returns one entry per weapon (main + offhand if present) plus a combo
# entry if any melee weapon is equipped.
func _gather_active_quirks() -> Array:
	var entries: Array = []
	var seen_quirks: Dictionary = {}  # don't double-list if main and offhand share an archetype
	var any_melee := false
	for slot in [&"weapon", &"offhand"]:
		var item: Item = InventoryState.get_equipped(slot)
		if item == null:
			continue
		if item.weapon_base_id in PrototypePlayer.MELEE_BASE_IDS:
			any_melee = true
		var tip: String = QUIRK_TIPS.get(item.weapon_base_id, "")
		if tip.is_empty():
			continue
		if seen_quirks.has(item.weapon_base_id):
			continue
		seen_quirks[item.weapon_base_id] = true
		entries.append({
			"header": _build_header(item),
			"tip": tip,
		})
	if any_melee:
		entries.append({
			"header": "Melee Combo",
			"tip": MELEE_COMBO_TIP,
		})
	return entries


# Header line — uses the rolled model_name when set (e.g. "VK-9
# Stinger"), otherwise the archetype sub_type ("SMG"). Keeps the
# label terse so the tip line is readable at a glance.
func _build_header(item: Item) -> String:
	if item.model_name != "":
		return item.model_name
	if item.sub_type != "":
		return item.sub_type
	return item.main_type
