extends CanvasLayer
class_name PrototypeHud

const HP_BAR_WIDTH := 156.0
const RESOURCE_BAR_WIDTH := 156.0
const LOW_HP_RATIO := 0.35
# Rolling window for the avatar loot tally — pickups within this many seconds
# of each other accumulate; the running total clears once nothing's been
# picked up for the full window.
const LOOT_TALLY_WINDOW := 5.0

# Visual order on the bar: number/letter slots first (1-E), then LMB/RMB on
# the right side, with the F/^ flashlight & crouch indicators trailing.
# SLOT_TO_SKILL_INDEX maps each visual slot to the skill index that
# resolve_skill() expects (0=LMB, 1=RMB, 2-7=skills[0..5] for keys 1,2,3,4,Q,E).
const SLOT_LABELS: Array[String] = ["1", "2", "3", "4", "Q", "E", "LMB", "RMB"]
const SLOT_TO_SKILL_INDEX: Array[int] = [2, 3, 4, 5, 6, 7, 0, 1]
const DEBUG_OVERLAY_INTERVAL := 0.1

@onready var root: Control = $Root
@onready var hud_bg: ColorRect = %HudBackground
@onready var hud_border: ReferenceRect = %HudBorder
@onready var hp_fill: ColorRect = %HPFill
@onready var hp_label: Label = %HPLabel
@onready var hp_bg: ColorRect = %HPBackground
@onready var hp_border: ReferenceRect = %HPBorder
@onready var hp_frame: NinePatchRect = %HPFrame
@onready var resource_fill: ColorRect = %ResourceFill
@onready var resource_label: Label = %ResourceLabel
@onready var resource_bg: ColorRect = %ResourceBackground
@onready var resource_border: ReferenceRect = %ResourceBorder
@onready var resource_frame: NinePatchRect = %ResourceFrame
@onready var avatar_bg: ColorRect = %AvatarBackground
@onready var avatar_border: ReferenceRect = %AvatarBorder
@onready var avatar_image: TextureRect = %AvatarImage
@onready var avatar_placeholder: Label = %AvatarPlaceholder
@onready var level_label: Label = %LevelLabel
@onready var buff_entries: HBoxContainer = %BuffEntries
@onready var recent_loot_label: Label = %RecentLootLabel
@onready var flashlight_bg: ColorRect = %FBg
@onready var flashlight_border: ReferenceRect = %FBorder
@onready var crouch_bg: ColorRect = %CBg
@onready var crouch_border: ReferenceRect = %CBorder
@onready var skill_bar: Control = %SkillBar
@onready var banner: Label = %Banner
@onready var debug_label: Label = %DebugLabel
@onready var debug_bg: ColorRect = $Root/DebugPanel/DebugBack
@onready var xp_fill: ColorRect = %XPFill
@onready var xp_bg: ColorRect = %XPBackground
@onready var main_menu: Node = %MainMenu

var _max_health: int = 1
var _last_hp_current: int = 0
var _banner_token: int = 0
var _debug_overlay_accum: float = 0.0
var _state_flashlight: bool = false
var _state_crouch: bool = false
var _minimap: Minimap
# Loot tally state: signal carries the running total, not the delta, so we
# diff it against the last seen value to derive each pickup amount.
var _last_credits_seen: int = 0
var _loot_tally: int = 0
var _loot_tally_token: int = 0

