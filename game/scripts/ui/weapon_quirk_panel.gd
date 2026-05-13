extends Control
class_name WeaponQuirkPanel

## Always-visible HUD reminder of the player's currently-equipped weapon
## quirks. Each weapon archetype has a "signature passive" (Backstab,
## Wind-Up, Pierce, etc) that's easy to forget across 11 weapon classes;
## this panel surfaces a one-line play tip per equipped weapon so the
## player doesn't have to memorise the table.
##
## Rolled stats from the weapon are baked directly into each tip sentence
## with variable values highlighted in gold so the player can tell which
## parts are gear-dependent.
##
## Refreshes on InventoryState.equipment_changed. Auto-hides if no
## equipped weapons have a known quirk (e.g. early-game with only an
## offhand). Layout: top-right of HUD, stack of small rich-text labels.

# Universal melee combo reminder shown alongside the per-archetype tip
# for any equipped melee weapon. Combo applies to both 1H and 2H, so
# a separate line keeps the per-archetype quirk uncluttered.
const MELEE_COMBO_TIP: String = "3-hit combo: wider, stronger, finisher applies status"

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
# Highlight color for variable (rolled) values embedded in tip text.
const VAR_COLOR_HEX: String = "#f2d97a"

var _bg: ColorRect
var _vbox: VBoxContainer
# Public so MissionsPanel can stack underneath, accounting for
# this panel's variable height (collapses when no quirks active).
var bottom_edge_y: float = 0.0
signal layout_changed


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
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
	_vbox.offset_left = 5.0
	_vbox.offset_top = 3.0
	_vbox.offset_right = -5.0
	_vbox.offset_bottom = -3.0
	add_child(_vbox)

	add_to_group(&"weapon_quirk_panel")
	InventoryState.equipment_changed.connect(_on_equipment_changed)
	refresh()


func _on_equipment_changed(_slot: StringName) -> void:
	refresh()


func refresh() -> void:
	for child in _vbox.get_children():
		_vbox.remove_child(child)
		child.queue_free()

	var entries: Array = _gather_active_quirks()
	if entries.is_empty():
		visible = false
		bottom_edge_y = position.y
		layout_changed.emit()
		return
	visible = true
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
	for entry in entries:
		var header := Label.new()
		header.text = entry["header"]
		header.add_theme_font_size_override(&"font_size", HEADER_FONT_SIZE)
		header.add_theme_color_override(&"font_color", HEADER_COLOR)
		header.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vbox.add_child(header)
		# Use RichTextLabel for BBCode color highlighting on variable values.
		var tip := RichTextLabel.new()
		tip.bbcode_enabled = true
		tip.fit_content = true
		tip.scroll_active = false
		tip.text = entry["tip"]
		tip.add_theme_font_size_override(&"normal_font_size", TIP_FONT_SIZE)
		tip.add_theme_color_override(&"default_color", TIP_COLOR)
		tip.custom_minimum_size = Vector2(PANEL_WIDTH - 10.0, 0.0)
		tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_vbox.add_child(tip)
	call_deferred(&"_resize_to_content")


func _resize_to_content() -> void:
	custom_minimum_size.y = _vbox.size.y + 8.0
	size.y = custom_minimum_size.y
	bottom_edge_y = position.y + size.y
	layout_changed.emit()


func _gather_active_quirks() -> Array:
	var entries: Array = []
	var seen_quirks: Dictionary = {}
	var any_melee := false
	var has_weapon := false
	for slot in [&"weapon", &"offhand"]:
		var item: Item = InventoryState.get_equipped(slot)
		if item == null:
			continue
		has_weapon = true
		if item.weapon_base_id in PrototypePlayer.MELEE_BASE_IDS:
			any_melee = true
		var tip: String = _build_quirk_tip(item)
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
	if not has_weapon:
		entries.append({
			"header": "Unarmed Strike",
			"tip": _build_unarmed_tip(),
		})
	return entries


# Wrap a value string in BBCode color tags so it stands out from the
# surrounding grey tip text. Used for rolled / gear-dependent numbers.
func _v(text: String) -> String:
	return "[color=%s]%s[/color]" % [VAR_COLOR_HEX, text]


