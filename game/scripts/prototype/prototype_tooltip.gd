class_name PrototypeTooltip
extends Control

const SCREEN_MARGIN := Vector2(12, 12)
const MOUSE_OFFSET := Vector2(14.0, 14.0)
const PADDING_X := 8
const PADDING_Y := 6
const CONTENT_MIN_WIDTH := 140.0
const PARK_DURATION := 0.14
const PARK_TOP_MARGIN := 24.0
const ANCHOR_OFFSET_Y := -16.0  # tooltip sits this far above target's screen point

const COMPARE_BETTER_COLOR := "#66cc66"
const COMPARE_WORSE_COLOR := "#cc5555"
const COMPARE_NEUTRAL_COLOR := "#999999"

# Stat modifier lines in the tooltip use generic formatting (white text)
# now that the old 8-attribute stat system has been removed.

var _bg: PanelContainer
var _vbox: VBoxContainer
var _text_label: Label
var _name_row: HBoxContainer
var _name_label: Label
var _dps_label: Label
var _type_label: Label
var _desc_label: Label
var _stats_label: RichTextLabel

# LMB lock: while held, the tooltip parks at top-center and freezes — no
# content updates, no follow-cursor, no hide on hover-exit. Released →
# unlocked and dismissed.
var _current_item: Item = null
var _lmb_held: bool = false
# Increments on every show_* call and on hide_tooltip. The deferred
# resume in _resize_then_show captures the value at call time; if it
# doesn't match when the await resumes, a fresh show or a hide came in
# during the layout pass — bail rather than override the new intent.
var _show_token: int = 0
var _park_tween: Tween
# 3D node currently providing the tooltip. While set, the tooltip tracks the
# target's screen-space position each frame instead of following the mouse.
# UI sources (item slots, talent nodes) leave this null and use mouse-follow.
var _anchor_target: Node3D = null
# Snapshot of the anchor at LMB-press time. Drives the bright-red highlight
# and persists even if the cursor drifts off the target before release.
var _locked_target: Node = null

func _ready() -> void:
	add_to_group(&"interactable_tooltip")
	mouse_filter = MOUSE_FILTER_IGNORE
	top_level = true
	visible = false
	size = Vector2.ZERO
	_build_ui()
	_apply_theme()
	UIThemeState.changed.connect(_apply_theme)

func _process(_dt: float) -> void:
	# Anchor was freed (level reset, pool release, queue_free) — drop the
	# stale tooltip rather than leaving it pinned to a dead node. Without
	# this the exit-pad tooltip persists across NG+ because the pad's
	# mouse_exited never fires when the body is removed from the tree.
	if _anchor_target != null and not is_instance_valid(_anchor_target):
		_anchor_target = null
		hide_tooltip()
		return
	if _anchor_target == null:
		return
	if not visible or _lmb_held:
		return
	_reposition_to_anchor()

