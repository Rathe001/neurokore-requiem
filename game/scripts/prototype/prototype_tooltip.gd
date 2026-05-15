class_name PrototypeTooltip
extends Control

const SCREEN_MARGIN := Vector2(12, 12)
const MOUSE_OFFSET := Vector2(14.0, 14.0)
const PADDING_X := 8
const PADDING_Y := 6
const CONTENT_MIN_WIDTH := 140.0
const TOP_MARGIN := 24.0
const PANEL_GAP := 8
# Border color when LMB-locked on an enemy. Picked to read against every
# class palette's panel_bg without theme coupling.
const LOCK_BORDER_COLOR := Color(1.0, 0.85, 0.2, 1.0)

const COMPARE_BETTER_COLOR := "#66cc66"
const COMPARE_WORSE_COLOR := "#cc5555"
const COMPARE_NEUTRAL_COLOR := "#999999"

var _h_layout: HBoxContainer
var _bg: PanelContainer
var _vbox: VBoxContainer
var _text_label: Label
var _name_row: HBoxContainer
var _name_label: Label
var _dps_label: Label
var _quality_label: Label
var _type_label: Label
var _origin_label: Label
var _desc_label: RichTextLabel
var _stats_label: RichTextLabel
var _bg_style: StyleBoxFlat

# Shift-held side-by-side panel: shows the equipped item next to the hovered
# one. Replaces the inline-arrow comparison that used to clutter every stat
# line — only the headline DPS keeps an inline arrow.
var _equipped_bg: PanelContainer
var _equipped_vbox: VBoxContainer
var _equipped_header: Label
var _equipped_name: Label
var _equipped_type: Label
var _equipped_stats: RichTextLabel
var _equipped_style: StyleBoxFlat
var _equipped_meters: WeaponMeterStrip = null
var _equipped_quality_label: Label = null
var _shift_held: bool = false

# LMB lock: while held on an enemy, the tooltip freezes — no content updates,
# no hide on hover-exit, gold border to telegraph the locked state. Released
# → unlocked and dismissed.
var _weapon_meters: WeaponMeterStrip = null
var _current_item: Item = null
var _lmb_held: bool = false
# Increments on every show_* call and on hide_tooltip. The deferred resume
# in _resize_then_show captures the value at call time; if it doesn't match
# when the await resumes, a fresh show or a hide came in during the layout
# pass — bail rather than override the new intent.
var _show_token: int = 0
# 3D node currently providing the tooltip. While set, the tooltip stays
# pinned to top-center so it never obscures the action under the camera.
# UI sources (item slots, talent nodes) leave this null and use mouse-follow.
var _anchor_target: Node3D = null
# Snapshot of the anchor at LMB-press time. Drives the bright-red highlight
# on the locked enemy and persists even if the cursor drifts off the target
# before release.
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
	# Anchor freed (level reset, pool release, queue_free) — drop the stale
	# tooltip rather than leaving it pinned to a dead node. Without this the
	# exit-pad tooltip persists across NG+ because the pad's mouse_exited
	# never fires when the body is removed from the tree.
	if _anchor_target != null and not is_instance_valid(_anchor_target):
		_anchor_target = null
		hide_tooltip()
		return
	if not visible:
		return
	# While locked, keep repositioning (enemy may move) and periodically
	# ask the locked target to push fresh content so status-effect timers
	# and HP update in real time.
	if _lmb_held:
		# Enemy died while locked — auto-dismiss.
		if _locked_target != null and is_instance_valid(_locked_target) \
				and _locked_target.has_method(&"_is_alive") and not _locked_target._is_alive():
			_lmb_held = false
			_set_lock_border(false)
			_dismiss()
			_release_target()
			return
		if _anchor_target != null:
			_position_at_top()
		if _locked_target != null and is_instance_valid(_locked_target) \
				and _locked_target.has_method(&"refresh_locked_tooltip"):
			_locked_target.refresh_locked_tooltip()
		return
	# Only re-pin 3D-anchored tooltips; UI tooltips track mouse via _input.
	if _anchor_target != null:
		_position_at_top()