# Build a single-line quirk tip with rolled stats baked in.
# Variable parts are highlighted via _v(). Returns "" for unknown archetypes.
func _build_quirk_tip(item: Item) -> String:
	match item.weapon_base_id:
		&"melee_1h":
			var bleed: int = item.get_effective_modifier(&"bleed_damage")
			if bleed > 0:
				return "Strike from behind for %s damage, combo bleed %s/tick" % [_v("+50%"), _v(str(bleed))]
			return "Strike from behind for %s damage" % _v("+50%")
		&"melee_2h":
			var impact: int = item.get_modifier(&"impact_radius")
			if impact > 0:
				return "Stand still 1s — next swing deals %s, %s impact radius" % [_v("+75%"), _v("+%dm" % impact)]
			return "Stand still 1s — next swing deals %s" % _v("+75%")
		&"ranged_1h":
			var oc: int = item.get_effective_modifier(&"overcharge_chance")
			if oc > 0:
				return "Pause 1s for a %s charged shot, %s overcharge chance" % [_v("1.5×"), _v("%d%%" % oc)]
			return "Pause 1s between shots for a %s charged shot" % _v("1.5×")
		&"ranged_2h":
			var pen: int = item.get_modifier(&"penetration")
			var pen_val: int = maxi(1, pen)
			return "Bolts pierce through %s" % _v("%d enem%s" % [pen_val, "y" if pen_val == 1 else "ies"])
		&"smg_1h":
			var ric: int = item.get_effective_modifier(&"ricochet_chance")
			if ric > 0:
				return "Every 5th shot deals %s damage, %s ricochet chance" % [_v("2×"), _v("%d%%" % ric)]
			return "Every 5th shot deals %s damage" % _v("2×")
		&"lmg_2h":
			var bonus: int = item.get_effective_modifier(&"sustained_bonus")
			var total_pct: int = 50 + bonus
			return "Sustained fire stacks up to %s damage" % _v("+%d%%" % total_pct)
		&"sniper_2h":
			var hs: int = item.get_effective_modifier(&"headshot_bonus")
			var total_pct: int = 50 + hs
			return "First shot on a fresh target deals %s" % _v("+%d%%" % total_pct)
		&"rpg_2h":
			var blast: int = item.get_modifier(&"blast_radius_bonus")
			if blast > 0:
				return "Blast staggers every enemy, %s bonus blast radius" % _v("+%dm" % blast)
			return "Blast staggers every enemy caught in it"
		&"shotgun_2h":
			var pellets: int = item.get_modifier(&"pellet_count")
			var spread: int = item.get_modifier(&"spread_angle")
			var parts: Array[String] = ["Pellets at point-blank (<2m) deal %s" % _v("+50%")]
			if pellets > 0:
				parts.append("%s pellets" % _v(str(pellets)))
			if spread > 0:
				parts.append("%s spread" % _v("%d°" % spread))
			return ", ".join(parts)
		&"taser_2h":
			var ret: int = item.get_effective_modifier(&"chain_retention")
			if ret > 0:
				return "Every 10th hit releases %s damage, %s chain retention" % [_v("3×"), _v("%d%%" % ret)]
			return "Every 10th hit on an enemy releases %s damage" % _v("3×")
		&"accelerator_2h":
			var ramp_pct: int = item.get_effective_modifier(&"ramp_speed")
			if ramp_pct > 0:
				var base_dur := 2.5
				var eff_dur := base_dur / (1.0 + float(ramp_pct) * 0.01)
				return "Hold the stream — damage ramps to %s over %s" % [_v("2.5×"), _v("%.1fs" % eff_dur)]
			return "Hold the stream — damage ramps to %s over %s" % [_v("2.5×"), _v("2.5s")]
	return ""


func _build_unarmed_tip() -> String:
	var gloves: Item = InventoryState.get_equipped(&"hands")
	if gloves == null:
		return "Short-range punch. Equip gloves with unarmed bonuses to power up."
	var parts: Array[String] = []
	var dmg: int = gloves.get_effective_modifier(&"unarmed_damage_bonus")
	if dmg > 0:
		parts.append("%s bonus damage" % _v("+%d" % dmg))
	var stun: int = gloves.get_effective_modifier(&"unarmed_stun_chance")
	if stun > 0:
		parts.append("%s stun chance" % _v("%d%%" % stun))
	var aoe: int = gloves.get_effective_modifier(&"unarmed_aoe_radius")
	if aoe > 0:
		parts.append("%s AoE radius" % _v("%dm" % aoe))
	if parts.is_empty():
		return "Short-range punch. Equip gloves with unarmed bonuses to power up."
	return "Short-range punch with " + ", ".join(parts)


func _build_header(item: Item) -> String:
	if item.model_name != "":
		return item.model_name
	if item.sub_type != "":
		return item.sub_type
	return item.main_type
