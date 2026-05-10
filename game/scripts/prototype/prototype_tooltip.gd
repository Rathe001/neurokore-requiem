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
var _type_label: Label
var _desc_label: Label
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
var _shift_held: bool = false

# LMB lock: while held on an enemy, the tooltip freezes — no content updates,
# no hide on hover-exit, gold border to telegraph the locked state. Released
# → unlocked and dismissed.
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
	if not visible or _lmb_held:
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
	# Tighten line spacing — default (3) leaves too much vertical air in
	# multi-line tooltips, especially the buff-bar tooltips with bullet lists.
	# Down to 0 reads compact without the bullets touching descenders.
	_desc_label.add_theme_constant_override(&"line_spacing", 0)
	_desc_label.mouse_filter = MOUSE_FILTER_IGNORE
	_desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Pin the wrap width up-front. Without this, autowrap labels report
	# minimum_size as the unwrapped natural width on first layout, which the
	# PanelContainer then allocates — and the second pass that would measure
	# wrapped height never fires before the tooltip is shown.
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

	_equipped_name = Label.new()
	_equipped_name.theme_type_variation = &"BodyLabel"
	_equipped_name.add_theme_font_size_override(&"font_size", 10)
	_equipped_name.mouse_filter = MOUSE_FILTER_IGNORE
	_equipped_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_equipped_name.custom_minimum_size = Vector2(CONTENT_MIN_WIDTH, 0.0)
	_equipped_vbox.add_child(_equipped_name)

	_equipped_type = Label.new()
	_equipped_type.theme_type_variation = &"SmallLabel"
	_equipped_type.add_theme_font_size_override(&"font_size", 7)
	_equipped_type.mouse_filter = MOUSE_FILTER_IGNORE
	_equipped_vbox.add_child(_equipped_type)

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
	# Sync shift state in case the user was already holding it before hover.
	_shift_held = Input.is_key_pressed(KEY_SHIFT)
	_current_item = item
	_text_label.visible = false

	_name_label.text = item.name_key
	_name_label.add_theme_color_override(&"font_color", _rarity_color(item.rarity))
	_name_row.visible = true
	_dps_label.visible = false

	var type_text := _build_type_text(item)
	var tagline := _archetype_tagline(item)
	if not tagline.is_empty():
		# Tagline appended on a second line so it renders directly under
		# the archetype line in the same muted grey style. Pure cosmetic
		# identity — reinforces the weapon's "personality" at the moment
		# of pickup without needing a dedicated label.
		type_text = "%s\n%s" % [type_text, tagline]
	_type_label.text = type_text
	_type_label.visible = not type_text.is_empty()

	var has_desc := item.description_key != ""
	_desc_label.text = item.description_key
	_desc_label.visible = has_desc

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

# Mid-show shift toggle: visibility flip changes compound width, so re-run
# the size/position pipeline.
func _refresh_equipped_panel() -> void:
	var equipped: Item = _resolve_equipped(_current_item)
	var should_show := _shift_held and equipped != null
	if should_show:
		_populate_equipped_panel(equipped)
	if _equipped_bg.visible == should_show:
		return
	_equipped_bg.visible = should_show
	if visible and not _lmb_held:
		_resize_then_show()

func _populate_equipped_panel(item: Item) -> void:
	_equipped_name.text = item.name_key
	_equipped_name.add_theme_color_override(&"font_color", _rarity_color(item.rarity))
	var t := _build_type_text(item)
	_equipped_type.text = t
	_equipped_type.visible = not t.is_empty()
	_equipped_stats.text = _build_stats_text(item, null)

func show_skill(skill: Skill, source: Item) -> void:
	if _lmb_held:
		return
	if skill == null:
		hide_tooltip()
		return
	_current_item = null
	_equipped_bg.visible = false
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
	_current_item = null
	_equipped_bg.visible = false
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

# Tagline by weapon archetype — one line of flavor that reinforces the
# weapon's identity. Tone matches the cyberpunk + body-horror + 80s
# sci-fi camp surface: clipped corp-shorthand for firearms, blunter
# physical lines for melee, eerie evocative phrases for energy.
const WEAPON_TAGLINES: Dictionary = {
	&"melee_1h": "Quick, quiet, repeatable.",
	&"melee_2h": "Subtle as a falling building.",
	&"ranged_1h": "Pocket-sized, plenty loud.",
	&"ranged_2h": "Bolts pass through. Things fall down.",
	&"smg_1h": "Volume over precision.",
	&"lmg_2h": "Suppress. Sustain. Survive.",
	&"sniper_2h": "One shot. One thought.",
	&"rpg_2h": "When subtlety has failed.",
	&"shotgun_2h": "Get close. Get closer.",
	&"taser_2h": "The hum before the scream.",
	&"accelerator_2h": "Continuous. Element-fed. Patient.",
}


func _archetype_tagline(item: Item) -> String:
	if item == null or item.weapon_base_id == &"":
		return ""
	return WEAPON_TAGLINES.get(item.weapon_base_id, "")


func _build_type_text(item: Item) -> String:
	if item.main_type.is_empty():
		return ""
	if item.sub_type.is_empty():
		return item.main_type
	return "%s - %s" % [item.main_type, item.sub_type]