func _build_ui() -> void:
	_h_layout = HBoxContainer.new()
	_h_layout.set_anchors_and_offsets_preset(PRESET_TOP_LEFT)
	_h_layout.add_theme_constant_override(&"separation", PANEL_GAP)
	_h_layout.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_h_layout)

	_bg = PanelContainer.new()
	_bg.mouse_filter = MOUSE_FILTER_IGNORE
	_h_layout.add_child(_bg)

	_vbox = VBoxContainer.new()
	_vbox.custom_minimum_size = Vector2(CONTENT_MIN_WIDTH, 0.0)
	_vbox.add_theme_constant_override(&"separation", 1)
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
	_name_label.add_theme_font_size_override(&"font_size", 8)
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

	_quality_label = Label.new()
	_quality_label.theme_type_variation = &"BodyLabel"
	_quality_label.add_theme_font_size_override(&"font_size", 8)
	_quality_label.mouse_filter = MOUSE_FILTER_IGNORE
	_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_quality_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_quality_label.visible = false
	_name_row.add_child(_quality_label)

	_type_label = Label.new()
	_type_label.theme_type_variation = &"SmallLabel"
	_type_label.add_theme_font_size_override(&"font_size", 7)
	_type_label.mouse_filter = MOUSE_FILTER_IGNORE
	_vbox.add_child(_type_label)

	_origin_label = Label.new()
	_origin_label.theme_type_variation = &"SmallLabel"
	_origin_label.add_theme_font_size_override(&"font_size", 7)
	_origin_label.mouse_filter = MOUSE_FILTER_IGNORE
	_origin_label.visible = false
	_vbox.add_child(_origin_label)

	_desc_label = RichTextLabel.new()
	_desc_label.bbcode_enabled = true
	_desc_label.fit_content = true
	_desc_label.scroll_active = false
	_desc_label.add_theme_font_size_override(&"normal_font_size", 7)
	_desc_label.mouse_filter = MOUSE_FILTER_IGNORE
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_label.custom_minimum_size = Vector2(CONTENT_MIN_WIDTH, 0.0)
	_vbox.add_child(_desc_label)

	_weapon_meters = WeaponMeterStrip.new()
	_weapon_meters.mouse_filter = MOUSE_FILTER_IGNORE
	_weapon_meters.visible = false
	_vbox.add_child(_weapon_meters)

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

	# Equipped (right) panel — same layout as the main panel minus the dps
	# row. Hidden by default; only visible when shift is held during item hover.
	_equipped_bg = PanelContainer.new()
	_equipped_bg.mouse_filter = MOUSE_FILTER_IGNORE
	_equipped_bg.visible = false
	_h_layout.add_child(_equipped_bg)

	_equipped_vbox = VBoxContainer.new()
	_equipped_vbox.custom_minimum_size = Vector2(CONTENT_MIN_WIDTH, 0.0)
	_equipped_vbox.add_theme_constant_override(&"separation", 3)
	_equipped_vbox.mouse_filter = MOUSE_FILTER_IGNORE
	_equipped_bg.add_child(_equipped_vbox)

	_equipped_header = Label.new()
	_equipped_header.text = "EQUIPPED"
	_equipped_header.theme_type_variation = &"SmallLabel"
	_equipped_header.add_theme_font_size_override(&"font_size", 7)
	_equipped_header.mouse_filter = MOUSE_FILTER_IGNORE
	_equipped_vbox.add_child(_equipped_header)

	var eq_name_row := HBoxContainer.new()
	eq_name_row.mouse_filter = MOUSE_FILTER_IGNORE
	eq_name_row.add_theme_constant_override(&"separation", 4)
	_equipped_vbox.add_child(eq_name_row)

	_equipped_name = Label.new()
	_equipped_name.theme_type_variation = &"BodyLabel"
	_equipped_name.add_theme_font_size_override(&"font_size", 10)
	_equipped_name.mouse_filter = MOUSE_FILTER_IGNORE
	_equipped_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equipped_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equipped_name.custom_minimum_size = Vector2(80.0, 0.0)
	eq_name_row.add_child(_equipped_name)

	_equipped_quality_label = Label.new()
	_equipped_quality_label.theme_type_variation = &"BodyLabel"
	_equipped_quality_label.add_theme_font_size_override(&"font_size", 8)
	_equipped_quality_label.mouse_filter = MOUSE_FILTER_IGNORE
	_equipped_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_equipped_quality_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_equipped_quality_label.visible = false
	eq_name_row.add_child(_equipped_quality_label)

	_equipped_type = Label.new()
	_equipped_type.theme_type_variation = &"SmallLabel"
	_equipped_type.add_theme_font_size_override(&"font_size", 7)
	_equipped_type.mouse_filter = MOUSE_FILTER_IGNORE
	_equipped_vbox.add_child(_equipped_type)

	_equipped_meters = WeaponMeterStrip.new()
	_equipped_meters.mouse_filter = MOUSE_FILTER_IGNORE
	_equipped_meters.visible = false
	_equipped_vbox.add_child(_equipped_meters)

	_equipped_stats = RichTextLabel.new()
	_equipped_stats.bbcode_enabled = true
	_equipped_stats.fit_content = true
	_equipped_stats.scroll_active = false
	_equipped_stats.autowrap_mode = TextServer.AUTOWRAP_OFF
	_equipped_stats.add_theme_font_size_override(&"normal_font_size", 7)
	_equipped_stats.add_theme_font_size_override(&"bold_font_size", 7)
	_equipped_stats.add_theme_constant_override(&"line_separation", 0)
	_equipped_stats.mouse_filter = MOUSE_FILTER_IGNORE
	_equipped_stats.custom_minimum_size = Vector2(CONTENT_MIN_WIDTH, 0.0)
	_equipped_vbox.add_child(_equipped_stats)

func _apply_theme() -> void:
	var p: UIThemeConfig = UIThemeState.palette
	if p == null:
		return
	var main_border: Color = LOCK_BORDER_COLOR if _lmb_held else p.panel_border
	var main_w: int = 2 if _lmb_held else 1
	_bg_style = _make_style(p.panel_bg, main_border, main_w)
	_bg.add_theme_stylebox_override(&"panel", _bg_style)
	_equipped_style = _make_style(p.panel_bg, p.panel_border, 1)
	_equipped_bg.add_theme_stylebox_override(&"panel", _equipped_style)
	if _weapon_meters:
		_weapon_meters.update_theme()
	if _equipped_meters:
		_equipped_meters.update_theme()
	_text_label.add_theme_color_override(&"font_color", p.text)
	_type_label.add_theme_color_override(&"font_color", Color(p.text, 0.55))
	_stats_label.add_theme_color_override(&"default_color", p.text)
	_equipped_header.add_theme_color_override(&"font_color", Color(p.text, 0.55))
	_equipped_type.add_theme_color_override(&"font_color", Color(p.text, 0.55))
	_equipped_stats.add_theme_color_override(&"default_color", p.text)

