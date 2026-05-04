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

# Stat lines in the tooltip render in their identity color
# (AttributeState.STAT_COLORS) so a stat reads the SAME everywhere it
# appears — character panel, talents panel, HUD tier badges. The
# previous tooltip path used relationship colors (good/bad-for-player
# tinting) which made Orthodoxy look red on a Cyborg even though it's
# cream on the character sheet. Relationship signal can come back as
# a separate icon / +/- background later.

var _bg: PanelContainer
var _vbox: VBoxContainer
var _text_label: Label
var _name_label: Label
var _type_label: Label
var _desc_label: Label
var _stats_label: RichTextLabel

# LMB lock: while held, the tooltip parks at top-center and freezes — no
# content updates, no follow-cursor, no hide on hover-exit. Released →
# unlocked and dismissed.
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

	_name_label = Label.new()
	_name_label.theme_type_variation = &"BodyLabel"
	_name_label.add_theme_font_size_override(&"font_size", 10)
	_name_label.mouse_filter = MOUSE_FILTER_IGNORE
	_vbox.add_child(_name_label)

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
	_name_label.visible = false
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
	_text_label.visible = false

	_name_label.text = item.name_key
	_name_label.add_theme_color_override(&"font_color", _rarity_color(item.rarity))
	_name_label.visible = true

	var type_text := _build_type_text(item)
	_type_label.text = type_text
	_type_label.visible = not type_text.is_empty()

	var has_desc := item.description_key != ""
	_desc_label.text = item.description_key
	_desc_label.visible = has_desc

	var stats := _build_stats_text(item)
	_stats_label.text = stats
	_stats_label.visible = not stats.is_empty()

	_resize_then_show()

func show_talent_node(title: String, body: String) -> void:
	if _lmb_held:
		return
	_text_label.visible = false
	_name_label.text = title
	_name_label.add_theme_color_override(&"font_color", Color(0.95, 0.95, 0.95, 1.0))
	_name_label.visible = true
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

func _build_stats_text(item: Item) -> String:
	var lines: Array[String] = []
	# Active offhand stats — shield pool, reduction, cooldown, duration.
	# Different fields are relevant per active_kind so each archetype
	# gets its own line set; common lines (cooldown, pool) aren't
	# shared because the fixed-format pattern reads cleaner per item
	# than a shared header. Pool reads include the offhand's
	# shield_pool_bonus so the tooltip matches the in-game pool the
	# player will actually see.
	if item.fire_skill != null and item.fire_skill.active_kind != Skill.ActiveKind.NONE:
		var sk: Skill = item.fire_skill
		var bonus: int = item.get_modifier(&"shield_pool_bonus")
		var pool_total: int = sk.shield_pool + bonus
		match sk.active_kind:
			Skill.ActiveKind.SHIELD_BUFF:
				lines.append("Damage Reduction: %d%%" % int(round(sk.damage_reduction * 100.0)))
				lines.append("Shield Pool: %d" % pool_total)
				lines.append("Duration: %ds" % int(round(sk.duration)))
				lines.append("Cooldown on Break: %.1fs" % sk.cooldown)
			Skill.ActiveKind.SHIELD_HOLD:
				lines.append("Damage Block: 100%")
				lines.append("Shield Pool: %d" % pool_total)
				lines.append("Cooldown on Break: %.1fs" % sk.cooldown)
			Skill.ActiveKind.GRENADE:
				lines.append("Damage: %d" % sk.damage)
				lines.append("Range: %.1f m" % sk.skill_range)
				lines.append("Cooldown: %.1fs" % sk.cooldown)
	# Weapon / combat stats
	if item.damage_max > 0:
		lines.append("Damage: %d–%d" % [item.damage_min, item.damage_max])
	if item.attack_speed != 1.0:
		lines.append("Speed: %.2f" % item.attack_speed)
	if item.crit_chance > 0.0:
		lines.append("Crit: %d%%" % int(item.crit_chance * 100))
	if item.accuracy != 1.0:
		lines.append("Accuracy: %d%%" % int(item.accuracy * 100))
	if item.weapon_range > 0.0 and item.damage_max > 0:
		lines.append("Range: %.1f m" % item.weapon_range)
	if item.two_handed:
		lines.append("Two-Handed")
	# Recon (light sources)
	if item.kind == &"recon":
		lines.append("%s: %d m" % [tr("ITEM_STATS_LIGHT_RANGE"), int(item.light_range)])
		lines.append("%s: %d" % [tr("ITEM_STATS_LIGHT_ENERGY"), int(item.light_energy)])
	# Container / belt
	var inv_bonus := item.get_modifier(&"inventory_bonus")
	if item.kind == &"backpack" and inv_bonus > 0:
		lines.append("+%d %s" % [inv_bonus, tr("ITEM_STATS_INVENTORY_BONUS")])
	if item.kind == &"belt" and item.utility_slots > 0:
		lines.append("+%d %s" % [item.utility_slots, tr("ITEM_STATS_UTILITY_SLOTS")])
	# Attribute modifiers — only the rollable class stats render here. The
	# other keys in stat_modifiers (inventory_bonus, damage_reduction,
	# fire_damage_bonus, etc.) are non-stat modifiers; each gets its own
	# display rule above (or none yet, if the system that consumes them
	# isn't shipped). Letting them through this loop produces wrong colours
	# (relationship lookup falls through to "opposing") and ugly labels.
	for stat_id: StringName in item.stat_modifiers:
		if not stat_id in AttributeState.ROLLABLE_STATS:
			continue
		var amount: int = int(item.stat_modifiers[stat_id])
		var color: Color = AttributeState.STAT_COLORS.get(stat_id, Color.WHITE)
		var hex := "#%s" % color.to_html(false)
		var label := _stat_display_name(stat_id)
		lines.append("[color=%s]+%d %s[/color]" % [hex, amount, label])
	return "\n".join(lines)

func _stat_display_name(stat_id: StringName) -> String:
	var key: StringName = AttributeState.STAT_I18N.get(stat_id, &"")
	return tr(key) if key != &"" else (stat_id as String).capitalize()