func _ready() -> void:
	add_to_group(&"hud")
	_apply_theme()
	_update_avatar_panel()
	_repaint_xp(PlayerState.xp, PlayerState.xp_to_next)
	UIThemeState.changed.connect(_apply_theme)
	PlayerState.level_changed.connect(func(_n: int, _o: int) -> void: _update_avatar_panel())
	PlayerState.xp_changed.connect(_repaint_xp)
	# Buffs bar repopulates on any of the signals that can shift the active
	# perk set: gear swap (stats), tier crossing, class/spec change. PerkState
	# already collapses these into its own perks_changed, but we hook the
	# upstream signals too so display stays accurate even if PerkState is
	# briefly out of sync during a recompute cycle.
	PerkState.perks_changed.connect(_update_buffs_bar)
	AttributeState.stats_changed.connect(_update_buffs_bar)
	PlayerState.class_changed.connect(func(_id: StringName) -> void: _update_buffs_bar())
	PlayerState.spec_changed.connect(func(_id: StringName) -> void: _update_buffs_bar())
	_update_buffs_bar()
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		push_warning("[prototype_hud] no player in group")
		return
	_max_health = int(player.max_health)
	_last_hp_current = _max_health
	if player.has_signal(&"health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal(&"resource_changed"):
		player.resource_changed.connect(_on_resource_changed)
	if player.has_signal(&"died"):
		player.died.connect(_on_player_died)
	if player.has_signal(&"notification_requested"):
		player.notification_requested.connect(_on_notification_requested)
	if player.has_signal(&"crouch_changed"):
		player.crouch_changed.connect(_on_crouch_changed)
	if player.has_signal(&"light_changed"):
		player.light_changed.connect(_on_light_changed)
	# Charm count drives the live "current/max" text on the AMB buff
	# entry. Cheaper to rebuild the bar than to reach in and surgically
	# patch one Label — the bar has at most ~6 entries.
	if player.has_signal(&"charm_count_changed"):
		player.charm_count_changed.connect(func(_c: int, _m: int) -> void: _update_buffs_bar())
	if player.has_signal(&"credits_changed"):
		_last_credits_seen = int(player.get_credits()) if player.has_method(&"get_credits") else 0
		player.credits_changed.connect(_on_credits_changed)
	PerkState.perk_gained.connect(_on_perk_gained)
	_on_health_changed(_max_health, _max_health)
	_bind_skill_slots(player)
	_bind_resource_pool(player)
	_build_minimap(player)
	_build_talents_panel()

func _apply_theme() -> void:
	root.theme = UIThemeState.theme
	var p := UIThemeState.palette
	var panel_dark := Color(p.panel_bg.r * 0.65, p.panel_bg.g * 0.65, p.panel_bg.b * 0.65, 0.92)
	hud_bg.color = panel_dark
	hud_border.border_color = Color(p.panel_border.r, p.panel_border.g, p.panel_border.b, 0.65)
	hp_bg.color = p.hp_bar_bg
	hp_border.border_color = p.hp_bar_border
	resource_bg.color = p.hp_bar_bg
	resource_border.border_color = p.hp_bar_border
	var accent_dark := Color(p.accent.r * 0.15, p.accent.g * 0.15, p.accent.b * 0.15, 0.95)
	avatar_bg.color = accent_dark
	avatar_border.border_color = Color(p.accent.r, p.accent.g, p.accent.b, 0.65)
	level_label.add_theme_color_override(&"font_color", p.accent)
	avatar_placeholder.add_theme_color_override(&"font_color", Color(p.accent.r, p.accent.g, p.accent.b, 0.4))
	debug_bg.color = Color(p.panel_bg.r, p.panel_bg.g, p.panel_bg.b, 0.75)
	_apply_frame(hp_frame, hp_border, p.hp_bar_frame, p.frame_patch_margin)
	_apply_frame(resource_frame, resource_border, p.resource_bar_frame, p.frame_patch_margin)
	_repaint_hp()
	_apply_indicator(flashlight_bg, flashlight_border, _state_flashlight)
	_apply_indicator(crouch_bg, crouch_border, _state_crouch)

func _apply_frame(frame: NinePatchRect, fallback_border: ReferenceRect, tex: Texture2D, margin: int) -> void:
	if tex == null:
		frame.visible = false
		frame.texture = null
		fallback_border.visible = true
		return
	frame.texture = tex
	frame.patch_margin_left = margin
	frame.patch_margin_top = margin
	frame.patch_margin_right = margin
	frame.patch_margin_bottom = margin
	frame.visible = true
	fallback_border.visible = false

func _apply_indicator(bg: ColorRect, border: ReferenceRect, active: bool) -> void:
	var p := UIThemeState.palette
	if active:
		bg.color = Color(p.accent.r * 0.35, p.accent.g * 0.35, p.accent.b * 0.35, 0.95)
		border.border_color = p.accent
	else:
		bg.color = p.slot_bg
		border.border_color = Color(p.slot_border.r, p.slot_border.g, p.slot_border.b, 0.5)

func _update_avatar_panel() -> void:
	# Image: PlayerState.avatar_texture() returns null when character creation
	# was bypassed (legacy prototype scene). The placeholder "?" fills the
	# square so the panel stays balanced; the level label below still works.
	var tex := PlayerState.avatar_texture()
	if tex != null:
		avatar_image.texture = tex
		avatar_image.visible = true
		avatar_placeholder.visible = false
	else:
		avatar_image.texture = null
		avatar_image.visible = false
		avatar_placeholder.visible = true
	level_label.text = tr("HUD_LEVEL_FORMAT") % PlayerState.level


# Rebuild the buffs / active-perks strip. Each entry is a small colored
# panel hoverable for a tooltip showing the perk's label + description.
# Iterates ROLLABLE_STATS for stable left-to-right order regardless of
# which tiers happen to be unlocked — so newly-acquired perks slot into
# their fixed position rather than shuffling existing entries.
const _BUFF_ENTRY_SIZE := Vector2(14.0, 14.0)
func _update_buffs_bar() -> void:
	if buff_entries == null:
		return
	for child in buff_entries.get_children():
		child.queue_free()
	if PlayerState.class_id == &"":
		return
	# Index active perks by id so we can match a stat tier to its perk
	# resource (same id convention: "{stat}_t{N}", e.g. "amb_t2").
	var active_by_id: Dictionary = {}
	for p in PerkState.get_active_perks():
		if p != null:
			active_by_id[p.id] = p
	for stat_id in AttributeState.ROLLABLE_STATS:
		var tier := AttributeState.get_unlocked_tier(stat_id, PlayerState.class_id, PlayerState.spec_id)
		if tier <= 0:
			continue
		# Try to look up the actual perk resource for this stat+tier so
		# the tooltip shows the perk's authored label + description.
		# Falls back to a generic "STAT TIER" label if the ladder
		# doesn't have a perk for this tier (e.g. unauthored ladders).
		var perk_id := StringName("%s_t%d" % [String(stat_id), tier])
		var perk: Perk = active_by_id.get(perk_id)
		_add_buff_entry(stat_id, tier, perk)


func _add_buff_entry(stat_id: StringName, tier: int, perk: Perk) -> void:
	var stat_color: Color = AttributeState.STAT_COLORS.get(stat_id, Color.WHITE)
	# No background, no border — entry is just the tier roman painted in
	# the stat color. Wrapping in a Control so mouse_filter STOP still
	# catches hover events for the tooltip without a visible panel.
	var entry := Control.new()
	entry.custom_minimum_size = _BUFF_ENTRY_SIZE
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	var label := Label.new()
	label.text = AttributeState.TIER_ROMAN[tier - 1]
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", stat_color)
	# Subtle outline so the colored numerals stay readable against any
	# background the world happens to render behind them. 1px keeps the
	# small tier text crisp without thickening it.
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override(&"outline_size", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(label)
	# Hover wires to the existing tooltip system. Captured locals so the
	# closure doesn't reach into mutable state at fire time.
	# Build tooltip lazily at hover time so live state (current charm
	# count for AMB, etc.) is fresh on each open instead of frozen at
	# bar-build time.
	var captured_stat: StringName = stat_id
	var captured_tier: int = tier
	var captured_perk: Perk = perk
	entry.mouse_entered.connect(func() -> void:
		var pair := _build_buff_tooltip(captured_stat, captured_tier, captured_perk)
		get_tree().call_group(&"interactable_tooltip", &"show_talent_node", pair[0], pair[1]))
	entry.mouse_exited.connect(func() -> void:
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip"))
	buff_entries.add_child(entry)


# Returns [title, body] for the buff tooltip. AMB appends the live
# charm count ("X/Y followers") so the player can see how many pets
# they currently have without staring at the bar.
func _build_buff_tooltip(stat_id: StringName, tier: int, perk: Perk) -> Array:
	var title: String
	var body: String
	if perk != null:
		title = "%s  ·  %s" % [perk.label, AttributeState.TIER_ROMAN[tier - 1]]
		body = perk.description
	else:
		var stat_key: StringName = AttributeState.STAT_I18N.get(stat_id, &"")
		var stat_name: String = tr(stat_key) if stat_key != &"" else String(stat_id).capitalize()
		title = "%s  ·  %s" % [stat_name, AttributeState.TIER_ROMAN[tier - 1]]
		body = "Tier %s perk for this stat — no description available." % AttributeState.TIER_ROMAN[tier - 1]
	if stat_id == &"amb":
		var player := get_tree().get_first_node_in_group(&"player") as PrototypePlayer
		var current: int = player.get_charm_count() if player != null else 0
		var max_count: int = player.get_charm_max() if player != null else 0
		body += "\n\n%d/%d followers" % [current, max_count]
	return [title, body]

func _repaint_xp(current: int, to_next: int) -> void:
	if xp_fill == null:
		return
	var ratio: float = 0.0
	if to_next > 0:
		ratio = clampf(float(current) / float(to_next), 0.0, 1.0)
	xp_fill.anchor_right = ratio

func _on_crouch_changed(is_crouching: bool) -> void:
	_state_crouch = is_crouching
	_apply_indicator(crouch_bg, crouch_border, _state_crouch)

func _on_light_changed(is_on: bool) -> void:
	_state_flashlight = is_on
	_apply_indicator(flashlight_bg, flashlight_border, _state_flashlight)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	for modal in get_tree().get_nodes_in_group(&"ui_modal"):
		if modal == main_menu:
			continue
		if modal.visible:
			modal.call(&"close_menu")
			get_viewport().set_input_as_handled()
			return
	if main_menu.visible:
		main_menu.close_menu()
	else:
		main_menu.open_menu()
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var panel := debug_label.get_parent() as Control
	var overlay_on := DebugState.config == null or DebugState.config.show_debug_overlay
	if panel.visible != overlay_on:
		panel.visible = overlay_on
	if not overlay_on:
		return
	_debug_overlay_accum += delta
	if _debug_overlay_accum < DEBUG_OVERLAY_INTERVAL:
		return
	_debug_overlay_accum = 0.0
	var tree := get_tree()
	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(float(fps), 1.0)
	debug_label.text = tr("HUD_DEBUG_OVERLAY_FORMAT") % [
		fps,
		frame_ms,
		SpatialGrid.count(&"enemies"),
		tree.get_nodes_in_group(&"corpses").size(),
		tree.get_nodes_in_group(&"pickups").size(),
		tree.get_nodes_in_group(&"structures").size(),
		tree.get_node_count(),
	]

func _bind_skill_slots(player: Node) -> void:
	var skills: Array = player.skills
	for i in SLOT_LABELS.size():
		var slot := skill_bar.get_node_or_null("Slot%d" % i) as SkillSlot
		if slot == null:
			continue
		var skill_idx: int = SLOT_TO_SKILL_INDEX[i]
		var skill: Skill = player.resolve_skill(skill_idx) if player.has_method(&"resolve_skill") else (skills[skill_idx] if skill_idx < skills.size() else null)
		slot.bind(player, skill, SLOT_LABELS[i])
	# LMB / RMB skills come from the equipped weapon + offhand. Re-bind on
	# equipment changes so swapping weapons updates the cooldown overlay
	# (without this, the slot keeps polling the previous weapon's skill
	# and shows nothing for the new one).
	if not InventoryState.equipment_changed.is_connected(_on_equipment_changed):
		InventoryState.equipment_changed.connect(_on_equipment_changed.bind(player))


func _on_equipment_changed(slot_name: StringName, player: Node) -> void:
	if slot_name != &"weapon" and slot_name != &"offhand":
		return
	# Only rebind LMB (visual slot 6) and RMB (visual slot 7) — the rest
	# of the bar pulls from player.skills which doesn't change at runtime.
	for i in [6, 7]:
		var slot := skill_bar.get_node_or_null("Slot%d" % i) as SkillSlot
		if slot == null:
			continue
		var skill_idx: int = SLOT_TO_SKILL_INDEX[i]
		var skill: Skill = player.resolve_skill(skill_idx) if player.has_method(&"resolve_skill") else null
		slot.bind(player, skill, SLOT_LABELS[i])

func _bind_resource_pool(player: Node) -> void:
	var pool: ResourcePool = player.resource_pool
	if pool == null:
		resource_fill.size.x = 0.0
		resource_label.text = tr("COMMON_DASH")
		return
	resource_fill.color = pool.color
	_on_resource_changed(pool.start_value, pool.max_value)

func _build_minimap(player: Node) -> void:
	_minimap = Minimap.new()
	root.add_child(_minimap)
	# If scanner is already equipped, activate radar overlay.
	if player.has_method(&"is_scanner_active"):
		_minimap.scanner_active = player.is_scanner_active()

func _build_talents_panel() -> void:
	var talents := TalentsPanel.new()
	root.add_child(talents)

func set_scanner_active(active: bool) -> void:
	if _minimap != null:
		_minimap.scanner_active = active

func _on_health_changed(current: int, max_value: int) -> void:
	_max_health = max(max_value, 1)
	_last_hp_current = current
	_repaint_hp()

func _repaint_hp() -> void:
	var ratio := clampf(float(_last_hp_current) / float(_max_health), 0.0, 1.0)
	var p := UIThemeState.palette
	hp_fill.offset_right = hp_fill.offset_left + HP_BAR_WIDTH * ratio
	hp_fill.color = p.hp_full if ratio > LOW_HP_RATIO else p.hp_low
	hp_label.text = "%d / %d" % [max(_last_hp_current, 0), _max_health]

func _on_resource_changed(current: int, max_value: int) -> void:
	var ratio := 0.0 if max_value <= 0 else clampf(float(current) / float(max_value), 0.0, 1.0)
	resource_fill.offset_right = resource_fill.offset_left + RESOURCE_BAR_WIDTH * ratio
	resource_label.text = "%d / %d" % [max(current, 0), max_value]

func _on_player_died() -> void:
	_show_banner(tr("HUD_BANNER_DIED"), 2.0)

func _on_notification_requested(text: String) -> void:
	_show_banner(text, 2.5)

func _on_credits_changed(total: int) -> void:
	# credits_changed carries the running total — diff against the previous
	# value to recover each pickup's delta. A negative delta (spend) just
	# resyncs the baseline without touching the tally.
	var delta := total - _last_credits_seen
	_last_credits_seen = total
	if delta <= 0:
		return
	_loot_tally += delta
	recent_loot_label.text = "+%d cr" % _loot_tally
	recent_loot_label.visible = true
	# Token-based debounce — every new pickup invalidates the prior timer so
	# the window restarts from zero. After LOOT_TALLY_WINDOW seconds with no
	# fresh pickup, the latest token survives the await and clears the tally.
	_loot_tally_token += 1
	var token := _loot_tally_token
	await get_tree().create_timer(LOOT_TALLY_WINDOW).timeout
	if token != _loot_tally_token:
		return
	_loot_tally = 0
	recent_loot_label.visible = false
	recent_loot_label.text = ""

func _on_perk_gained(perk: Perk) -> void:
	_show_banner("%s — %s" % [perk.label, perk.description], 3.0)

func _show_banner(text: String, duration: float) -> void:
	_banner_token += 1
	var token := _banner_token
	banner.text = text
	banner.visible = true
	await get_tree().create_timer(duration).timeout
	if token == _banner_token:
		banner.visible = false