func _make_style(bg: Color, border: Color, border_w: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = border_w
	s.border_width_top = border_w
	s.border_width_right = border_w
	s.border_width_bottom = border_w
	s.content_margin_left = PADDING_X
	s.content_margin_right = PADDING_X
	s.content_margin_top = PADDING_Y
	s.content_margin_bottom = PADDING_Y
	return s

# Mutates the existing main-panel stylebox in place — cheaper than rebuilding
# and avoids re-querying the theme palette for the same colors.
func _set_lock_border(locked: bool) -> void:
	if _bg_style == null:
		return
	var p: UIThemeConfig = UIThemeState.palette
	var base: Color = p.panel_border if p != null else Color(0.5, 0.5, 0.5, 1.0)
	_bg_style.border_color = LOCK_BORDER_COLOR if locked else base
	var w: int = 2 if locked else 1
	_bg_style.border_width_left = w
	_bg_style.border_width_top = w
	_bg_style.border_width_right = w
	_bg_style.border_width_bottom = w

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.echo:
			return
		# Cover both keycode (logical) and physical_keycode so left/right
		# shift variants both flip the side-by-side panel.
		if key.keycode == KEY_SHIFT or key.physical_keycode == KEY_SHIFT:
			var was := _shift_held
			_shift_held = key.pressed
			if was != _shift_held and _current_item != null:
				_refresh_meters()
				_refresh_equipped_panel()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Only lock when clicking on an enemy. Interactables (doors,
				# switches, crates) shouldn't lock the tooltip — clicking them
				# triggers an action, not a sustained inspection.
				if not _lmb_held and visible and _anchor_target != null \
						and _anchor_target.is_in_group(&"enemies"):
					_lmb_held = true
					_set_lock_border(true)
					_lock_target()
			else:
				if _lmb_held:
					_lmb_held = false
					_set_lock_border(false)
					_dismiss()
					_release_target()
		return

	# Mouse-follow only for non-anchored (UI) tooltips.
	if visible and not _lmb_held and _anchor_target == null and event is InputEventMouseMotion:
		_reposition((event as InputEventMouseMotion).position)

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
	var compound_size := _h_layout.size
	var pos := mouse + MOUSE_OFFSET
	pos.x = minf(pos.x, vp_size.x - compound_size.x - SCREEN_MARGIN.x)
	pos.y = minf(pos.y, vp_size.y - compound_size.y - SCREEN_MARGIN.y)
	position = pos

# 3D-anchored tooltips always sit at the top-center so they never obscure
# the action area below the camera. The compound width (main + equipped)
# is what we center; clamped to keep the equipped panel on-screen even on
# narrow viewports.
func _position_at_top() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var compound_size := _h_layout.size
	var pos := Vector2((vp_size.x - compound_size.x) * 0.5, TOP_MARGIN)
	pos.x = clampf(pos.x, SCREEN_MARGIN.x, vp_size.x - compound_size.x - SCREEN_MARGIN.x)
	position = pos

# A 3D source adds itself to "tooltip_target" before calling show_*. UI
# sources don't, so the tooltip falls back to mouse-follow.
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
	_current_item = null
	_equipped_bg.visible = false
	_weapon_meters.visible = false
	_text_label.text = text
	_text_label.visible = true
	_name_row.visible = false
	_type_label.visible = false
	_origin_label.visible = false
	_desc_label.visible = false
	_stats_label.visible = false
	_resize_then_show()

func show_item(item: Item) -> void:
	if _lmb_held:
		return
	if item == null:
		hide_tooltip()
		return
	# Sync shift state in case the user was already holding it before hover.
	_shift_held = Input.is_key_pressed(KEY_SHIFT)
	_current_item = item
	_text_label.visible = false

	_name_label.text = item.name_key
	_name_label.add_theme_color_override(&"font_color", _rarity_color(item.rarity))
	_name_row.visible = true
	_dps_label.visible = false
	_update_quality_label(item)

	var type_text := _build_type_text(item)
	_type_label.text = type_text
	_type_label.visible = not type_text.is_empty()

	# Origin restriction — green when met, red when blocked.
	if item.origin_restriction != &"":
		var origin_label: String = (item.origin_restriction as String).capitalize()
		if item.origin_matches_player():
			_origin_label.text = "Origin: %s" % origin_label
			_origin_label.add_theme_color_override(&"font_color", Color(0.4, 0.8, 0.4))
		else:
			_origin_label.text = "Requires %s origin" % origin_label
			_origin_label.add_theme_color_override(&"font_color", Color(0.8, 0.33, 0.33))
		_origin_label.visible = true
	else:
		_origin_label.visible = false

	var has_desc := item.description_key != ""
	_desc_label.text = item.description_key
	_desc_label.visible = has_desc

	# Visual meter bars — replaces numeric stat lines with at-a-glance bars
	# showing where this item's roll sits in its archetype+rarity range.
	_update_meter_bars(item)

	# DPS keeps an inline arrow vs equipped (the headline at-a-glance signal);
	# every other stat shows bare. Shift+hover provides the full comparison.
	var equipped: Item = _resolve_equipped(item)
	var stats := _build_stats_text(item, equipped)
	_stats_label.text = stats
	_stats_label.visible = not stats.is_empty()

	_sync_equipped_panel_visibility()
	_resize_then_show()

func _resolve_equipped(item: Item) -> Item:
	if item == null or item.kind == &"":
		return null
	var eq := InventoryState.get_equipped(item.kind)
	if eq == null or eq == item:
		return null
	return eq

# Update the equipped-panel state to match shift + current item, without
# kicking off a full _resize_then_show. Use this on initial show (visibility
# is part of the same resize pass).
func _sync_equipped_panel_visibility() -> void:
	var equipped: Item = _resolve_equipped(_current_item)
	var should_show := _shift_held and equipped != null
	_equipped_bg.visible = should_show
	if should_show:
		_populate_equipped_panel(equipped)

# Re-filter meter bars on shift toggle — unrolled bars appear only when
# comparing (shift held).
func _refresh_meters() -> void:
	if _current_item == null:
		return
	_update_meter_bars(_current_item)

# Compute + merge meter bars for both hovered and equipped items.
# When Shift is held, both panels show the union of all bar IDs so missing
# stats are visible as empty bars.
func _update_meter_bars(item: Item) -> void:
	var hovered_bars := ItemMeterData.compute(item)
	var equipped: Item = _resolve_equipped(item)
	if _shift_held and equipped != null:
		var eq_bars := ItemMeterData.compute(equipped)
		var merged: Array = ItemMeterData.merge_for_comparison(hovered_bars, eq_bars)
		hovered_bars = merged[0]
		var merged_eq: Array[WeaponMeterData.MeterBar] = []
		for b in merged[1]:
			merged_eq.append(b as WeaponMeterData.MeterBar)
		if not merged_eq.is_empty():
			_equipped_meters.populate(merged_eq)
			_equipped_meters.visible = true
		else:
			_equipped_meters.visible = false
	else:
		# No comparison — hide unrolled (empty) bars
		hovered_bars = hovered_bars.filter(func(b: WeaponMeterData.MeterBar) -> bool: return not b.number_text.is_empty())
	if not hovered_bars.is_empty():
		_weapon_meters.populate(hovered_bars)
		_weapon_meters.visible = true
	else:
		_weapon_meters.visible = false


# Mid-show shift toggle: visibility flip changes compound width, so re-run
# the size/position pipeline.
func _refresh_equipped_panel() -> void:
	var equipped: Item = _resolve_equipped(_current_item)
	var should_show := _shift_held and equipped != null
	if should_show:
		_populate_equipped_panel(equipped)
	_equipped_bg.visible = should_show
	# Always resize — meter bar count or equipped panel may have changed.
	if visible and not _lmb_held:
		_resize_then_show()

func _populate_equipped_panel(item: Item) -> void:
	_equipped_name.text = item.name_key
	_equipped_name.add_theme_color_override(&"font_color", _rarity_color(item.rarity))
	var t := _build_type_text(item)
	_equipped_type.text = t
	_equipped_type.visible = not t.is_empty()
	# Quality % for equipped item
	if _equipped_quality_label != null:
		_update_quality_label(item, _equipped_quality_label)
	# Meter bars populated by _update_meter_bars (merged with hovered)
	_equipped_stats.text = _build_stats_text(item)

func show_skill(skill: Skill, source: Item) -> void:
	if _lmb_held:
		return
	if skill == null:
		hide_tooltip()
		return
	_current_item = null
	_equipped_bg.visible = false
	_weapon_meters.visible = false
	_text_label.visible = false
	_name_label.text = skill.display_name
	_name_label.add_theme_color_override(&"font_color", skill.icon_color)
	_dps_label.visible = false
	_quality_label.visible = false
	_name_row.visible = true
	_type_label.visible = false
	_origin_label.visible = false
	_desc_label.visible = false
	var stats := _build_skill_stats_text(skill, source)
	_stats_label.text = stats
	_stats_label.visible = not stats.is_empty()
	_resize_then_show()


func show_talent_node(title: String, body: String) -> void:
	if _lmb_held:
		# Locked — update text in-place without resize/reposition so the
		# tooltip stays pinned but reflects live HP and status effects.
		_name_label.text = title
		_desc_label.text = body
		return
	_current_item = null
	_equipped_bg.visible = false
	_weapon_meters.visible = false
	_text_label.visible = false
	_name_label.text = title
	_name_label.add_theme_color_override(&"font_color", Color(0.95, 0.95, 0.95, 1.0))
	_dps_label.visible = false
	_quality_label.visible = false
	_name_row.visible = true
	_type_label.visible = false
	_origin_label.visible = false
	_desc_label.text = body
	_desc_label.visible = true
	_stats_label.visible = false
	_resize_then_show()


# Common tail for every show_* path. Reset the panel sizes so they track the
# new content, then wait one frame for the container layout pass to settle
# before reading sizes for positioning. Without the await the FIRST show
# after boot reads the default-allocated panel size (essentially full
# viewport, since reset_size queued but didn't apply this frame), producing
# an enormous empty frame stretched along the screen edge for one frame.
# Keeping visibility off across the await means the user never sees the
# wrong-size flash.
func _resize_then_show() -> void:
	_show_token += 1
	var token := _show_token
	visible = false
	_bg.size = Vector2.ZERO
	_equipped_bg.size = Vector2.ZERO
	_h_layout.size = Vector2.ZERO
	await get_tree().process_frame
	if not is_inside_tree() or _lmb_held or token != _show_token:
		return
	_bg.size = _bg.get_combined_minimum_size()
	if _equipped_bg.visible:
		_equipped_bg.size = _equipped_bg.get_combined_minimum_size()
	_h_layout.size = _h_layout.get_combined_minimum_size()
	await get_tree().process_frame
	if not is_inside_tree() or _lmb_held or token != _show_token:
		return
	_bg.size = _bg.get_combined_minimum_size()
	if _equipped_bg.visible:
		_equipped_bg.size = _equipped_bg.get_combined_minimum_size()
	_h_layout.size = _h_layout.get_combined_minimum_size()
	_show_now()
	_position_for_current_source()

func hide_tooltip() -> void:
	if _lmb_held:
		return
	_show_token += 1
	_current_item = null
	_equipped_bg.visible = false
	_dismiss()
	_anchor_target = null

# Pick the anchor (if a 3D source is currently hovered) and place the
# tooltip accordingly. Called immediately after content/size update so the
# first frame is already in the right position — _process keeps it pinned
# from there.
func _position_for_current_source() -> void:
	_anchor_target = _pick_anchor_target()
	if _anchor_target != null:
		_position_at_top()
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

# Tooltip's secondary line — broad category + slot/archetype. The
# specific model ("Chaps", "Vest", "MKR-12 Quietus") already lives in
# the item's display name at the top of the tooltip, so repeating it
# here as the sub_type was redundant and pushed the actually-useful
# slot information off-screen. Format: "${category} - ${slot}".
const _CATEGORY_BY_MAIN_TYPE: Dictionary = {
	"Head Armor":  "Armor",
	"Chest Armor": "Armor",
	"Leg Armor":   "Armor",
	"Gloves":      "Armor",
	"Boots":       "Armor",
	"1H Weapon":   "Weapon",
	"2H Weapon":   "Weapon",
}

# Armor slot display names — singular for one-of body parts (Head,
# Chest), plural for paired (Legs, Hands, Feet). The slot, not the
# `&"head"`/`&"chest"` StringName, is what the player sees in-game.
const _ARMOR_SLOT_LABEL: Dictionary = {
	"Head Armor":  "Head",
	"Chest Armor": "Chest",
	"Leg Armor":   "Legs",
	"Gloves":      "Hands",
	"Boots":       "Feet",
}


func _build_type_text(item: Item) -> String:
	if item.main_type.is_empty():
		return ""
	var category: String = _CATEGORY_BY_MAIN_TYPE.get(item.main_type, item.main_type)
	var subtype: String = _resolve_type_subtype(item)
	if subtype.is_empty():
		return category
	return "%s - %s" % [category, subtype]


# Color-coded quality % in the top-right of the tooltip name row.
# Below 100%: red→yellow→green. Above 100%: green→blue.
func _update_quality_label(item: Item, label: Label = null) -> void:
	var lbl: Label = label if label != null else _quality_label
	if not ItemMeterData.has_meters(item):
		lbl.visible = false
		return
	var pct := int(round(item.effective_multiplier() * 100.0))
	lbl.text = "%d%%" % pct
	lbl.add_theme_color_override(&"font_color", _quality_pct_color(pct))
	lbl.visible = true


# Quality % color: 30% (floor) = red, 65% = yellow, 100% = green, 150% (ceil) = blue.
static func _quality_pct_color(pct: int) -> Color:
	if pct <= 100:
		# 30–100 range → red→yellow→green
		var t := clampf(float(pct - 30) / 70.0, 0.0, 1.0)
		if t < 0.5:
			return Color(0.9, 0.2, 0.2).lerp(Color(0.95, 0.85, 0.2), t / 0.5)
		else:
			return Color(0.95, 0.85, 0.2).lerp(Color(0.2, 0.85, 0.3), (t - 0.5) / 0.5)
	else:
		# 100–150 range → green→blue
		var t := clampf(float(pct - 100) / 50.0, 0.0, 1.0)
		return Color(0.2, 0.85, 0.3).lerp(Color(0.3, 0.55, 1.0), t)


# Choose what goes after the dash. Armor pieces show the slot; weapons
# show the archetype (`sub_type` is the WeaponBase's display_name like
# "SMG" or "Sniper Rifle"); grenades / offhands / backpacks fall back
# to sub_type with the category suffix stripped to avoid "Grenade -
# Frag Grenade" repeating "Grenade."
func _resolve_type_subtype(item: Item) -> String:
	if _ARMOR_SLOT_LABEL.has(item.main_type):
		return _ARMOR_SLOT_LABEL[item.main_type]
	if item.main_type == "1H Weapon" or item.main_type == "2H Weapon":
		return item.sub_type
	# Backpack / Grenade / Offhand — strip the redundant trailing category
	# word ("Frag Grenade" → "Frag" when category is "Grenade").
	var st := item.sub_type
	var category: String = _CATEGORY_BY_MAIN_TYPE.get(item.main_type, item.main_type)
	var suffix := " " + category
	if st.ends_with(suffix):
		st = st.substr(0, st.length() - suffix.length())
	return st

func _compute_dps(item: Item) -> float:
	# Delegates to WeaponMeterData — single source of truth for the DPS
	# formula. Includes multistrike from equipped perks.
	return WeaponMeterData.compute_single_dps(item)


# Cached WeaponBase loads, keyed by weapon_base_id, so opening tooltips
# for many items doesn't churn the resource loader. Cleared only on
# script reload — these are tiny resources and there are <20 of them.
static var _weapon_base_cache: Dictionary = {}


func _resolve_fire_skill(item: Item) -> Skill:
	if item == null or item.weapon_base_id == &"":
		return null
	var cached: WeaponBase = _weapon_base_cache.get(item.weapon_base_id, null)
	if cached == null:
		var path := "res://resources/items/weapon_bases/%s.tres" % item.weapon_base_id
		if not ResourceLoader.exists(path):
			# Silent null here would mean the tooltip's DPS formula
			# falls back to the raw attack_speed multiplier without the
			# cooldown / pellet_count / damage_multiplier corrections —
			# subtly wrong numbers from a typo or renamed file. Surface
			# the failure in editor logs instead of hiding it.
			push_warning("[Tooltip] WeaponBase not found for id %s (path %s) — DPS fallback will be inaccurate." % [
				item.weapon_base_id, path
			])
			return null
		cached = load(path) as WeaponBase
		if cached != null:
			_weapon_base_cache[item.weapon_base_id] = cached
	return cached.fire_skill if cached != null else null

# Builds the stats-block text for an item. Only DPS shows an inline
# comparison arrow against `equipped` — everything else is bare. The
# shift-held side-by-side panel covers the rest of the comparison.
func _build_stats_text(item: Item, equipped: Item = null, force_text: bool = false) -> String:
	var lines: Array[String] = []
	# Weapons with meter bars skip DPS and combat stat lines — those are
	# now conveyed visually by the meter strip above this text block.
	var is_weapon: bool = item.main_type == "1H Weapon" or item.main_type == "2H Weapon"
	var has_meters: bool = not force_text and ItemMeterData.has_meters(item)
	if not has_meters and is_weapon and item.damage_max > 0 and item.attack_speed > 0.0:
		var new_dps := _compute_dps(item)
		var line := "[color=#ffe680]DPS: %.1f[/color]" % new_dps
		if equipped != null and equipped.damage_max > 0 and equipped.attack_speed > 0.0:
			var old_dps := _compute_dps(equipped)
			if not is_equal_approx(new_dps, old_dps):
				line += " %s [color=#ffe680]%.1f[/color]" % [_compare_arrow(new_dps, old_dps), old_dps]
		lines.append(line)
	# Active offhand stats — meters handle these when available.
	if item.fire_skill != null and item.fire_skill.active_kind != Skill.ActiveKind.NONE:
		var sk: Skill = item.fire_skill
		var bonus: int = item.get_effective_modifier(&"shield_pool_bonus")
		var pool_total: int = sk.shield_pool + bonus
		match sk.active_kind:
			Skill.ActiveKind.SHIELD_BUFF:
				if not has_meters:
					lines.append("Damage Reduction: %.1f%%" % (sk.damage_reduction * 100.0))
					lines.append("Shield Pool: %d" % pool_total)
					lines.append("Duration: %ds" % int(round(sk.duration)))
					lines.append("Cooldown on Break: %.1fs" % sk.cooldown)
			Skill.ActiveKind.SHIELD_HOLD:
				if not has_meters:
					lines.append("Damage Block: 100%")
					lines.append("Shield Pool: %d" % pool_total)
					lines.append("Cooldown on Break: %.1fs" % sk.cooldown)
			Skill.ActiveKind.GRENADE:
				if not has_meters:
					var radius := item.blast_radius if item.blast_radius > 0.0 else sk.blast_radius
					lines.append("Blast Radius: %.1f m" % radius)
					lines.append("Cooldown: %.1fs" % sk.cooldown)
					if sk.resource_cost > 0:
						lines.append("Resource Cost: %d" % sk.resource_cost)
	# Weapon / combat stats — bare values. Weapons with meter bars skip
	# these entirely; the bars convey the same information visually.
	if not has_meters:
		if item.damage_max > 0:
			lines.append("Damage: %d–%d" % [item.effective_damage_min(), item.effective_damage_max()])
		if item.attack_speed != 1.0:
			lines.append("Speed: %.2f" % item.effective_attack_speed())
		if item.crit_chance > 0.0:
			lines.append("Crit: %.1f%%" % (item.effective_crit_chance() * 100.0))
		if item.accuracy != 1.0:
			lines.append("Accuracy: %.1f%%" % (item.effective_accuracy() * 100.0))
		if item.weapon_range > 0.0 and item.damage_max > 0:
			lines.append("Range: %.1f m" % item.weapon_range)
		if item.ammo_max > 0:
			lines.append("Capacity: %d" % item.ammo_max)
	# Weapon signature stats — archetype-specific rolled values (blast radius,
	# penetration, bleed, etc). Displayed with effectiveness decay applied.
	# Skipped when meter bars are active — sig stats are shown as bars instead.
	if not has_meters and item.weapon_base_id != &"":
		for sig_key: StringName in _WEAPON_SIG_DISPLAY:
			var raw: int = int(item.stat_modifiers.get(sig_key, 0))
			if raw == 0:
				continue
			var d: Dictionary = _WEAPON_SIG_DISPLAY[sig_key]
			if d.get("no_decay", false):
				# Geometric / feel stats (spread_angle) — raw value, no decay.
				lines.append("%s: %s" % [d["label"], d["fmt"] % raw])
			elif d.get("pct", false):
				var val := item.get_effective_modifier_float(sig_key)
				lines.append("%s: %s" % [d["label"], d["fmt"] % val])
			else:
				var val := item.get_effective_modifier(sig_key)
				lines.append("%s: %s" % [d["label"], d["fmt"] % val])
	# Element — for weapons whose archetype has an elemental identity
	# (Energy Accelerator's flame/cryo/electric, Taser's electric, etc).
	# Tints the weapon's effects in combat AND drives Overcharge-style
	# status effects, so worth surfacing to the player.
	# effective_damage_type() lazy-migrates pre-fix saves whose
	# damage_type field never got rolled (Accelerator pre-pool wiring).
	var elem_type := item.effective_damage_type()
	if elem_type != &"":
		var elem_label := (elem_type as String).capitalize()
		var elem_color := Item.damage_type_color(elem_type)
		var elem_hex := "#%02x%02x%02x" % [int(elem_color.r * 255), int(elem_color.g * 255), int(elem_color.b * 255)]
		lines.append("Element: [color=%s]%s[/color]" % [elem_hex, elem_label])
	# Head light mod
	if item.light_mod != Item.LightMod.NONE:
		var mod_name := "Light"
		match item.light_mod:
			Item.LightMod.FLASHLIGHT: mod_name = "Flashlight"
			Item.LightMod.RADIANT: mod_name = "Radiant Lamp"
			Item.LightMod.SCANNER: mod_name = "Tactical Scanner"
			Item.LightMod.UV: mod_name = "UV Lamp"
		lines.append("Mod: %s" % mod_name)
	# Container — shown via raw modifier because inventory capacity is a
	# storage stat, not a power stat, and shouldn't shrink with player level.
	var inv_bonus := item.get_modifier(&"inventory_bonus")
	if item.kind == &"backpack" and inv_bonus > 0:
		lines.append("+%d %s" % [inv_bonus, tr("ITEM_STATS_INVENTORY_BONUS")])
	# Consumable heal stats — custom one-liner instead of bare numbers.
	# heal_duration is rolled as a float (0.0-5.0) and item.get_modifier
	# returns int, so reading via the dict avoids truncating sub-1s
	# durations to 0 (which would silently skip this entire heal line and
	# make the potion read as "no health restoration"). Sub-HOT_INTERVAL
	# durations route through PlayerPotion's instant-heal branch.
	if item.main_type == "Consumable":
		if not has_meters:
			var hp: float = float(item.stat_modifiers.get(&"heal_pct", 0))
			var hd: float = float(item.stat_modifiers.get(&"heal_duration", 0.0))
			if hp > 0.0:
				if hd < 0.5:
					lines.append("[color=#66cc66]Heals %d%% HP instantly[/color]" % int(hp))
				else:
					lines.append("[color=#66cc66]Heals %d%% HP over %.1fs[/color]" % [int(hp), hd])
		if item.max_charges > 0:
			lines.append("Charges: %d (%.0fs recharge)" % [item.max_charges, item.recharge_time])
	# Generic stat modifiers — bare values, no comparison.
	for stat_id: StringName in item.stat_modifiers:
		if stat_id == &"inventory_bonus" and item.kind == &"backpack":
			continue
		if stat_id in _WEAPON_SIG_DISPLAY and item.weapon_base_id != &"":
			continue
		if stat_id in [&"heal_pct", &"heal_duration"] and item.main_type == "Consumable":
			continue
		if has_meters and stat_id in ItemMeterData.METERED_MODIFIER_KEYS:
			continue
		var raw: int = int(item.stat_modifiers.get(stat_id, 0))
		if raw == 0:
			continue
		var label := _stat_display_name(stat_id)
		if stat_id in _PCT_STATS:
			var amt_f: float = item.get_effective_modifier_float(stat_id)
			var sign_f: String = "+" if amt_f > 0.0 else ""
			lines.append("%s%.1f%% %s" % [sign_f, amt_f, label])
		else:
			var amount: int = item.get_effective_modifier(stat_id)
			var sign := "+" if amount > 0 else ""
			lines.append("%s%d %s" % [sign, amount, label])
	return "\n".join(lines)


## Returns a BBCode-colored arrow: green ▲ for better, red ▼ for worse,
## grey = for equal. Higher is always better for DPS — the only stat that
## still uses this.
func _compare_arrow(new_val: float, old_val: float) -> String:
	if new_val > old_val:
		return "[color=%s]▲[/color]" % COMPARE_BETTER_COLOR
	elif new_val < old_val:
		return "[color=%s]▼[/color]" % COMPARE_WORSE_COLOR
	return "[color=%s]=[/color]" % COMPARE_NEUTRAL_COLOR


# Stat keys that should render as percentages (with the tenths suffix per
# the "marginal upgrades visible" rule). Anything not in this set is
# rendered as a flat integer. New affixes that produce a percentage bonus
# must be added here, otherwise their tooltip line drops the %.
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
	&"move_speed_bonus": true,
}

# Weapon archetype signature stats — displayed in the weapon stats block
# (above generic modifiers) with custom formatting per stat. Keys here are
# also excluded from the generic stat_modifiers loop to avoid double-listing.
# "pct" = true means the value is a percentage and should use float display.
const _WEAPON_SIG_DISPLAY: Dictionary = {
	&"blast_radius_bonus": { "label": "Blast Radius",    "fmt": "+%d m", "no_decay": true },
	&"pellet_count":       { "label": "Pellets",         "fmt": "%d", "no_decay": true },
	&"spread_angle":       { "label": "Spread",          "fmt": "%d°", "no_decay": true },
	&"penetration":        { "label": "Penetration",     "fmt": "%d", "no_decay": true },
	&"headshot_bonus":     { "label": "Headshot Bonus",  "fmt": "+%.1f%%", "pct": true },
	&"chain_retention":    { "label": "Chain Retention",  "fmt": "%.1f%%", "pct": true },
	&"chain_targets":      { "label": "Chain Targets",   "fmt": "%d", "no_decay": true },
	&"ramp_speed":         { "label": "Ramp Speed",      "fmt": "+%.1f%%", "pct": true },
	&"bleed_damage":       { "label": "Bleed",           "fmt": "%d/tick" },
	&"impact_radius":      { "label": "Impact Radius",   "fmt": "%d m", "no_decay": true },
	&"sustained_bonus":    { "label": "Sustained Fire",  "fmt": "+%.1f%%", "pct": true },
	&"ricochet_chance":    { "label": "Ricochet",        "fmt": "%.1f%%", "pct": true },
	&"overcharge_chance":  { "label": "Overcharge",      "fmt": "%.1f%%", "pct": true },
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
	&"life_on_kill": "Life on Kill",
	&"barrier_on_kill": "Barrier on Kill",
	&"unarmed_damage_bonus": "Unarmed Damage",
	&"unarmed_stun_chance": "Unarmed Stun Chance",
	&"unarmed_aoe_radius": "Unarmed AoE Radius",
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
		Skill.ActiveKind.AIM_HOLD:
			# Held-buff skills (Aimed Shot, LMG Tripod). They don't
			# deal their own damage and aren't fired; showing weapon
			# damage / speed / accuracy here was misleading. Show the
			# buff effects + drain rate + movement-lock instead.
			lines.append("[color=#aaccff]Hold: drains resource for combat buffs[/color]")
			if skill.aim_hold_accuracy_bonus > 0.0:
				lines.append("+%.0f%% Accuracy" % (skill.aim_hold_accuracy_bonus * 100.0))
			if skill.aim_hold_crit_bonus > 0.0:
				lines.append("+%.0f%% Crit Chance" % (skill.aim_hold_crit_bonus * 100.0))
			if skill.aim_hold_resource_drain > 0.0:
				lines.append("Drain: %.0f/sec" % skill.aim_hold_resource_drain)
			if skill.aim_hold_locks_movement:
				lines.append("[color=#ff8866]Locks Movement[/color]")
		Skill.ActiveKind.CHANNEL_BEAM:
			# Held-damage skills (Taser Tase, Accelerator Stream). The
			# weapon's per-shot damage is the per-tick damage here, so
			# leading with damage range is fair — but cooldown/accuracy
			# don't apply to a continuous channel, so we skip them.
			# Targeting-specific lines (chain jump radius, cone deg)
			# follow.
			lines.append("[color=#aaccff]Hold: continuous damage channel[/color]")
			if source != null and source.damage_max > 0:
				lines.append("Damage / tick: %d–%d" % [source.effective_damage_min(), source.effective_damage_max()])
			elif skill.damage > 0:
				lines.append("Damage / tick: %d" % skill.damage)
			if skill.channel_tick_interval > 0.0:
				lines.append("Ticks: %.1f/sec" % (1.0 / skill.channel_tick_interval))
			if skill.channel_resource_per_sec > 0.0:
				lines.append("Drain: %.0f/sec" % skill.channel_resource_per_sec)
			var ch_range := source.weapon_range if source != null and source.weapon_range > 0.0 else skill.skill_range
			if ch_range > 0.0:
				lines.append("Range: %.1f m" % ch_range)
			match skill.targeting_mode:
				Skill.TargetingMode.SINGLE_CONE:
					lines.append("Targeting: Cone %d°" % int(skill.cone_deg))
				Skill.TargetingMode.CHAIN_LIGHTNING:
					var ct: int = source.get_effective_modifier(&"chain_targets") if source != null else 0
					var jumps: int = ct if ct > 0 else skill.chain_jumps
					var falloff: float = skill.chain_falloff_pct
					if source != null:
						var ret: int = source.get_effective_modifier(&"chain_retention")
						if ret > 0:
							falloff = clampf(100.0 - float(ret), 0.0, 100.0)
					if falloff > 0.0:
						if jumps > 0:
							lines.append("Chain: %d targets, %.0f%% falloff" % [jumps, falloff])
						else:
							lines.append("Chain: bounces with %.0f%% falloff" % falloff)
					else:
						lines.append("Chain: %d targets" % jumps)
		Skill.ActiveKind.POTION:
			var consumable: Item = InventoryState.get_equipped(&"consumable")
			if consumable != null:
				# Read via stat_modifiers — heal_duration is float and
				# get_modifier truncates to int (see _build_stats_text).
				var hp: float = float(consumable.stat_modifiers.get(&"heal_pct", 0))
				var hd: float = float(consumable.stat_modifiers.get(&"heal_duration", 0.0))
				if hp > 0.0:
					if hd < 0.5:
						lines.append("[color=#66cc66]Instantly heals %d%% HP[/color]" % int(hp))
					else:
						lines.append("[color=#66cc66]Heals %d%% HP over %.1fs[/color]" % [int(hp), hd])
			if consumable != null and consumable.max_charges > 0:
				lines.append("Charges: %d (%.0fs recharge)" % [consumable.max_charges, consumable.recharge_time])
			lines.append("Per-use Cooldown: %.1fs" % skill.cooldown)
		_:
			# Standard weapon skill (cone, aoe, projectile, hitscan).
			var dmg_mult := skill.damage_multiplier
			if source != null and source.damage_max > 0:
				var dmin := int(round(source.effective_damage_min() * dmg_mult))
				var dmax := int(round(source.effective_damage_max() * dmg_mult))
				lines.append("Damage: %d–%d" % [dmin, dmax])
			elif skill.damage > 0:
				lines.append("Damage: %d" % int(round(skill.damage * dmg_mult)))
			if dmg_mult != 1.0:
				lines.append("Damage Multiplier: %.1f×" % dmg_mult)
			if source != null and source.attack_speed != 1.0:
				lines.append("Speed: %.2f" % source.effective_attack_speed())
			if source != null and source.crit_chance > 0.0:
				lines.append("Crit: %.1f%%" % (source.effective_crit_chance() * 100.0))
			if source != null and source.accuracy < 1.0:
				lines.append("Accuracy: %.1f%%" % (source.effective_accuracy() * 100.0))
			var eff_range := source.weapon_range if source != null and source.weapon_range > 0.0 else skill.skill_range
			if eff_range > 0.0:
				lines.append("Range: %.1f m" % eff_range)
			if skill.blast_radius > 0.0:
				lines.append("Blast Radius: %.1f m" % skill.blast_radius)
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
					if skill.blast_radius > 0.0:
						lines.append("Targeting: AoE Projectile")
					else:
						lines.append("Targeting: Projectile")
				Skill.TargetingMode.HITSCAN:
					lines.append("Targeting: Hitscan")
	return "\n".join(lines)
