extends CanvasLayer
class_name PrototypeHud

const HP_BAR_WIDTH := 156.0
const RESOURCE_BAR_WIDTH := 156.0
const LOW_HP_RATIO := 0.35
const HEAL_PREVIEW_COLOR := Color(0.3, 0.85, 0.4, 0.35)
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
@onready var avatar_panel: Control = %AvatarPanel
@onready var avatar_bg: ColorRect = %AvatarBackground
@onready var avatar_border: ReferenceRect = %AvatarBorder
@onready var avatar_image: TextureRect = %AvatarImage
@onready var avatar_placeholder: Label = %AvatarPlaceholder
@onready var level_label: Label = %LevelLabel
@onready var buff_entries: HBoxContainer = %BuffEntries
@onready var debuff_entries: HBoxContainer = %DebuffEntries
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
var _barrier_fill: ColorRect = null
const BARRIER_FILL_COLOR := Color(0.5, 0.85, 1.0, 0.45)
var _banner_token: int = 0
# Shield buff state cache, populated by player's shield_buff_changed
# signal. Drives the white outline around the HP bar (visible when
# active OR on cooldown) and the buff-bar "Shield" entry's tooltip.
var _hp_ghost: ColorRect = null
var _hp_ghost_right: float = 0.0
var _hp_ghost_hold: float = 0.0
var _resource_ghost: ColorRect = null
var _resource_ghost_right: float = 0.0
var _resource_ghost_hold: float = 0.0
const GHOST_HOLD_TIME := 0.4        # seconds to hold before draining
const GHOST_DRAIN_SPEED := 200.0    # pixels per second
const GHOST_HP_COLOR := Color(1.0, 0.3, 0.2, 0.25)
const GHOST_RESOURCE_COLOR := Color(0.4, 0.6, 0.9, 0.25)

var _shield_state: Dictionary = {"active": false, "pool": 0, "pool_max": 0, "reduction": 0.0, "cooldown_remain": 0.0, "cooldown_total": 0.0, "duration_remain": 0.0}
var _shield_outline: ReferenceRect = null
var _shield_overlay: ColorRect = null
var _heal_preview: ColorRect = null
# White → red lerp colours for the HP-bar outline. Above
# _SHIELD_OUTLINE_RED_THRESHOLD the outline stays full white;
# below, it lerps toward red so the player can see the shield
# nearing collapse without staring at the buff bar.
const _SHIELD_OUTLINE_FULL := Color.WHITE
const _SHIELD_OUTLINE_BREAK := Color(1.0, 0.18, 0.18, 1.0)
const _SHIELD_OUTLINE_COOLDOWN := Color(1.0, 1.0, 1.0, 0.35)
# A dim cyan tint for SHIELD_HOLD released-with-pool: communicates
# "ready to redeploy" without competing visually with the bright
# active-block colour or the dim white cooldown state.
const _SHIELD_OUTLINE_HOLD_READY := Color(0.6, 0.85, 1.0, 0.45)
const _SHIELD_OUTLINE_RED_THRESHOLD := 0.5
var _debug_overlay_accum: float = 0.0
var _state_flashlight: bool = false
var _state_crouch: bool = false
var _minimap: Minimap
var _controls_panel: PanelContainer
var _talent_btn: Button
var _talent_btn_glow_phase: float = 0.0
# Loot tally state: signal carries the running total, not the delta, so we
# diff it against the last seen value to derive each pickup amount.
var _last_credits_seen: int = 0
var _loot_tally: int = 0
var _loot_tally_token: int = 0

func _ready() -> void:
	add_to_group(&"hud")
	_apply_theme()
	_build_heal_preview()
	_build_ghost_fills()
	_build_barrier_fill()
	_update_avatar_panel()
	_repaint_xp(PlayerState.xp, PlayerState.xp_to_next)
	UIThemeState.changed.connect(_apply_theme)
	PlayerState.level_changed.connect(_on_level_changed)
	PlayerState.xp_changed.connect(_repaint_xp)
	# Buffs bar repopulates on any of the signals that can shift the active
	# perk set: gear swap (stats), tier crossing, class/spec change. PerkState
	# already collapses these into its own perks_changed, but we hook the
	# upstream signals too so display stays accurate even if PerkState is
	# briefly out of sync during a recompute cycle.
	PerkState.perks_changed.connect(_update_buffs_bar)
	PlayerState.class_changed.connect(_on_class_or_spec_changed)
	PlayerState.spec_changed.connect(_on_class_or_spec_changed)
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
		player.charm_count_changed.connect(_on_charm_count_changed)
	if player.has_signal(&"shield_buff_changed"):
		player.shield_buff_changed.connect(_on_shield_buff_changed)
	if player.has_signal(&"slow_pool_changed"):
		player.slow_pool_changed.connect(_on_slow_pool_changed)
	if player.has_signal(&"weapon_ammo_changed"):
		player.weapon_ammo_changed.connect(_on_weapon_ammo_changed)
	# Equipment changes drive ammo widget visibility too — swapping to a
	# laser pistol from an LMG should hide the count.
	InventoryState.equipment_changed.connect(_on_ammo_equipment_changed)
	_build_ammo_widget()
	_refresh_ammo_widget()
	if player.has_signal(&"credits_changed"):
		_last_credits_seen = int(player.get_credits()) if player.has_method(&"get_credits") else 0
		player.credits_changed.connect(_on_credits_changed)
	PerkState.perk_gained.connect(_on_perk_gained)
	_on_health_changed(_max_health, _max_health)
	_build_shield_outline()
	_bind_skill_slots(player)
	_bind_resource_pool(player)
	_build_minimap(player)
	_build_controls_panel()
	_build_talents_panel()
	_build_talent_point_button()
	PlayerState.talents_changed.connect(_refresh_talent_button)
	PlayerState.leveled_up.connect(_on_leveled_up)
	# Click anywhere on the avatar panel (outside the + button, which has
	# its own STOP filter) opens the character sheet — same affordance as
	# pressing I/C. Avatar panel mouse_filter is STOP in the .tscn.
	if avatar_panel != null:
		avatar_panel.gui_input.connect(_on_avatar_clicked)

