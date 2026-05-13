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
	&"accelerator_2h": "Hold the stream — damage ramps to 2.5× over 2.5s",
}

# Universal melee combo reminder shown alongside the per-archetype tip
# for any equipped melee weapon. Combo applies to both 1H and 2H, so
# a separate line keeps the per-archetype quirk uncluttered.
const MELEE_COMBO_TIP: String = "3-hit combo: wider, stronger, finisher applies status"

# Display formatters for weapon signature stats shown under each quirk tip.
# Mirrors prototype_tooltip's _WEAPON_SIG_DISPLAY but uses compact labels
# suited to the small Combat Effects panel.
const SIG_STAT_DISPLAY: Dictionary = {
	&"blast_radius_bonus": { "label": "Blast Radius",   "fmt": "+%d m" },
	&"pellet_count":       { "label": "Pellets",        "fmt": "%d" },
	&"spread_angle":       { "label": "Spread",         "fmt": "%d°", "raw": true },
	&"penetration":        { "label": "Penetration",    "fmt": "%d" },
	&"headshot_bonus":     { "label": "Headshot",       "fmt": "+%d%%" },
	&"chain_retention":    { "label": "Chain Retain",   "fmt": "%d%%" },
	&"ramp_speed":         { "label": "Ramp Speed",     "fmt": "+%d%%" },
	&"bleed_damage":       { "label": "Bleed",          "fmt": "%d/tick" },
	&"impact_radius":      { "label": "Impact",         "fmt": "%d m" },
	&"sustained_bonus":    { "label": "Sustained",      "fmt": "+%d%%" },
	&"ricochet_chance":    { "label": "Ricochet",       "fmt": "%d%%" },
	&"overcharge_chance":  { "label": "Overcharge",     "fmt": "%d%%" },
}

const PANEL_WIDTH: float = 210.0
const PANEL_TITLE: String = "Combat Effects"
const TITLE_FONT_SIZE: int = 11
const HEADER_FONT_SIZE: int = 9
const TIP_FONT_SIZE: int = 8
const TITLE_COLOR := Color(0.95, 0.92, 0.85, 1.0)
const HEADER_COLOR := Color(0.95, 0.85, 0.5, 1.0)
const TIP_COLOR := Color(0.78, 0.78, 0.78, 0.85)
const PANEL_BG := Color(0.0, 0.0, 0.0, 0.55)
const TITLE_DIVIDER_COLOR := Color(0.95, 0.85, 0.5, 0.35)

var _bg: ColorRect
var _vbox: VBoxContainer
# Public so MissionsPanel can stack underneath, accounting for
# this panel's variable height (collapses when no quirks active).
var bottom_edge_y: float = 0.0
signal layout_changed


func _ready() -> void:
	# Top-right, anchored just under the minimap. The minimap's corner
	# offset + size are exposed as constants on Minimap; we mirror them
	# so this panel stays glued to the bottom edge of the map even if
	# the map size changes. mouse_filter=IGNORE — purely informational.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	# Anchor offsets so right edge sits one margin in from screen edge
	# and top sits just below the minimap. CORNER_MARGIN + CORNER_SIZE
	# from Minimap match what the (former) controls panel used.
	var map_margin := Minimap.CORNER_MARGIN
	var map_size := Minimap.CORNER_SIZE
	offset_left = -PANEL_WIDTH - map_margin
	offset_right = -map_margin
	offset_top = map_margin + map_size + 4.0
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
	# Tight padding — panel is small and lives in the corner.
	_vbox.offset_left = 5.0
	_vbox.offset_top = 3.0
	_vbox.offset_right = -5.0
	_vbox.offset_bottom = -3.0
	add_child(_vbox)

	# MissionsPanel finds us via this group so it can dock just below
	# our bottom edge regardless of where we land in the scene tree.
	add_to_group(&"weapon_quirk_panel")

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
		bottom_edge_y = position.y
		layout_changed.emit()
		return
	visible = true
	# Title label at the top — frames the panel as "Combat Effects" so
	# the player knows the section identity without having to read the
	# weapon quirks themselves.
	var title := Label.new()
	title.text = PANEL_TITLE
	title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override(&"font_color", TITLE_COLOR)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(title)
	# Thin divider line under the title — visual separator between the
	# section header and the per-weapon entries.
	var divider := ColorRect.new()
	divider.color = TITLE_DIVIDER_COLOR
	divider.custom_minimum_size = Vector2(0.0, 1.0)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vbox.add_child(divider)
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
		var stats_text: String = entry.get("stats", "")
		if stats_text != "":
			var stats_label := Label.new()
			stats_label.text = stats_text
			stats_label.add_theme_font_size_override(&"font_size", TIP_FONT_SIZE)
			stats_label.add_theme_color_override(&"font_color", HEADER_COLOR)
			stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			stats_label.custom_minimum_size = Vector2(PANEL_WIDTH - 10.0, 0.0)
			stats_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_vbox.add_child(stats_label)
	# Re-fit the BG to the new content height after children layout.
	# Defer one frame so the VBoxContainer has reported its size.
	call_deferred(&"_resize_to_content")


