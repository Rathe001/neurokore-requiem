extends CanvasLayer
class_name PrototypeHud

const HP_BAR_WIDTH := 156.0
const RESOURCE_BAR_WIDTH := 156.0
const LOW_HP_RATIO := 0.35

const SLOT_LABELS: Array[String] = ["LMB", "RMB", "1", "2", "3", "4", "Q", "E"]
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
@onready var avatar_label: Label = %AvatarLabel
@onready var flashlight_bg: ColorRect = %FBg
@onready var flashlight_border: ReferenceRect = %FBorder
@onready var crouch_bg: ColorRect = %CBg
@onready var crouch_border: ReferenceRect = %CBorder
@onready var skill_bar: Control = %SkillBar
@onready var banner: Label = %Banner
@onready var debug_label: Label = %DebugLabel
@onready var debug_bg: ColorRect = $Root/DebugPanel/DebugBack
@onready var hotkey_hints: Label = %HotkeyHints
@onready var main_menu: Node = %MainMenu

var _max_health: int = 1
var _last_hp_current: int = 0
var _banner_token: int = 0
var _debug_overlay_accum: float = 0.0
var _state_flashlight: bool = false
var _state_crouch: bool = false
var _minimap: Minimap

func _ready() -> void:
	add_to_group(&"hud")
	_apply_theme()
	_update_avatar_glyph()
	UIThemeState.changed.connect(_apply_theme)
	PlayerState.class_changed.connect(func(_id: StringName) -> void: _update_avatar_glyph())
	PlayerState.spec_changed.connect(func(_id: StringName) -> void: _update_avatar_glyph())
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
	_on_health_changed(_max_health, _max_health)
	_bind_skill_slots(player)
	_bind_resource_pool(player)
	_build_minimap(player)

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
	avatar_label.add_theme_color_override(&"font_color", p.accent)
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

func _update_avatar_glyph() -> void:
	var id: StringName = PlayerState.spec_id if PlayerState.spec_id != &"" else PlayerState.class_id
	avatar_label.text = (id as String).substr(0, 1).to_upper()

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
	if hotkey_hints.visible != overlay_on:
		hotkey_hints.visible = overlay_on
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
		var skill: Skill = player.resolve_skill(i) if player.has_method(&"resolve_skill") else (skills[i] if i < skills.size() else null)
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
	hp_fill.size.x = HP_BAR_WIDTH * ratio
	hp_fill.color = p.hp_full if ratio > LOW_HP_RATIO else p.hp_low
	hp_label.text = "%d / %d" % [max(_last_hp_current, 0), _max_health]

func _on_resource_changed(current: int, max_value: int) -> void:
	var ratio := 0.0 if max_value <= 0 else clampf(float(current) / float(max_value), 0.0, 1.0)
	resource_fill.size.x = RESOURCE_BAR_WIDTH * ratio
	resource_label.text = "%d / %d" % [max(current, 0), max_value]

func _on_player_died() -> void:
	_show_banner(tr("HUD_BANNER_DIED"), 2.0)

func _on_notification_requested(text: String) -> void:
	_show_banner(text, 2.5)

func _show_banner(text: String, duration: float) -> void:
	_banner_token += 1
	var token := _banner_token
	banner.text = text
	banner.visible = true
	await get_tree().create_timer(duration).timeout
	if token == _banner_token:
		banner.visible = false