func _build_ui() -> void:
	_bg = PanelContainer.new()
	_bg.mouse_filter = MOUSE_FILTER_IGNORE
	# Prevent stretching to parent — size from content only.
	_bg.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	add_child(_bg)

	_vbox = VBoxContainer.new()
	_vbox.custom_minimum_size = Vector2(CONTENT_MIN_WIDTH, 0.0)
	_vbox.add_theme_constant_override(&"separation", 3)
	_vbox.mouse_filter = MOUSE_FILTER_IGNORE
	_bg.add_child(_vbox)

	_text_label = Label.new()
	_text_label.theme_type_variation = &"SmallLabel"
	_text_label.add_theme_font_size_override(&"font_size", 8)
	_text_label.mouse_filter = MOUSE_FILTER_IGNORE
	_vbox.add_child(_text_label)

	_name_row = HBoxContainer.new()
	_name_row.mouse_filter = MOUSE_FILTER_IGNORE
	_name_row.add_theme_constant_override(&"separation", 6)
	_vbox.add_child(_name_row)

	_name_label = Label.new()
	_name_label.theme_type_variation = &"BodyLabel"
	_name_label.add_theme_font_size_override(&"font_size", 10)
	_name_label.mouse_filter = MOUSE_FILTER_IGNORE
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.custom_minimum_size = Vector2(80.0, 0.0)
	_name_row.add_child(_name_label)

	_dps_label = Label.new()
	_dps_label.theme_type_variation = &"BodyLabel"
	_dps_label.add_theme_font_size_override(&"font_size", 9)
	_dps_label.add_theme_color_override(&"font_color", Color(1.0, 0.9, 0.5, 1.0))
	_dps_label.mouse_filter = MOUSE_FILTER_IGNORE
	_dps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dps_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_name_row.add_child(_dps_label)

	_type_label = Label.new()
	_type_label.theme_type_variation = &"SmallLabel"
	_type_label.add_theme_font_size_override(&"font_size", 7)
	_type_label.mouse_filter = MOUSE_FILTER_IGNORE
	_vbox.add_child(_type_label)

	_desc_label = Label.new()
	_desc_label.theme_type_variation = &"SmallLabel"
	_desc_label.add_theme_font_size_override(&"font_size", 7)
	# Tighten line spacing — default (3) leaves too much vertical air
	# in multi-line tooltips, especially the buff-bar tooltips with
	# bullet lists. Down to 0 reads compact without the bullets
	# touching descenders.
	_desc_label.add_theme_constant_override(&"line_spacing", 0)
	_desc_label.mouse_filter = MOUSE_FILTER_IGNORE
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Pin the wrap width up-front. Without this, autowrap labels report
	# minimum_size as the unwrapped natural width on first layout, which
	# the PanelContainer then allocates — and the second pass that would
	# measure wrapped height never fires before the tooltip is shown.
	# Result: a panel sized for the longest line rendered as a vertical
	# stack of wrapped lines, leaving huge empty space below.
	_desc_label.custom_minimum_size = Vector2(CONTENT_MIN_WIDTH, 0.0)
	_vbox.add_child(_desc_label)

	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.scroll_active = false
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_stats_label.add_theme_font_size_override(&"normal_font_size", 7)
	_stats_label.add_theme_font_size_override(&"bold_font_size", 7)
	_stats_label.add_theme_constant_override(&"line_separation", 0)
	_stats_label.mouse_filter = MOUSE_FILTER_IGNORE
	_stats_label.custom_minimum_size = Vector2(CONTENT_MIN_WIDTH, 0.0)
	_vbox.add_child(_stats_label)