func _resize_to_content() -> void:
	custom_minimum_size.y = _vbox.size.y + 8.0
	size.y = custom_minimum_size.y
	bottom_edge_y = position.y + size.y
	layout_changed.emit()


# Build the list of active quirks for currently-equipped weapons. Each
# entry is {header: "Sniper Rifle (MK-7 Voidcaster)", tip: "First shot..."}.
# Returns one entry per weapon (main + offhand if present) plus a combo
# entry if any melee weapon is equipped.
func _gather_active_quirks() -> Array:
	var entries: Array = []
	var seen_quirks: Dictionary = {}  # don't double-list if main and offhand share an archetype
	var any_melee := false
	var has_weapon := false
	for slot in [&"weapon", &"offhand"]:
		var item: Item = InventoryState.get_equipped(slot)
		if item == null:
			continue
		has_weapon = true
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
			"stats": _build_sig_stats(item),
		})
	if any_melee:
		entries.append({
			"header": "Melee Combo",
			"tip": MELEE_COMBO_TIP,
		})
	# Unarmed fallback — show when no weapon is equipped.
	if not has_weapon:
		entries.append({
			"header": "Unarmed Strike",
			"tip": "Short-range punch. Equip gloves with unarmed bonuses to power up.",
			"stats": _build_unarmed_stats(),
		})
	return entries


func _build_unarmed_stats() -> String:
	var gloves: Item = InventoryState.get_equipped(&"hands")
	if gloves == null:
		return ""
	var parts: Array[String] = []
	var dmg: int = gloves.get_effective_modifier(&"unarmed_damage_bonus")
	if dmg > 0:
		parts.append("Damage: +%d" % dmg)
	var stun: int = gloves.get_effective_modifier(&"unarmed_stun_chance")
	if stun > 0:
		parts.append("Stun: %d%%" % stun)
	var aoe: int = gloves.get_effective_modifier(&"unarmed_aoe_radius")
	if aoe > 0:
		parts.append("AoE: %dm" % aoe)
	return "  ".join(parts)


# Header line — uses the rolled model_name when set (e.g. "VK-9
# Stinger"), otherwise the archetype sub_type ("SMG"). Keeps the
# label terse so the tip line is readable at a glance.
## Build a compact stat summary for the weapon's signature stats.
## Returns a single line like "Pellets: 9  Spread: 32°" or "" if none.
func _build_sig_stats(item: Item) -> String:
	var parts: Array[String] = []
	for sig_key: StringName in SIG_STAT_DISPLAY:
		var raw: int = int(item.stat_modifiers.get(sig_key, 0))
		if raw == 0:
			continue
		var d: Dictionary = SIG_STAT_DISPLAY[sig_key]
		var val: int
		if d.get("raw", false):
			val = raw
		else:
			val = item.get_effective_modifier(sig_key)
		parts.append("%s: %s" % [d["label"], d["fmt"] % val])
	return "  ".join(parts)


func _build_header(item: Item) -> String:
	if item.model_name != "":
		return item.model_name
	if item.sub_type != "":
		return item.sub_type
	return item.main_type