func _exit_tree() -> void:
	UIThemeState.changed.disconnect(_apply_theme)
	PlayerState.level_changed.disconnect(_on_level_changed)
	PlayerState.xp_changed.disconnect(_repaint_xp)
	PerkState.perks_changed.disconnect(_update_buffs_bar)
	PlayerState.class_changed.disconnect(_on_class_or_spec_changed)
	PlayerState.spec_changed.disconnect(_on_class_or_spec_changed)
	PerkState.perk_gained.disconnect(_on_perk_gained)
	PlayerState.talents_changed.disconnect(_refresh_talent_button)
	PlayerState.leveled_up.disconnect(_on_leveled_up)
	if InventoryState.equipment_changed.is_connected(_on_equipment_changed):
		InventoryState.equipment_changed.disconnect(_on_equipment_changed)
	if TalentState.granted_skills_changed.is_connected(_on_granted_skills_changed):
		TalentState.granted_skills_changed.disconnect(_on_granted_skills_changed)


func _on_level_changed(_new: int, _old: int) -> void:
	_update_avatar_panel()


func _on_class_or_spec_changed(_id: StringName) -> void:
	_update_buffs_bar()


func _on_charm_count_changed(_c: int, _m: int) -> void:
	_update_buffs_bar()


func _on_leveled_up(_lv: int, _hp: int) -> void:
	_refresh_talent_button()


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
# Each entry is a small colored panel hoverable for a tooltip showing
# the perk's label + description.
const _BUFF_ENTRY_SIZE := Vector2(14.0, 14.0)
func _update_buffs_bar() -> void:
	if buff_entries == null:
		return
	for child in buff_entries.get_children():
		child.queue_free()
	if PlayerState.class_id == &"":
		return
	# Show only the highest active perk per tree (tiers replace, not stack).
	var best_per_tree: Dictionary = {}  # stat_id → {tier, perk}
	for perk: Perk in PerkState.get_active_perks():
		if perk == null:
			continue
		var id_parts := String(perk.id).split("_t")
		if id_parts.size() != 2:
			continue
		var stat_id := StringName(id_parts[0])
		var tier := int(id_parts[1])
		if tier <= 0:
			continue
		var prev: Dictionary = best_per_tree.get(stat_id, {})
		if prev.is_empty() or tier > int(prev["tier"]):
			best_per_tree[stat_id] = {"tier": tier, "perk": perk}
	for stat_id: StringName in best_per_tree.keys():
		var entry: Dictionary = best_per_tree[stat_id]
		_add_buff_entry(stat_id, int(entry["tier"]), entry["perk"] as Perk)
	# Active offhand: SHIELD_BUFF gets its own buff-bar entry while
	# active so the player can see the % reduction and the remaining
	# pool. Cooldown state is communicated via the HP-bar outline
	# rather than a separate entry — keeps the buff bar focused on
	# things actively benefitting the player.
	if _shield_state.get("active", false):
		_add_shield_buff_entry()


# Rebuilds the right-aligned debuffs bar. Currently only the Slowed
# debuff (slow-pool overlap) lives here, but the same pattern handles
# any future negative status — burns, weakens, etc. would each add an
# entry the same way.
func _update_debuffs_bar() -> void:
	if debuff_entries == null:
		return
	for child in debuff_entries.get_children():
		child.queue_free()
	var player := get_tree().get_first_node_in_group(&"player") as PrototypePlayer
	if player == null or not is_instance_valid(player):
		return
	if player.is_in_slow_pool():
		_add_slow_debuff_entry()


func _on_slow_pool_changed(_in_pool: bool) -> void:
	_update_debuffs_bar()


# Ammo widget — yellow bar stacked above the resource bar. When a
# bullet weapon is equipped both bars share the resource container 50/50;
# when no bullet weapon is equipped the resource bar gets full height.
# The yellow fill represents ammo remaining (current/max ratio); during
# reload it instead sweeps 0→100% as the reload progresses.
var _ammo_fill: ColorRect = null
var _ammo_label: Label = null
var _ammo_built: bool = false

const _AMMO_FILL_COLOR := Color(0.95, 0.78, 0.25, 1.0)