func _apply_theme() -> void:
	var p: UIThemeConfig = UIThemeState.palette
	if p == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = p.panel_bg
	style.border_color = p.panel_border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.content_margin_left = PADDING_X
	style.content_margin_right = PADDING_X
	style.content_margin_top = PADDING_Y
	style.content_margin_bottom = PADDING_Y
	_bg.add_theme_stylebox_override(&"panel", style)
	_text_label.add_theme_color_override(&"font_color", p.text)
	_type_label.add_theme_color_override(&"font_color", Color(p.text, 0.55))
	_stats_label.add_theme_color_override(&"default_color", p.text)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Only park when clicking on an enemy. Interactables (doors,
				# switches, crates) shouldn't lock the tooltip — clicking them
				# triggers an action, not a sustained inspection.
				if not _lmb_held and visible and _anchor_target != null \
						and _anchor_target.is_in_group(&"enemies"):
					_lmb_held = true
					_park_to_top_center()
					_lock_target()
			else:
				if _lmb_held:
					_lmb_held = false
					_kill_park_tween()
					_dismiss()
					_release_target()
		return
	if visible and not _lmb_held and _anchor_target == null and event is InputEventMouseMotion:
		_reposition((event as InputEventMouseMotion).position)

func _park_to_top_center() -> void:
	_kill_park_tween()
	var vp_size := get_viewport().get_visible_rect().size
	var target := Vector2((vp_size.x - _bg.size.x) * 0.5, PARK_TOP_MARGIN)
	_park_tween = create_tween()
	_park_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_park_tween.tween_property(self, "position", target, PARK_DURATION)

func _kill_park_tween() -> void:
	if _park_tween != null and _park_tween.is_valid():
		_park_tween.kill()
	_park_tween = null

func _lock_target() -> void:
	_locked_target = null
	for n in get_tree().get_nodes_in_group(&"tooltip_target"):
		if is_instance_valid(n):
			_locked_target = n
			break
	if _locked_target != null and _locked_target.has_method(&"set_tooltip_locked"):
		_locked_target.set_tooltip_locked(true)

func _release_target() -> void:
	if _locked_target != null and is_instance_valid(_locked_target) \
			and _locked_target.has_method(&"set_tooltip_locked"):
		_locked_target.set_tooltip_locked(false)
	_locked_target = null

func _dismiss() -> void:
	visible = false

func _show_now() -> void:
	visible = true

func _reposition(mouse: Vector2) -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var pos := mouse + MOUSE_OFFSET
	pos.x = minf(pos.x, vp_size.x - _bg.size.x - SCREEN_MARGIN.x)
	pos.y = minf(pos.y, vp_size.y - _bg.size.y - SCREEN_MARGIN.y)
	position = pos

func _reposition_to_anchor() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Project the target's world position onto the screen, then center the
	# tooltip horizontally above it. Clamp inside the viewport so it never
	# slides off-screen when the target is near an edge.
	var screen_pos := cam.unproject_position(_anchor_target.global_position)
	var pos := Vector2(screen_pos.x - _bg.size.x * 0.5, screen_pos.y - _bg.size.y + ANCHOR_OFFSET_Y)
	var vp_size := get_viewport().get_visible_rect().size
	pos.x = clampf(pos.x, SCREEN_MARGIN.x, vp_size.x - _bg.size.x - SCREEN_MARGIN.x)
	pos.y = clampf(pos.y, SCREEN_MARGIN.y, vp_size.y - _bg.size.y - SCREEN_MARGIN.y)
	position = pos

# A 3D source adds itself to "tooltip_target" before calling show_*. UI sources
# don't, so the tooltip falls back to mouse-follow.
func _pick_anchor_target() -> Node3D:
	for n in get_tree().get_nodes_in_group(&"tooltip_target"):
		if is_instance_valid(n) and n is Node3D:
			return n
	return null

func show_text(text: String) -> void:
	if _lmb_held:
		return
	if text.is_empty():
		hide_tooltip()
		return
	_text_label.text = text
	_text_label.visible = true
	_name_row.visible = false
	_type_label.visible = false
	_desc_label.visible = false
	_stats_label.visible = false
	_resize_then_show()

func show_item(item: Item) -> void:
	if _lmb_held:
		return
	if item == null:
		hide_tooltip()
		return
	_current_item = item
	_text_label.visible = false

	_name_label.text = item.name_key
	_name_label.add_theme_color_override(&"font_color", _rarity_color(item.rarity))
	_name_row.visible = true

	# DPS in the top-right corner of the name row.
	var dps_text := _compute_dps_text(item)
	_dps_label.text = dps_text
	_dps_label.visible = not dps_text.is_empty()

	var type_text := _build_type_text(item)
	_type_label.text = type_text
	_type_label.visible = not type_text.is_empty()

	var has_desc := item.description_key != ""
	_desc_label.text = item.description_key
	_desc_label.visible = has_desc

	# Inline comparison: look up the equipped item in the same slot and
	# pass it through so each stat row can show a colored arrow + old value.
	var equipped: Item = null
	if item.kind != &"":
		var eq := InventoryState.get_equipped(item.kind)
		if eq != null and eq != item:
			equipped = eq
	var stats := _build_stats_text(item, equipped)
	_stats_label.text = stats
	_stats_label.visible = not stats.is_empty()

	_resize_then_show()

func show_skill(skill: Skill, source: Item) -> void:
	if _lmb_held:
		return
	if skill == null:
		hide_tooltip()
		return
	_text_label.visible = false
	_name_label.text = skill.display_name
	_name_label.add_theme_color_override(&"font_color", skill.icon_color)
	_dps_label.visible = false
	_name_row.visible = true
	_type_label.visible = false
	_desc_label.visible = false
	var stats := _build_skill_stats_text(skill, source)
	_stats_label.text = stats
	_stats_label.visible = not stats.is_empty()
	_resize_then_show()


func show_talent_node(title: String, body: String) -> void:
	if _lmb_held:
		return
	_text_label.visible = false
	_name_label.text = title
	_name_label.add_theme_color_override(&"font_color", Color(0.95, 0.95, 0.95, 1.0))
	_dps_label.visible = false
	_name_row.visible = true
	_type_label.visible = false
	_desc_label.text = body
	_desc_label.visible = true
	_stats_label.visible = false
	_resize_then_show()


# Common tail for every show_* path. Reset the panel size so it tracks
# the new content, then wait one frame for the container layout pass
# to settle before reading _bg.size for positioning. Without the await
# the FIRST show after boot reads the default-allocated panel size
# (essentially full viewport, since reset_size queued but didn't apply
# this frame), producing an enormous empty frame stretched along the
# screen edge for one frame. Keeping visibility off across the await
# means the user never sees the wrong-size flash.
func _resize_then_show() -> void:
	_show_token += 1
	var token := _show_token
	visible = false
	# Collapse first so a previous show's larger size can't survive.
	# Then assign size from the live combined_minimum_size after each
	# frame's layout pass — two passes covers the autowrap iterative
	# settle even with the labels' custom_minimum_size pinning the
	# wrap width up-front.
	_bg.size = Vector2.ZERO
	await get_tree().process_frame
	if not is_inside_tree() or _lmb_held or token != _show_token:
		return
	_bg.size = _bg.get_combined_minimum_size()
	await get_tree().process_frame
	if not is_inside_tree() or _lmb_held or token != _show_token:
		return
	_bg.size = _bg.get_combined_minimum_size()
	_show_now()
	_position_for_current_source()

func hide_tooltip() -> void:
	if _lmb_held:
		return
	_show_token += 1
	_current_item = null
	_dismiss()
	_anchor_target = null

# Pick the anchor (if a 3D source is currently hovered) and place the tooltip
# accordingly. Called immediately after content/size update so the first frame
# is already in the right position — _process keeps it tracking from there.
func _position_for_current_source() -> void:
	_anchor_target = _pick_anchor_target()
	if _anchor_target != null:
		_reposition_to_anchor()
	else:
		_reposition(get_viewport().get_mouse_position())

func _rarity_color(rarity: StringName) -> Color:
	match rarity:
		&"magic":
			return Color(0.55, 0.75, 1.0, 1.0)
		&"rare":
			return Color(1.0, 0.85, 0.35, 1.0)
		&"unique":
			return Color(1.0, 0.6, 0.2, 1.0)
	return Color(0.95, 0.95, 0.95, 1.0)

func _build_type_text(item: Item) -> String:
	if item.main_type.is_empty():
		return ""
	if item.sub_type.is_empty():
		return item.main_type
	return "%s - %s" % [item.main_type, item.sub_type]

func _compute_dps_text(item: Item) -> String:
	if item.damage_max <= 0 or item.attack_speed <= 0.0:
		return ""
	var avg_dmg := float(item.effective_damage_min() + item.effective_damage_max()) * 0.5
	var dps := avg_dmg * item.effective_attack_speed()
	return "DPS %.1f" % dps

func _build_stats_text(item: Item, equipped: Item = null) -> String:
	var lines: Array[String] = []
	# ilvl header — shown for every item so the player can tell at a glance
	# how outdated/overleveled a drop is. Decimal formatting on the multiplier
	# so 1.0 reads as "100%" cleanly.
	var mult: float = item.effective_multiplier()
	var pct: int = int(round(mult * 100.0))
	if pct == 100:
		lines.append("Item Level: %d" % item.item_level)
	else:
		lines.append("Item Level: %d (%d%% effective)" % [item.item_level, pct])
	# Active offhand stats — shield pool, reduction, cooldown, duration.
	if item.fire_skill != null and item.fire_skill.active_kind != Skill.ActiveKind.NONE:
		var sk: Skill = item.fire_skill
		var bonus: int = item.get_effective_modifier(&"shield_pool_bonus")
		var pool_total: int = sk.shield_pool + bonus
		match sk.active_kind:
			Skill.ActiveKind.SHIELD_BUFF:
				lines.append("Damage Reduction: %.1f%%" % (sk.damage_reduction * 100.0))
				lines.append("Shield Pool: %d" % pool_total)
				lines.append("Duration: %ds" % int(round(sk.duration)))
				lines.append("Cooldown on Break: %.1fs" % sk.cooldown)
			Skill.ActiveKind.SHIELD_HOLD:
				lines.append("Damage Block: 100%")
				lines.append("Shield Pool: %d" % pool_total)
				lines.append("Cooldown on Break: %.1fs" % sk.cooldown)
			Skill.ActiveKind.GRENADE:
				var radius := item.blast_radius if item.blast_radius > 0.0 else sk.blast_radius
				lines.append("Blast Radius: %.1f m" % radius)
				lines.append("Cooldown: %.1fs" % sk.cooldown)
				if sk.resource_cost > 0:
					lines.append("Resource Cost: %d" % sk.resource_cost)
	# Weapon / combat stats with inline comparison arrows when equipped != null.
	if item.damage_max > 0:
		var line := "Damage: %d–%d" % [item.effective_damage_min(), item.effective_damage_max()]
		if equipped != null and equipped.damage_max > 0:
			var new_avg := float(item.effective_damage_min() + item.effective_damage_max()) * 0.5
			var old_avg := float(equipped.effective_damage_min() + equipped.effective_damage_max()) * 0.5
			line += " %s %d–%d" % [_compare_arrow(new_avg, old_avg), equipped.effective_damage_min(), equipped.effective_damage_max()]
		lines.append(line)
	if item.attack_speed != 1.0:
		var line := "Speed: %.2f" % item.effective_attack_speed()
		if equipped != null and equipped.attack_speed != 1.0:
			var new_spd := item.effective_attack_speed()
			var old_spd := equipped.effective_attack_speed()
			if not is_equal_approx(new_spd, old_spd):
				line += " %s %.2f" % [_compare_arrow(new_spd, old_spd), old_spd]
		lines.append(line)
	if item.crit_chance > 0.0:
		var line := "Crit: %.1f%%" % (item.effective_crit_chance() * 100.0)
		if equipped != null and equipped.crit_chance > 0.0:
			var new_c := item.effective_crit_chance() * 100.0
			var old_c := equipped.effective_crit_chance() * 100.0
			if not is_equal_approx(new_c, old_c):
				line += " %s %.1f%%" % [_compare_arrow(new_c, old_c), old_c]
		lines.append(line)
	if item.accuracy != 1.0:
		var line := "Accuracy: %.1f%%" % (item.effective_accuracy() * 100.0)
		if equipped != null and equipped.accuracy != 1.0:
			var new_a := item.effective_accuracy() * 100.0
			var old_a := equipped.effective_accuracy() * 100.0
			if not is_equal_approx(new_a, old_a):
				line += " %s %.1f%%" % [_compare_arrow(new_a, old_a), old_a]
		lines.append(line)
	if item.weapon_range > 0.0 and item.damage_max > 0:
		var line := "Range: %.1f m" % item.weapon_range
		if equipped != null and equipped.weapon_range > 0.0 and equipped.damage_max > 0:
			if not is_equal_approx(item.weapon_range, equipped.weapon_range):
				line += " %s %.1f m" % [_compare_arrow(item.weapon_range, equipped.weapon_range), equipped.weapon_range]
		lines.append(line)
	# Head light mod
	if item.light_mod != Item.LightMod.NONE:
		var mod_name := "Light"
		match item.light_mod:
			Item.LightMod.FLASHLIGHT: mod_name = "Flashlight"
			Item.LightMod.RADIANT: mod_name = "Radiant Lamp"
			Item.LightMod.SCANNER: mod_name = "Scanner"
			Item.LightMod.UV: mod_name = "UV Lamp"
		lines.append("Mod: %s" % mod_name)
	# Container — shown via raw modifier because inventory capacity is a
	# storage stat, not a power stat, and shouldn't shrink with player level.
	var inv_bonus := item.get_modifier(&"inventory_bonus")
	if item.kind == &"backpack" and inv_bonus > 0:
		var line := "+%d %s" % [inv_bonus, tr("ITEM_STATS_INVENTORY_BONUS")]
		if equipped != null:
			var old_inv := equipped.get_modifier(&"inventory_bonus")
			if old_inv != inv_bonus:
				line += " %s %d" % [_compare_arrow(float(inv_bonus), float(old_inv)), old_inv]
		lines.append(line)
	# Generic stat modifiers with inline comparison. Union of both items'
	# keys so stats the hovered item lacks but the equipped one has still
	# show (as a loss). Power stats display as effective (post-scaling).
	var all_stat_ids: Dictionary = {}
	for stat_id: StringName in item.stat_modifiers:
		all_stat_ids[stat_id] = true
	if equipped != null:
		for stat_id: StringName in equipped.stat_modifiers:
			all_stat_ids[stat_id] = true
	for stat_id: StringName in all_stat_ids:
		if stat_id == &"inventory_bonus" and item.kind == &"backpack":
			continue
		var raw_new: int = int(item.stat_modifiers.get(stat_id, 0))
		var raw_old: int = int(equipped.stat_modifiers.get(stat_id, 0)) if equipped != null else 0
		if raw_new == 0 and raw_old == 0:
			continue
		var label := _stat_display_name(stat_id)
		if stat_id in _PCT_STATS:
			var amt_f: float = item.get_effective_modifier_float(stat_id) if raw_new != 0 else 0.0
			var old_f: float = equipped.get_effective_modifier_float(stat_id) if equipped != null and raw_old != 0 else 0.0
			var sign_f: String = "+" if amt_f > 0.0 else ""
			var line := "%s%.1f%% %s" % [sign_f, amt_f, label]
			if equipped != null and not is_equal_approx(amt_f, old_f):
				var old_sign: String = "+" if old_f > 0.0 else ""
				line += " %s %s%.1f%%" % [_compare_arrow(amt_f, old_f, stat_id), old_sign, old_f]
			lines.append(line)
		else:
			var amount: int = item.get_effective_modifier(stat_id) if raw_new != 0 else 0
			var old_amount: int = equipped.get_effective_modifier(stat_id) if equipped != null and raw_old != 0 else 0
			var sign := "+" if amount > 0 else ""
			var line := "%s%d %s" % [sign, amount, label]
			if equipped != null and amount != old_amount:
				var old_sign := "+" if old_amount > 0 else ""
				line += " %s %s%d" % [_compare_arrow(float(amount), float(old_amount), stat_id), old_sign, old_amount]
			lines.append(line)
	return "\n".join(lines)


## Returns a BBCode-colored arrow: green ▲ for better, red ▼ for worse,
## grey = for equal. "Better" depends on the stat — damage_reduction going
## up is good, but most stats follow the "higher = better" rule.
func _compare_arrow(new_val: float, old_val: float, _stat_id: StringName = &"") -> String:
	if new_val > old_val:
		return "[color=%s]▲[/color]" % COMPARE_BETTER_COLOR
	elif new_val < old_val:
		return "[color=%s]▼[/color]" % COMPARE_WORSE_COLOR
	return "[color=%s]=[/color]" % COMPARE_NEUTRAL_COLOR


# Stat keys that should render as percentages (with the tenths suffix per
# the "marginal upgrades visible" rule). Anything not in this set is
# rendered as a flat integer. New affixes that produce a percentage
# bonus must be added here, otherwise their tooltip line drops the %.
const _PCT_STATS: Dictionary = {
	&"damage_reduction": true,
	&"crit_chance_bonus": true,
	&"crit_damage_bonus": true,
	&"attack_speed_bonus": true,
	&"hit_chance_bonus": true,
	&"cooldown_reduction": true,
	&"electric_resistance": true,
	&"cryo_resistance": true,
	&"toxic_resistance": true,
	&"elemental_resistance": true,
	&"resource_cost_reduction": true,
	&"lifesteal_percent": true,
	&"armor_penetration": true,
	&"damage_bonus_pct": true,
	&"hp_regen_bonus": true,
}

const _STAT_LABELS: Dictionary = {
	&"max_health_bonus": "Max Health",
	&"max_resource_bonus": "Max Resource",
	&"damage_reduction": "Damage Reduction",
	&"move_speed_bonus": "Move Speed",
	&"base_damage_bonus": "Base Damage",
	&"crit_chance_bonus": "Crit Chance",
	&"crit_damage_bonus": "Crit Damage",
	&"attack_speed_bonus": "Attack Speed",
	&"hit_chance_bonus": "Hit Chance",
	&"cooldown_reduction": "Cooldown Reduction",
	&"fire_damage_bonus": "Fire Damage",
	&"cryo_damage_bonus": "Cryo Damage",
	&"electric_damage_bonus": "Electric Damage",
	&"toxic_damage_bonus": "Toxic Damage",
	&"electric_resistance": "Electric Resistance",
	&"cryo_resistance": "Cryo Resistance",
	&"toxic_resistance": "Toxic Resistance",
	&"elemental_resistance": "Elemental Resistance",
	&"carry_capacity_bonus": "Carry Capacity",
	&"inventory_bonus": "Inventory Slots",
	&"range_bonus": "Range",
	&"knockback_bonus": "Knockback",
	&"traction_bonus": "Traction",
	&"hp_regen_bonus": "HP Regen / sec",
	&"regen_delay_reduction": "Regen Delay Reduction",
	&"resource_cost_reduction": "Resource Cost Reduction",
	&"lifesteal_percent": "Life Steal",
	&"armor_penetration": "Armor Penetration",
	&"blast_radius_bonus": "Blast Radius",
	&"damage_bonus_pct": "Damage",
	&"resource_on_hit": "Resource On Hit",
}

func _stat_display_name(stat_id: StringName) -> String:
	return _STAT_LABELS.get(stat_id, (stat_id as String).capitalize())


func _build_skill_stats_text(skill: Skill, source: Item) -> String:
	var lines: Array[String] = []
	match skill.active_kind:
		Skill.ActiveKind.SHIELD_HOLD:
			var bonus: int = source.get_effective_modifier(&"shield_pool_bonus") if source != null else 0
			lines.append("Damage Block: 100%")
			lines.append("Shield Pool: %d" % (skill.shield_pool + bonus))
			lines.append("Cooldown on Break: %.1fs" % skill.cooldown)
		Skill.ActiveKind.SHIELD_BUFF:
			var bonus: int = source.get_effective_modifier(&"shield_pool_bonus") if source != null else 0
			lines.append("Damage Reduction: %.1f%%" % (skill.damage_reduction * 100.0))
			lines.append("Shield Pool: %d" % (skill.shield_pool + bonus))
			lines.append("Duration: %ds" % int(round(skill.duration)))
			lines.append("Cooldown on Break: %.1fs" % skill.cooldown)
		Skill.ActiveKind.GRENADE:
			if source != null and source.damage_max > 0:
				lines.append("Damage: %d–%d" % [source.effective_damage_min(), source.effective_damage_max()])
			elif skill.damage > 0:
				lines.append("Damage: %d" % skill.damage)
			var radius := source.blast_radius if source != null and source.blast_radius > 0.0 else skill.blast_radius
			lines.append("Blast Radius: %.1f m" % radius)
			if source != null and source.crit_chance > 0.0:
				lines.append("Crit: %.1f%%" % (source.effective_crit_chance() * 100.0))
			if skill.knockback > 0.0:
				lines.append("Knockback: %.1f" % skill.knockback)
			lines.append("Cooldown: %.1fs" % skill.cooldown)
			if skill.resource_cost > 0:
				lines.append("Resource Cost: %d" % skill.resource_cost)
			match skill.grenade_type:
				Skill.GrenadeType.FRAG:
					lines.append("[color=#ff8844]Frag: standard explosion[/color]")
				Skill.GrenadeType.INCENDIARY:
					lines.append("[color=#ff4422]Incendiary: bonus burn damage[/color]")
				Skill.GrenadeType.CLUSTER:
					lines.append("[color=#bb88ff]Cluster: splits into 3 sub-grenades[/color]")
				Skill.GrenadeType.STUN:
					lines.append("[color=#88aaff]Stun: staggers enemies[/color]")
		_:
			# Standard weapon skill (cone, aoe, projectile, hitscan).
			if source != null and source.damage_max > 0:
				lines.append("Damage: %d–%d" % [source.effective_damage_min(), source.effective_damage_max()])
			elif skill.damage > 0:
				lines.append("Damage: %d" % skill.damage)
			if source != null and source.attack_speed != 1.0:
				lines.append("Speed: %.2f" % source.effective_attack_speed())
			if source != null and source.crit_chance > 0.0:
				lines.append("Crit: %.1f%%" % (source.effective_crit_chance() * 100.0))
			if source != null and source.accuracy < 1.0:
				lines.append("Accuracy: %.1f%%" % (source.effective_accuracy() * 100.0))
			var eff_range := source.weapon_range if source != null and source.weapon_range > 0.0 else skill.skill_range
			if eff_range > 0.0:
				lines.append("Range: %.1f m" % eff_range)
			if skill.cooldown > 0.0:
				lines.append("Cooldown: %.1fs" % skill.cooldown)
			if skill.resource_cost > 0:
				lines.append("Resource Cost: %d" % skill.resource_cost)
			match skill.targeting_mode:
				Skill.TargetingMode.SINGLE_CONE:
					lines.append("Targeting: Cone %d°" % int(skill.cone_deg))
				Skill.TargetingMode.AOE_RADIAL:
					lines.append("Targeting: AoE Radial")
				Skill.TargetingMode.PROJECTILE:
					lines.append("Targeting: Projectile")
				Skill.TargetingMode.HITSCAN:
					lines.append("Targeting: Hitscan")
	return "\n".join(lines)