func _compute_dps(item: Item) -> float:
	# Returns the weapon's expected raw single-target DPS — what the
	# weapon outputs when every shot lands and the damage roll is
	# average. Accuracy is intentionally NOT in the formula: scattered
	# shots still hit nearby enemies in the cone, and a shotgun pellet
	# that "misses" the cursor target often hits a different one in
	# the spread. The number is "weapon power" not "expected DPS to a
	# specific cursor-target."
	#
	# Formula (single-shot weapons):
	#   DPS = avg_dmg × pellet_count × damage_multiplier × fire_rate × crit_factor
	# where:
	#   fire_rate = atk_speed / skill.cooldown   (casts per second)
	#   crit_factor = 1 + crit × (crit_mult - 1)
	#
	# Channel weapons (CHANNEL_BEAM, e.g. Energy Accelerator stream)
	# bypass cooldown and tick by `channel_tick_interval` instead;
	# their per-tick damage is the *skill*'s damage value, not the
	# weapon roll. Weapon roll still drives the displayed Damage line.
	var avg_dmg := float(item.effective_damage_min() + item.effective_damage_max()) * 0.5
	var spd := item.effective_attack_speed()
	var crit: float = item.effective_crit_chance() if item.crit_chance > 0.0 else 0.15
	var crit_mult := 1.5
	var crit_factor := 1.0 + crit * (crit_mult - 1.0)
	# Multistrike rolls per cast, so DPS scales with E[hits]. Resolves
	# to 1.0 with no multistrike sources equipped — unaffected weapons
	# pass through cleanly.
	var multistrike_factor: float = PerkState.expected_multistrike()

	var fire_skill := _resolve_fire_skill(item)
	var pellet_count := 1
	var damage_mult := 1.0
	var fire_rate := spd  # fallback when no fire_skill or cooldown=0 and not a channel
	if fire_skill != null:
		pellet_count = maxi(1, fire_skill.pellet_count)
		damage_mult = maxf(0.01, fire_skill.damage_multiplier)
		# Channel beams: per-tick damage × ticks per second. Per-tick
		# damage on a channel is `skill.damage` (the resource of an
		# Accelerator stream defines its tick). The weapon's avg_dmg
		# is irrelevant to actual stream output. Multistrike still
		# applies — each tick goes through resolve_skill_hit's
		# multistrike loop, so per-tick output scales with E[hits].
		if fire_skill.active_kind == Skill.ActiveKind.CHANNEL_BEAM:
			var interval: float = maxf(fire_skill.channel_tick_interval, 0.05)
			var per_tick := float(fire_skill.damage)
			return per_tick * (1.0 / interval) * crit_factor * multistrike_factor
		# Cooldown-driven fire rate. attack_speed scales the cooldown
		# duration (start_cooldown divides by it), so casts/sec =
		# atk_speed / cooldown. cooldown <= 0 falls back to atk_speed
		# alone (e.g. zero-cooldown skills that effectively re-fire as
		# fast as the weapon's animation allows).
		if fire_skill.cooldown > 0.0:
			fire_rate = spd / fire_skill.cooldown

	return avg_dmg * float(pellet_count) * damage_mult * fire_rate * crit_factor * multistrike_factor


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
	# DPS summary — single most important number for weapon comparison.
	# Factors in accuracy and crit so it reflects real expected output.
	if item.damage_max > 0 and item.attack_speed > 0.0:
		var new_dps := _compute_dps(item)
		var line := "[color=#ffe680]DPS: %.1f[/color]" % new_dps
		if equipped != null and equipped.damage_max > 0 and equipped.attack_speed > 0.0:
			var old_dps := _compute_dps(equipped)
			if not is_equal_approx(new_dps, old_dps):
				line += " %s [color=#ffe680]%.1f[/color]" % [_compare_arrow(new_dps, old_dps), old_dps]
		lines.append(line)
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
	# Weapon / combat stats — bare values (shift-side-by-side covers compare).
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
			Item.LightMod.SCANNER: mod_name = "Scanner"
			Item.LightMod.UV: mod_name = "UV Lamp"
		lines.append("Mod: %s" % mod_name)
	# Container — shown via raw modifier because inventory capacity is a
	# storage stat, not a power stat, and shouldn't shrink with player level.
	var inv_bonus := item.get_modifier(&"inventory_bonus")
	if item.kind == &"backpack" and inv_bonus > 0:
		lines.append("+%d %s" % [inv_bonus, tr("ITEM_STATS_INVENTORY_BONUS")])
	# Generic stat modifiers — bare values, no comparison.
	for stat_id: StringName in item.stat_modifiers:
		if stat_id == &"inventory_bonus" and item.kind == &"backpack":
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
		Skill.ActiveKind.AIM_HOLD:
			# Held-buff skills (Sniper Focus, LMG Tripod). They don't
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
					if skill.chain_falloff_pct > 0.0:
						lines.append("Chain: bounces with %.0f%% falloff" % skill.chain_falloff_pct)
					else:
						lines.append("Chain: %d targets" % skill.chain_jumps)
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