func _build_ammo_widget() -> void:
	if _ammo_built or resource_fill == null:
		return
	var container := resource_fill.get_parent() as Control
	if container == null:
		return
	var fill := ColorRect.new()
	fill.name = "AmmoFill"
	fill.color = _ammo_fill_color_for(false)
	# Mirror ResourceFill positioning but anchor to the TOP half of the
	# container (anchor_top=0, anchor_bottom=0.5). offset_left=2 / -2 keeps
	# the fill inside the 1px border.
	fill.anchor_left = 0.0
	fill.anchor_right = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 0.5
	fill.offset_left = 2.0
	fill.offset_right = 2.0
	fill.offset_top = 2.0
	fill.offset_bottom = 0.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.visible = false
	container.add_child(fill)
	_ammo_fill = fill
	var lbl := Label.new()
	lbl.name = "AmmoLabel"
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.0
	lbl.anchor_bottom = 0.5
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override(&"font_size", 9)
	lbl.add_theme_color_override(&"font_color", Color(1.0, 0.95, 0.85, 1.0))
	lbl.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override(&"outline_size", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.visible = false
	container.add_child(lbl)
	_ammo_label = lbl
	_ammo_built = true


# Distinct colour while reloading so the bar reads as "filling up" vs
# "draining as you fire". Both are yellow but the reload tone is dimmer
# so a glance can tell them apart even without the label.
func _ammo_fill_color_for(reloading: bool) -> Color:
	if reloading:
		return Color(0.85, 0.55, 0.15, 0.95)
	return _AMMO_FILL_COLOR


# Repaints the ammo widget to reflect the current main-weapon state.
# Called on weapon_ammo_changed (shot fired / reload finished) and on
# equipment_changed (weapon swap). When no bullet weapon is equipped
# the ammo overlay hides and the resource bar reclaims full height.
func _refresh_ammo_widget() -> void:
	if not _ammo_built:
		return
	var w: Item = InventoryState.get_equipped(&"weapon")
	var has_ammo := w != null and w.is_bullet_weapon()
	# Resize resource fill / label vertically to share the container
	# 50/50 with the ammo bar, or take the full container when no
	# bullet weapon is equipped (so energy users see the unchanged bar).
	resource_fill.anchor_top = 0.5 if has_ammo else 0.0
	resource_fill.offset_top = 0.0 if has_ammo else 2.0
	resource_label.anchor_top = 0.5 if has_ammo else 0.0
	_ammo_fill.visible = has_ammo
	_ammo_label.visible = has_ammo
	if not has_ammo:
		return
	var player := get_tree().get_first_node_in_group(&"player") as PrototypePlayer
	var reloading := player != null and player.is_reloading()
	var ratio: float = 0.0
	var text: String = ""
	if reloading:
		ratio = player.get_reload_progress()
		text = "RELOADING"
	else:
		ratio = float(w.ammo_current) / float(maxi(1, w.ammo_max))
		text = "%d / %d" % [w.ammo_current, w.ammo_max]
	_ammo_fill.color = _ammo_fill_color_for(reloading)
	_ammo_fill.offset_right = _ammo_fill.offset_left + RESOURCE_BAR_WIDTH * ratio
	_ammo_label.text = text


func _on_weapon_ammo_changed() -> void:
	_refresh_ammo_widget()


func _on_ammo_equipment_changed(slot: StringName) -> void:
	if slot == &"weapon":
		_refresh_ammo_widget()


# Tick the reload-progress fill while reloading — the player emits
# weapon_ammo_changed only on start/finish, so we poll _process for the
# in-between fill animation. Cheap: just one width update per frame.
func _process_ammo_fill() -> void:
	if not _ammo_built or not _ammo_fill.visible:
		return
	var player := get_tree().get_first_node_in_group(&"player") as PrototypePlayer
	if player == null or not player.is_reloading():
		return
	_ammo_fill.offset_right = _ammo_fill.offset_left + RESOURCE_BAR_WIDTH * player.get_reload_progress()



# Slowed debuff entry: red "S" glyph with a Traction-aware tooltip body
# so the player can see how much speed they're losing right now (which
# scales with their boots' traction stat).
func _add_slow_debuff_entry() -> void:
	var entry := Control.new()
	entry.custom_minimum_size = _BUFF_ENTRY_SIZE
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	entry.set_meta(&"buff_stat_id", &"slow_pool")
	var label := Label.new()
	label.text = "S"
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", Color(1.0, 0.5, 0.45, 1.0))
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override(&"outline_size", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(label)
	entry.mouse_entered.connect(func() -> void:
		var traction: int = Traction.get_player_traction()
		var factor: float = Traction.slow_factor_for(traction)
		var slow_pct: int = int(round((1.0 - factor) * 100.0))
		var title := "Slowed"
		var body: String
		if slow_pct > 0:
			body = "Move speed −%d%% from a liquid pool.\n• Traction: %d (more reduces this)" % [slow_pct, traction]
		else:
			body = "Standing in a liquid pool, but your traction fully mitigates the slow."
		get_tree().call_group(&"interactable_tooltip", &"show_talent_node", title, body))
	entry.mouse_exited.connect(func() -> void:
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip"))
	debuff_entries.add_child(entry)


func _add_buff_entry(stat_id: StringName, tier: int, perk: Perk) -> void:
	var stat_color: Color = AttributeState.color_for_id(stat_id)
	# No background, no border — entry is just the tier roman painted in
	# the class color. Wrapping in a Control so mouse_filter STOP still
	# catches hover events for the tooltip without a visible panel.
	var entry := Control.new()
	entry.custom_minimum_size = _BUFF_ENTRY_SIZE
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	# Tag with stat_id so the perk-pip animation can find this entry's
	# screen position to land on when a new perk unlocks.
	entry.set_meta(&"buff_stat_id", stat_id)
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


# Buff-bar entry for an active SHIELD_BUFF offhand. Reads from
# _shield_state — the entry is only added when active, so live values
# (pool / pool_max / reduction) are guaranteed to be set. Tooltip
# rebuilds lazily on hover so the pool count stays accurate as the
# shield absorbs hits between hover-enters.
func _add_shield_buff_entry() -> void:
	var entry := Control.new()
	entry.custom_minimum_size = _BUFF_ENTRY_SIZE
	entry.mouse_filter = Control.MOUSE_FILTER_STOP
	entry.set_meta(&"buff_stat_id", &"shield_buff")
	var label := Label.new()
	label.text = "S"  # placeholder glyph; could swap for an icon
	label.add_theme_font_size_override(&"font_size", 12)
	label.add_theme_color_override(&"font_color", Color.WHITE)
	label.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override(&"outline_size", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(label)
	entry.mouse_entered.connect(func() -> void:
		var pct: int = int(round(float(_shield_state.get("reduction", 0.0)) * 100.0))
		var pool: int = int(_shield_state.get("pool", 0))
		var pool_max: int = int(_shield_state.get("pool_max", 0))
		# Differentiate label/body by archetype. Live kind comes from
		# the player so swapping offhand mid-hover would reflect
		# correctly (cleared on unequip via clear_shield_buff anyway).
		var player := get_tree().get_first_node_in_group(&"player") as PrototypePlayer
		var kind := player.get_shield_buff_kind() if player != null else Skill.ActiveKind.NONE
		var title: String
		var body: String
		if kind == Skill.ActiveKind.SHIELD_HOLD:
			title = "Active Shield"
			body = "Hold RMB to block 100%% of incoming damage.\n• %d / %d shield pool" % [pool, pool_max]
		else:
			title = "Shield Generator"
			body = "Reduces incoming damage by %d%%.\n• %d / %d shield pool" % [pct, pool, pool_max]
		get_tree().call_group(&"interactable_tooltip", &"show_talent_node", title, body))
	entry.mouse_exited.connect(func() -> void:
		get_tree().call_group(&"interactable_tooltip", &"hide_tooltip"))
	buff_entries.add_child(entry)


# Returns [title, body] for the buff tooltip. Body is the perk's
# authored description followed by a compact bullet list of live
# mechanical contributors. Line text comes from EffectFormatter so the
# HUD doesn't have to know about the per-spec mechanics — adding a
# new effect kind is one place to edit. Built lazily on hover so the
# numbers reflect current stats / talent allocations.
func _build_buff_tooltip(stat_id: StringName, tier: int, perk: Perk) -> Array:
	var title: String
	var body: String
	if perk != null:
		title = "%s  ·  %s" % [perk.label, AttributeState.TIER_ROMAN[tier - 1]]
		body = perk.description
	else:
		var stat_name: String = String(stat_id).capitalize()
		title = "%s  ·  %s" % [stat_name, AttributeState.TIER_ROMAN[tier - 1]]
		body = "Tier %s perk — no description available." % AttributeState.TIER_ROMAN[tier - 1]
	var player := get_tree().get_first_node_in_group(&"player") as PrototypePlayer
	for line in EffectFormatter.buff_lines_for_stat(stat_id, player):
		body += "\n• " + line
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
	# Update scanner radar overlay when the light toggles or head item changes.
	if _minimap != null:
		var player := get_tree().get_first_node_in_group(&"player")
		if player != null and player.has_method(&"is_scanner_active"):
			_minimap.scanner_active = player.is_scanner_active()

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
	_position_controls_panel()
	_pulse_talent_button(delta)
	_process_ammo_fill()
	_update_heal_preview()
	_drain_ghost_fills(delta)
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
	# and shows nothing for the new one). Also re-bind the keyboard slots
	# when a talent grants/revokes an active skill — granted skills win
	# over the player's @export skills array, so allocating a "Sanctify"
	# node should immediately swap the icon and cooldown the slot tracks.
	if not InventoryState.equipment_changed.is_connected(_on_equipment_changed):
		InventoryState.equipment_changed.connect(_on_equipment_changed.bind(player))
	if not TalentState.granted_skills_changed.is_connected(_on_granted_skills_changed):
		TalentState.granted_skills_changed.connect(_on_granted_skills_changed.bind(player))


func _on_equipment_changed(slot_name: StringName, player: Node) -> void:
	if slot_name == &"consumable":
		# Consumable equip/unequip changes Q slot (visual slot 4).
		_rebind_slot(4, player)
		return
	if slot_name != &"weapon" and slot_name != &"offhand":
		return
	# Only rebind LMB (visual slot 6) and RMB (visual slot 7) — the
	# keyboard slots aren't touched by equipment changes.
	for i in [6, 7]:
		_rebind_slot(i, player)


func _on_granted_skills_changed(player: Node) -> void:
	# Keyboard slots only (0..5 = keys 1,2,3,4,Q,E). LMB/RMB are
	# weapon-driven and never touched by talent grants.
	for i in 6:
		_rebind_slot(i, player)


func _rebind_slot(visual_slot: int, player: Node) -> void:
	var slot := skill_bar.get_node_or_null("Slot%d" % visual_slot) as SkillSlot
	if slot == null:
		return
	var skill_idx: int = SLOT_TO_SKILL_INDEX[visual_slot]
	var skill: Skill = player.resolve_skill(skill_idx) if player.has_method(&"resolve_skill") else null
	slot.bind(player, skill, SLOT_LABELS[visual_slot])

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

func _build_controls_panel() -> void:
	# Hide the old full-width hints label at the top of the screen.
	var old_hints := root.get_node_or_null(^"HotkeyHints")
	if old_hints != null:
		old_hints.visible = false

	# Small translucent panel anchored below the minimap in the top-right.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.05, 0.82)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override(&"panel", style)

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override(&"normal_font_size", 6)
	label.add_theme_font_size_override(&"bold_font_size", 6)
	label.add_theme_constant_override(&"line_separation", -1)
	label.add_theme_color_override(&"default_color", Color(0.7, 0.85, 1.0, 0.7))

	var key_color := "#8ab4d8"
	# Vertical layout — one keybind per line for readability.
	var text := ""
	text += "[color=%s]WASD[/color] Move\n" % key_color
	text += "[color=%s]LMB[/color] Fire\n" % key_color
	text += "[color=%s]RMB[/color] Skill\n" % key_color
	text += "[color=%s]Space[/color] Jump\n" % key_color
	text += "[color=%s]Shift[/color] Sprint\n" % key_color
	text += "[color=%s]Ctrl[/color] Crouch\n" % key_color
	text += "[color=%s]R[/color] Reload\n" % key_color
	text += "[color=%s]F[/color] Light\n" % key_color
	text += "[color=%s]1-4/Q/E[/color] Skills\n" % key_color
	text += "[color=%s]I/C[/color] Inventory\n" % key_color
	text += "[color=%s]N[/color] Talents\n" % key_color
	text += "[color=%s]Tab[/color] Map\n" % key_color
	text += "[color=%s]V[/color] View\n" % key_color
	text += "[color=%s]Esc[/color] Menu" % key_color
	label.text = text
	panel.add_child(label)
	root.add_child(panel)

	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_controls_panel = panel

func _position_controls_panel() -> void:
	if _controls_panel == null or _controls_panel.size.x < 1.0:
		return
	var margin := Minimap.CORNER_MARGIN
	# Top-left of the screen. The top-right slot under the minimap now
	# belongs to the weapon-quirk reminder panel, which is the more
	# frequently-read in-play widget; control hints are reference info
	# and live better in the corner.
	_controls_panel.position = Vector2(margin, margin)

func _build_talents_panel() -> void:
	var talents := TalentsPanel.new()
	root.add_child(talents)

func _build_talent_point_button() -> void:
	# Glowing "+" that appears in the upper-right of the avatar panel when
	# unspent talent points are available. Clicking it opens the talents
	# panel (same as N). Pulses via _pulse_talent_button each frame.
	var btn := Button.new()
	btn.text = "+"
	btn.flat = true
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override(&"font_size", 28)
	btn.add_theme_color_override(&"font_color", Color(0.4, 1.0, 0.5, 1.0))
	btn.add_theme_color_override(&"font_hover_color", Color(0.6, 1.0, 0.7, 1.0))
	btn.add_theme_color_override(&"font_pressed_color", Color(0.8, 1.0, 0.85, 1.0))
	# Outline-as-glow: a thick same-hue outline reads as a soft halo around
	# the glyph at avatar scale. Combined with the pulse, the "+" feels
	# like an alert beacon rather than a stray glyph.
	btn.add_theme_color_override(&"font_outline_color", Color(0.4, 1.0, 0.5, 0.9))
	btn.add_theme_constant_override(&"outline_size", 8)
	# Anchor top-right of the AvatarPanel. AvatarPanel is 90×90; button is
	# ~30×30 sitting just inside the corner so it doesn't crowd the border.
	btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btn.offset_left = -32.0
	btn.offset_right = -2.0
	btn.offset_top = -2.0
	btn.offset_bottom = 28.0
	btn.tooltip_text = "Unallocated talent points (N)"
	btn.pressed.connect(_on_talent_button_pressed)
	# Add to AvatarPanel so it anchors to the same bottom-center region.
	var avatar_panel := root.get_node_or_null(^"AvatarPanel")
	if avatar_panel != null:
		avatar_panel.add_child(btn)
	else:
		root.add_child(btn)
	_talent_btn = btn
	_refresh_talent_button()

func _refresh_talent_button() -> void:
	if _talent_btn == null:
		return
	var available := PlayerState.talent_points_total - PlayerState.get_talent_points_spent()
	_talent_btn.visible = available > 0

func _pulse_talent_button(delta: float) -> void:
	if _talent_btn == null or not _talent_btn.visible:
		return
	_talent_btn_glow_phase += delta * 3.0
	# Pulse the green color's brightness between 0.6 and 1.0 on the glyph,
	# AND oscillate the outline alpha so the halo "breathes" — reads as a
	# beacon at the corner of the avatar instead of a static glyph.
	var t := 0.5 + 0.5 * sin(_talent_btn_glow_phase)
	var brightness := lerpf(0.6, 1.0, t)
	_talent_btn.add_theme_color_override(&"font_color", Color(0.4 * brightness, 1.0 * brightness, 0.5 * brightness, 1.0))
	var outline_alpha := lerpf(0.35, 0.95, t)
	_talent_btn.add_theme_color_override(&"font_outline_color", Color(0.4, 1.0, 0.5, outline_alpha))

func _on_talent_button_pressed() -> void:
	# Simulate opening the talents panel — same as pressing N.
	for node in get_tree().get_nodes_in_group(&"ui_modal"):
		if node is TalentsPanel:
			if not node.visible:
				node.open_menu()
			return


func _on_avatar_clicked(event: InputEvent) -> void:
	# Left click on the avatar (excluding the talent + button which has its
	# own STOP filter) opens the character sheet. Same affordance as the
	# I/C hotkey — discoverable for mouse-only players.
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	for node in get_tree().get_nodes_in_group(&"ui_modal"):
		if node is CharacterPanel:
			if not node.visible:
				node.open_menu()
			return

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
	var new_right := hp_fill.offset_left + HP_BAR_WIDTH * ratio
	# Ghost: on damage, show the lost region (from new fill edge to old edge)
	# as a bright bar that holds briefly then shrinks from the right.
	if _hp_ghost != null:
		if new_right < hp_fill.offset_right:
			# Damage — ghost covers the gap between new and old fill.
			_hp_ghost.offset_left = new_right
			_hp_ghost.offset_right = maxf(_hp_ghost_right, hp_fill.offset_right)
			_hp_ghost_right = _hp_ghost.offset_right
			_hp_ghost_hold = GHOST_HOLD_TIME
			_hp_ghost.visible = true
		elif not _hp_ghost.visible:
			# No active ghost and health rose — just track position.
			_hp_ghost_right = new_right
	hp_fill.offset_right = new_right
	hp_fill.color = p.hp_full if ratio > LOW_HP_RATIO else p.hp_low
	hp_label.text = "%d / %d" % [max(_last_hp_current, 0), _max_health]
	_update_barrier_fill()
	_update_heal_preview()


func _build_heal_preview() -> void:
	if hp_fill == null:
		return
	_heal_preview = ColorRect.new()
	_heal_preview.color = HEAL_PREVIEW_COLOR
	_heal_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heal_preview.visible = false
	_heal_preview.anchor_bottom = 1.0
	# Insert right after hp_fill so preview draws on top of the fill
	# (the green zone extends past the current fill into the empty area).
	var container := hp_fill.get_parent()
	container.add_child(_heal_preview)
	container.move_child(_heal_preview, hp_fill.get_index() + 1)


func _build_ghost_fills() -> void:
	# HP ghost — on damage, shows the "lost HP" region as a bright bar that
	# holds briefly then drains. Sits ON TOP of hp_fill (right after it in
	# child order) so it draws over the background in the gap.
	if hp_fill != null:
		_hp_ghost = ColorRect.new()
		_hp_ghost.color = GHOST_HP_COLOR
		_hp_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hp_ghost.visible = false
		_hp_ghost.anchor_bottom = hp_fill.anchor_bottom
		_hp_ghost.offset_top = hp_fill.offset_top
		_hp_ghost.offset_bottom = hp_fill.offset_bottom
		var container := hp_fill.get_parent()
		container.add_child(_hp_ghost)
		# Right after hp_fill in draw order so it layers on top of bg.
		container.move_child(_hp_ghost, hp_fill.get_index() + 1)
		_hp_ghost_right = hp_fill.offset_right
	# Resource ghost — same pattern.
	if resource_fill != null:
		_resource_ghost = ColorRect.new()
		_resource_ghost.color = GHOST_RESOURCE_COLOR
		_resource_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_resource_ghost.visible = false
		_resource_ghost.anchor_top = resource_fill.anchor_top
		_resource_ghost.anchor_bottom = resource_fill.anchor_bottom
		_resource_ghost.offset_top = resource_fill.offset_top
		_resource_ghost.offset_bottom = resource_fill.offset_bottom
		var container := resource_fill.get_parent()
		container.add_child(_resource_ghost)
		container.move_child(_resource_ghost, resource_fill.get_index() + 1)
		_resource_ghost_right = resource_fill.offset_right


func _update_barrier_fill() -> void:
	if _barrier_fill == null:
		return
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null or not player.has_method(&"get_barrier"):
		_barrier_fill.visible = false
		return
	var barrier: int = player.get_barrier()
	if barrier <= 0:
		_barrier_fill.visible = false
		return
	# Barrier sits at the right edge of the HP fill as a cyan extension.
	var barrier_ratio := clampf(float(barrier) / float(_max_health), 0.0, 1.0)
	var hp_right := hp_fill.offset_right
	var barrier_width := HP_BAR_WIDTH * barrier_ratio
	# Clamp so barrier + HP doesn't exceed the bar.
	var max_right := hp_fill.offset_left + HP_BAR_WIDTH
	_barrier_fill.offset_left = hp_right
	_barrier_fill.offset_right = minf(hp_right + barrier_width, max_right)
	_barrier_fill.visible = true


func _build_barrier_fill() -> void:
	if hp_fill == null:
		return
	_barrier_fill = ColorRect.new()
	_barrier_fill.color = BARRIER_FILL_COLOR
	_barrier_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_barrier_fill.visible = false
	_barrier_fill.anchor_bottom = hp_fill.anchor_bottom
	_barrier_fill.offset_top = hp_fill.offset_top
	_barrier_fill.offset_bottom = hp_fill.offset_bottom
	var container := hp_fill.get_parent()
	container.add_child(_barrier_fill)
	# Draw on top of hp_fill so the cyan segment is visible.
	container.move_child(_barrier_fill, hp_fill.get_index() + 1)


func _drain_ghost_fills(delta: float) -> void:
	if _hp_ghost != null and _hp_ghost.visible:
		if _hp_ghost_hold > 0.0:
			_hp_ghost_hold -= delta
		else:
			# Shrink from the right toward the fill edge (left).
			_hp_ghost.offset_right = move_toward(_hp_ghost.offset_right, _hp_ghost.offset_left, GHOST_DRAIN_SPEED * delta)
			if _hp_ghost.offset_right <= _hp_ghost.offset_left:
				_hp_ghost.visible = false
				_hp_ghost_right = hp_fill.offset_right
	if _resource_ghost != null and _resource_ghost.visible:
		if _resource_ghost_hold > 0.0:
			_resource_ghost_hold -= delta
		else:
			_resource_ghost.offset_right = move_toward(_resource_ghost.offset_right, _resource_ghost.offset_left, GHOST_DRAIN_SPEED * delta)
			if _resource_ghost.offset_right <= _resource_ghost.offset_left:
				_resource_ghost.visible = false
				_resource_ghost_right = resource_fill.offset_right


func _update_heal_preview() -> void:
	if _heal_preview == null:
		return
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null or not player.has_method(&"get_potion_heal_remaining"):
		_heal_preview.visible = false
		return
	var heal_remain: int = player.get_potion_heal_remaining()
	if heal_remain <= 0:
		_heal_preview.visible = false
		return
	var current_ratio := clampf(float(_last_hp_current) / float(_max_health), 0.0, 1.0)
	var projected := mini(_last_hp_current + heal_remain, _max_health)
	var projected_ratio := clampf(float(projected) / float(_max_health), 0.0, 1.0)
	if projected_ratio <= current_ratio:
		_heal_preview.visible = false
		return
	# Start the preview at current HP fill edge, extend to projected HP.
	_heal_preview.offset_left = hp_fill.offset_left + HP_BAR_WIDTH * current_ratio
	_heal_preview.offset_top = hp_fill.offset_top
	_heal_preview.offset_right = hp_fill.offset_left + HP_BAR_WIDTH * projected_ratio
	_heal_preview.offset_bottom = hp_fill.offset_bottom
	_heal_preview.visible = true

func _on_resource_changed(current: int, max_value: int) -> void:
	var ratio := 0.0 if max_value <= 0 else clampf(float(current) / float(max_value), 0.0, 1.0)
	var new_right := resource_fill.offset_left + RESOURCE_BAR_WIDTH * ratio
	if _resource_ghost != null:
		if new_right < resource_fill.offset_right:
			_resource_ghost.offset_left = new_right
			_resource_ghost.offset_right = maxf(_resource_ghost_right, resource_fill.offset_right)
			_resource_ghost_right = _resource_ghost.offset_right
			_resource_ghost_hold = GHOST_HOLD_TIME
			_resource_ghost.visible = true
		elif not _resource_ghost.visible:
			_resource_ghost_right = new_right
	resource_fill.offset_right = new_right
	resource_label.text = "%d / %d" % [max(current, 0), max_value]

func _on_player_died() -> void:
	pass


# Build a 1px white outline that tracks the HP bar's frame. Visible
# whenever the shield buff is active OR on cooldown — the colour
# difference between active (full white) and cooldown (dim) reads
# without a label.
func _build_shield_outline() -> void:
	if hp_bg == null:
		return
	_shield_outline = ReferenceRect.new()
	_shield_outline.editor_only = false
	_shield_outline.border_color = Color.WHITE
	_shield_outline.border_width = 2.0
	_shield_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Inset 2px on every side so the white shield ring sits INSIDE the
	# HP container's own 2px blue border. The HP fill is also inset by
	# 2px (set in the .tscn), so the shield ring layers between them —
	# the player sees the existing HUD border, then the shield ring,
	# then the fill, all stacked outward-to-inward.
	_shield_outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shield_outline.offset_left = 2.0
	_shield_outline.offset_top = 2.0
	_shield_outline.offset_right = -2.0
	_shield_outline.offset_bottom = -2.0
	_shield_outline.visible = false
	hp_bg.get_parent().add_child(_shield_outline)

	# White overlay bar — covers the HP fill when SHIELD_HOLD (full block)
	# is active, signaling "your HP is fully protected." Width tracks the
	# shield pool ratio so the player sees the absorb pool drain. Sits above
	# the HP fill in z-order via add_child ordering.
	_shield_overlay = ColorRect.new()
	_shield_overlay.color = Color(1.0, 1.0, 1.0, 0.35)
	_shield_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shield_overlay.visible = false
	# Same inset as hp_fill so it layers directly on top.
	_shield_overlay.offset_left = hp_fill.offset_left
	_shield_overlay.offset_top = hp_fill.offset_top
	_shield_overlay.offset_right = hp_fill.offset_right
	_shield_overlay.offset_bottom = hp_fill.offset_bottom
	hp_bg.get_parent().add_child(_shield_overlay)


func _on_shield_buff_changed(active: bool, pool: int, pool_max: int, reduction: float, cooldown_remain: float, cooldown_total: float, duration_remain: float) -> void:
	_shield_state = {
		"active": active,
		"pool": pool,
		"pool_max": pool_max,
		"reduction": reduction,
		"cooldown_remain": cooldown_remain,
		"cooldown_total": cooldown_total,
		"duration_remain": duration_remain,
	}
	if _shield_outline != null:
		var player := get_tree().get_first_node_in_group(&"player") as PrototypePlayer
		var kind := player.get_shield_buff_kind() if player != null else Skill.ActiveKind.NONE
		var has_pool: bool = pool > 0 and pool_max > 0
		var hold_ready: bool = kind == Skill.ActiveKind.SHIELD_HOLD and not active and has_pool and cooldown_remain <= 0.0
		# Visible when active (white→red as pool depletes), recovering
		# (dim white), or HOLD-ready-with-partial-pool (dim cyan).
		# Hidden when no offhand, or just cleared.
		var show: bool = active or cooldown_remain > 0.0 or hold_ready
		_shield_outline.visible = show
		# Thicker border for Amp Shield (partial DR) so it reads at a glance.
		_shield_outline.border_width = 3.0 if kind == Skill.ActiveKind.SHIELD_BUFF else 2.0
		if show:
			if active and pool_max > 0:
				# Lerp from white to red below the threshold; full white
				# above. Pool ratio of 0 = full red (about to break);
				# ratio at threshold = full white. Linear in between.
				var ratio: float = clampf(float(pool) / float(pool_max), 0.0, 1.0)
				if ratio >= _SHIELD_OUTLINE_RED_THRESHOLD:
					_shield_outline.border_color = _SHIELD_OUTLINE_FULL
				else:
					var t: float = 1.0 - (ratio / _SHIELD_OUTLINE_RED_THRESHOLD)
					_shield_outline.border_color = _SHIELD_OUTLINE_FULL.lerp(_SHIELD_OUTLINE_BREAK, t)
			elif hold_ready:
				_shield_outline.border_color = _SHIELD_OUTLINE_HOLD_READY
			else:
				_shield_outline.border_color = _SHIELD_OUTLINE_COOLDOWN

	# White overlay for SHIELD_HOLD — covers the HP bar to signal full
	# protection. Width tracks pool ratio so the bar visually drains.
	if _shield_overlay != null:
		var shield_reduction: float = _shield_state.get("reduction", 0.0)
		var is_hold_active: bool = active and pool_max > 0 and shield_reduction >= 1.0
		_shield_overlay.visible = is_hold_active
		if is_hold_active:
			var pool_ratio := clampf(float(pool) / float(pool_max), 0.0, 1.0)
			_shield_overlay.offset_right = _shield_overlay.offset_left + HP_BAR_WIDTH * pool_ratio
	# Buff bar shows the live shield as an entry; rebuild so the tooltip
	# is current. The bar is at most ~7 entries — cheap.
	_update_buffs_bar()

func _on_notification_requested(text: String) -> void:
	# Hold duration is fully-opaque time; the slow alpha fade-out adds
	# another ~1.8s where the text is still readable. Total perceived
	# read window ≈ 3.5 + 1.8 = ~5.3s.
	_show_banner(text, 3.5)

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
	# Defer one frame so PerkState.perks_changed → _update_buffs_bar
	# has a chance to (re)build the entry we want to land on. Without
	# this, the lookup in _animate_perk_pip can run before the entry
	# exists and fall through to the centre-screen fallback.
	call_deferred(&"_animate_perk_pip", perk)


# Spawn a large stat-coloured tier roman that flies into the matching
# buff-bar entry. Replaces the old centre-screen banner — keeps the
# "you got something" feedback without parking a multi-second wall of
# text over the action. Total runtime ~1.4s including hold + fade.
const _PIP_TRAVEL_DURATION := 0.85
const _PIP_HOLD := 0.25
const _PIP_FADE := 0.30
const _PIP_START_FONT_SIZE := 56
const _PIP_END_FONT_SIZE := 14
const _PIP_START_OFFSET := Vector2(0.0, -120.0)  # screen-space, relative to viewport center

func _animate_perk_pip(perk: Perk) -> void:
	if perk == null:
		return
	# Parse "amb_t2" → (&"amb", 2). Legacy 3-letter tree IDs.
	var id_parts := String(perk.id).split("_t")
	if id_parts.size() != 2:
		return
	var stat_id := StringName(id_parts[0])
	var tier := int(id_parts[1])
	if tier <= 0 or tier > AttributeState.TIER_ROMAN.size():
		return
	var entry := _buff_entry_for_stat(stat_id)
	var stat_color: Color = AttributeState.color_for_id(stat_id)
	var pip := Label.new()
	pip.text = AttributeState.TIER_ROMAN[tier - 1]
	pip.add_theme_font_size_override(&"font_size", _PIP_START_FONT_SIZE)
	pip.add_theme_color_override(&"font_color", stat_color)
	pip.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 1))
	pip.add_theme_constant_override(&"outline_size", 4)
	pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pip.size = Vector2(180.0, 80.0)
	pip.pivot_offset = pip.size * 0.5
	root.add_child(pip)
	var screen := get_viewport().get_visible_rect().size
	var start_pos := Vector2(screen.x * 0.5, screen.y * 0.5) + _PIP_START_OFFSET - pip.size * 0.5
	pip.position = start_pos
	# Target: center of the buff entry (or screen center if no entry yet).
	var target_pos: Vector2
	if entry != null:
		target_pos = entry.global_position + entry.size * 0.5 - pip.size * 0.5
	else:
		target_pos = start_pos + Vector2(0.0, 200.0)
	# Travel + shrink. Scale a Control around its center via pivot_offset
	# (set above). Position is top-left, so target_pos compensates.
	var end_scale: float = float(_PIP_END_FONT_SIZE) / float(_PIP_START_FONT_SIZE)
	var travel := create_tween().set_parallel(true)
	travel.tween_property(pip, "position", target_pos, _PIP_TRAVEL_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	travel.tween_property(pip, "scale", Vector2(end_scale, end_scale), _PIP_TRAVEL_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Hold + fade + free, sequenced after travel.
	var fade := create_tween()
	fade.tween_interval(_PIP_TRAVEL_DURATION + _PIP_HOLD)
	fade.tween_property(pip, "modulate:a", 0.0, _PIP_FADE)
	fade.tween_callback(pip.queue_free)


func _buff_entry_for_stat(stat_id: StringName) -> Control:
	if buff_entries == null:
		return null
	# _update_buffs_bar uses queue_free on the previous children before
	# adding fresh ones, so during the first idle frame after a rebuild
	# both the old and new entry for a stat may exist. Skip the
	# soon-to-be-freed children so the pip lands on the entry that's
	# actually going to stay.
	for child in buff_entries.get_children():
		if not (child is Control) or child.is_queued_for_deletion():
			continue
		if (child as Control).get_meta(&"buff_stat_id", &"") == stat_id:
			return child as Control
	return null


## How long the banner takes to fade from full opacity to invisible AFTER
## the hold duration ends. Slow on purpose so the player still has time to
## read longer announcements (snark messages, level-up + talent line).
const _BANNER_FADE_DURATION := 1.8

func _show_banner(text: String, duration: float) -> void:
	_banner_token += 1
	var token := _banner_token
	banner.text = text
	banner.modulate.a = 1.0
	banner.visible = true
	await get_tree().create_timer(duration).timeout
	if token != _banner_token:
		return
	var tween := create_tween()
	tween.tween_property(banner, "modulate:a", 0.0, _BANNER_FADE_DURATION)
	tween.tween_callback(func() -> void:
		# Re-check the token at fade-end — a fresh banner that arrived
		# during the fade would have bumped the token AND already reset
		# alpha + visible itself, so we mustn't hide-and-clobber it.
		if token == _banner_token:
			banner.visible = false
			banner.modulate.a = 1.0)
