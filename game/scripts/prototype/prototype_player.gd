extends CharacterBody3D
class_name PrototypePlayer

signal health_changed(current: int, max_value: int)
signal resource_changed(current: int, max_value: int)
signal credits_changed(amount: int)
# Active-offhand shield buff state. Fires on activate, on each
# damage hit (pool reduces), on break (active=false), and on
# unequip (active=false, all zero). HUD listens to draw the
# white outline around the HP bar and to show the buff bar entry.
signal shield_buff_changed(active: bool, pool: int, pool_max: int, reduction: float, cooldown_remain: float, cooldown_total: float, duration_remain: float)
signal died
signal notification_requested(text: String)
signal crouch_changed(is_crouching: bool)
signal light_changed(is_on: bool)
# Fires whenever the count of currently-charmed (Doomsayer) enemies
# changes. HUD listens to update the per-perk badge count.
signal charm_count_changed(current: int, max_value: int)
signal stats_changed

const ITEM_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_item_pickup.tscn")

const KNOCKBACK_DURATION := 0.22
const DEATH_HOLD := 0.9
const INTERACT_RANGE_SQ := 4.0  # 2.0m — player must stand close to interact
const PLAYER_WORLD_POS_PARAM := &"player_world_pos"

const SKILL_INPUTS: Array[StringName] = [
	&"fire",
	&"alt_fire",
	&"skill_1",
	&"skill_2",
	&"skill_3",
	&"skill_4",
	&"skill_q",
	&"skill_e",
]

const ANIM_IDLE: Array[StringName] = [&"Idle", &"Idle_Loop", &"Idle_Normal"]
const ANIM_RUN: Array[StringName] = [&"Jog_Fwd", &"Jog_Fwd_Loop"]
const ANIM_WALK_BACK: Array[StringName] = [&"Walk"]
const ANIM_CROUCH_IDLE: Array[StringName] = [&"Crouch_Idle", &"Crouch_Idle_Loop"]
const ANIM_CROUCH_MOVE: Array[StringName] = [&"Crouch_Fwd", &"Crouch_Fwd_Loop"]
const ANIM_ATTACK: Array[StringName] = [&"Sword_Attack", &"Punch_Cross"]
const ANIM_JUMP_START: Array[StringName] = [&"Jump_Start"]
const ANIM_JUMP_AIR: Array[StringName] = [&"Jump"]
const ANIM_JUMP_LAND: Array[StringName] = [&"Jump_Land"]
const ANIM_INTERACT: Array[StringName] = [&"Interact"]
const ANIM_DEATH: Array[StringName] = [
	&"Death01", &"Death_1", &"Death_2", &"Death_A", &"Death_B", &"Death",
	&"Dying_A", &"Dying_B", &"Die",
	&"DEATH_1", &"DEATH_2", &"DEATH",
]

const CROUCH_SPEED_FACTOR := 0.45
const SPRINT_SPEED_FACTOR := 1.6
const SPRINT_RESOURCE_PER_SEC := 8.0
## Penalty delay before resource regen starts after hitting 0 while sprinting.
const SPRINT_EMPTY_REGEN_DELAY := 2.0
# Health regen — out-of-combat only by default. Any take_damage() resets the
# delay; regen ticks as a percentage of max_health per second once the timer
# expires. Gear/talent surfaces:
#   hp_regen_bonus_pct      — adds to HP_REGEN_BASE_PCT (additive, e.g. +1
#                             means +1% max HP per second on top of the
#                             baseline). Read via get_effective_modifier so
#                             low-ilvl regen gear scales down as the player
#                             outlevels it, like every other power stat.
#   regen_delay_reduction   — subtracts from HP_REGEN_DELAY (seconds). At
#                             5s base, a +2 reduction means regen kicks in
#                             after 3s out of combat instead of 5.
const HP_REGEN_DELAY := 5.0
const HP_REGEN_BASE_PCT := 10.0
const HP_REGEN_MIN_DELAY := 0.5
# Movement multiplier while holding the Active Shield (SHIELD_HOLD).
# 20% — the player is essentially planted; the trade is full damage
# block + still being able to attack. SHIELD_BUFF doesn't apply.
const STAND_HEIGHT := 1.6
const CROUCH_HEIGHT := 0.9
const GRAVITY := 22.0
const JUMP_VELOCITY := 6.5

# Body rotation rates. Aim turns are snappier so kiting stays responsive.
const TURN_RATE_MOVE := 12.0  # rad/s — ~130 ms for a 90° turn
const TURN_RATE_AIM := 30.0   # rad/s — near-instant when an attack is held
# Velocity threshold below which we don't repoint at the velocity vector,
# so the player keeps their facing during a coast-to-stop instead of yanking
# back to the last input direction.
const FACE_BY_VELOCITY_MIN := 0.5
# Scales the run animation playback rate. The source clip is calibrated for a
# slower travel speed than our 6 m/s default, so feet skate without this. Tune
# by eye — at full sprint feet should plant cleanly with no slide.
const RUN_ANIM_SPEED_FACTOR := 1.5
const RUN_ANIM_SPEED_MIN := 0.6
const RUN_ANIM_SPEED_MAX := 1.9

@export var move_speed: float = 6.0
@export var accel: float = 30.0
@export var max_health: int = 100
@export var skills: Array[Skill] = []
@export var resource_pool: ResourcePool

@onready var visual: Node3D = $Visual
@onready var anim_player: AnimationPlayer = $Visual/Character/AnimationPlayer
@onready var _collision: CollisionShape3D = $Collision

const FLASHLIGHT_OFFSET := Vector3(0, 1.4, -0.3)
## Render layer used by the player visual so equipped lights can exclude
## it from their shadow_cull_mask (player still lit, just no self-shadow).
const PLAYER_VISUAL_LAYER := 2
const FPS_HEAD_OFFSET := Vector3(0.0, 1.55, 0.0)
const FPS_CROUCH_OFFSET := Vector3(0.0, 0.75, 0.0)
const FPS_PITCH_LIMIT := 1.4
const CROSSHAIR_ARM := 8.0
const CROSSHAIR_GAP := 3.0
const CROSSHAIR_THICK := 1.5
const FPS_FILL_COLOR := Color(0.5, 0.55, 0.62)
const FPS_FILL_ENERGY := 1.2
const FPS_FILL_RANGE := 6.0
const FPS_FILL_ATTENUATION := 2.0
const INTERACT_ANIM_SPEED := 3.0
const FPS_HOVER_INTERVAL := 0.05
const FLASHLIGHT_MAX_PITCH_DEG := 82.0
const FLASHLIGHT_MAX_UP_DEG := 10.0
# Cursor distance at which the beam fully levels off (and begins tilting up).
const FLASHLIGHT_LEVEL_DISTANCE := 9.0
# How far above the flashlight the beam targets at max cursor distance. This is
# what tilts the beam slightly above horizontal at the far end.
const FLASHLIGHT_OVER_LIFT := 0.8

var class_id: StringName = &""
var spec_id: StringName = &""
var _base_mat: StandardMaterial3D = null
var _combat: PlayerCombat
var _camera: Camera3D
var _health: int
var _alive: bool = true
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_remain: float = 0.0
# Independent busy flags for the two firing paths so LMB-hold and RMB-hold
# can interleave. Movement halt and facing gate on EITHER being true (any
# active commit window stops the player), but each input path only blocks
# its OWN re-entry — RMB cast can still fire while LMB is mid-windup, and
# vice versa.
var _lmb_busy: bool = false
var _skill_busy: bool = false


# True while any attack is in its commit window. Used by movement and
# facing logic so the player stops / locks orientation during ANY swing,
# regardless of which input started it.
func _is_attack_committed() -> bool:
	return _lmb_busy or _skill_busy
var _attack_aim: Vector3 = Vector3.ZERO
var _click_consumed: bool = false
# Auto-aim target while LMB is held over an enemy. Cleared on release, on
# target death/pooling, or in FPS mode. Drives _aim_direction when set.
var _lock_target: Node3D = null
# Click-to-walk-to-interact target. Set when the player LMB-clicks an
# out-of-range hovered interactable; the movement loop synthesises a
# wish_dir toward this node each tick until INTERACT_RANGE_SQ is met,
# then fires the interact and clears the target. Cancelled by manual
# WASD input, target invalidation, or a fresh click on something else.
var _walk_to_interact_target: Node3D = null

var _shield: PlayerShield
var _grenade: PlayerGrenade

## Called by pickups/interactables to suppress the fire input this frame.
func consume_click() -> void:
	_click_consumed = true
# Item that owns the in-flight skill (weapon or offhand). Captured at cast
# start so wind-up timing and hit resolution use the same stats even if the
# player swaps gear mid-attack. Null for class skills.
var _attack_weapon: Item = null
var _want_dir: Vector3 = Vector3.ZERO
var _resource_current: float = 0.0
var _resource_last_int: int = 0
var _credits: int = 0
var _death_tween: Tween
var _hit_flash_tween: Tween
var _telekinesis: PlayerTelekinesis
var _doomsayer: PlayerDoomsayer
var _drone_swarm: PlayerDroneSwarm
var _ied: PlayerIED
var _spawn_position: Vector3 = Vector3.ZERO
var _equipped_light: SpotLight3D
var _anim_reverse: bool = false
var _light_on: bool = false
var _fps_mode: bool = false
var _fps_camera: Camera3D = null
var _fps_pitch: float = 0.0
var _fps_transitioning: bool = false
var _world_env: Environment = null
var _modal_nodes: Array[CanvasItem] = []
var _fps_fill_light: OmniLight3D = null
var _fade_rect: ColorRect = null
var _chromatic: ChromaticAberrationOverlay = null
var _crouching: bool = false
var _sprinting: bool = false
## Time remaining on the regen penalty after emptying resource while sprinting.
var _sprint_regen_penalty: float = 0.0
var _is_airborne: bool = false
var _backing: bool = false
var _interacting: bool = false
var _fps_hovered: Node3D = null
var _crosshair_root: Control = null
var _crosshair_bars: Array[ColorRect] = []
var _stand_test_shape: CapsuleShape3D = null
var _fps_hover_timer: float = 0.0
# Stat-driven HP tracking: base + level gains + stat bonus = max_health.
var _base_max_health: int = 100
var _level_hp_bonus: int = 0
# Base resource pool max before stat bonuses.
var _base_resource_max: int = 100
# Gear-aggregated combat bonuses — recomputed on equipment change.
var _gear_damage_reduction: int = 0
var _gear_move_speed_bonus: int = 0
var _gear_base_damage_bonus: int = 0
var _gear_crit_chance_bonus: float = 0.0
var _gear_attack_speed_bonus: float = 0.0
var _gear_hit_chance_bonus: float = 0.0
var _gear_cooldown_reduction: float = 0.0
var _gear_hp_regen_bonus: float = 0.0
var _gear_regen_delay_reduction: float = 0.0
# Time since the player was last hit. Counts up each frame; HP regen kicks
# in once it crosses (HP_REGEN_DELAY - regen_delay_reduction). Reset by
# take_damage().
var _out_of_combat_t: float = HP_REGEN_DELAY
# Sub-integer accumulator so % regen produces the right value at any frame
# rate — flushed to _health when it crosses 1.0. Without this, a 4%/sec
# tick at 60fps produces 0 (rounded) every frame and HP never climbs.
var _hp_regen_accum: float = 0.0

func _ready() -> void:
	_combat = PlayerCombat.new()
	_combat.setup(self)
	add_child(_combat)
	_telekinesis = PlayerTelekinesis.new()
	_telekinesis.setup(self)
	add_child(_telekinesis)
	_camera = get_viewport().get_camera_3d()
	_fps_camera = Camera3D.new()
	_fps_camera.position = FPS_HEAD_OFFSET
	_fps_camera.current = false
	_fps_camera.far = _camera.far if _camera != null else 1000.0
	add_child(_fps_camera)
	_fps_fill_light = OmniLight3D.new()
	_fps_fill_light.light_color = FPS_FILL_COLOR
	_fps_fill_light.light_energy = FPS_FILL_ENERGY
	_fps_fill_light.omni_range = FPS_FILL_RANGE
	_fps_fill_light.omni_attenuation = FPS_FILL_ATTENUATION
	_fps_fill_light.shadow_enabled = false
	_fps_fill_light.visible = false
	_fps_camera.add_child(_fps_fill_light)
	var _fade_canvas := CanvasLayer.new()
	_fade_canvas.layer = 100
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_canvas.add_child(_fade_rect)
	add_child(_fade_canvas)
	_chromatic = ChromaticAberrationOverlay.new()
	add_child(_chromatic)
	add_to_group(&"player")
	add_to_group(&"world_item_dropper")
	SpatialGrid.register(self, &"player")
	class_id = PlayerState.class_id
	spec_id = PlayerState.spec_id
	PlayerState.leveled_up.connect(_on_player_leveled_up)
	_drone_swarm = PlayerDroneSwarm.new()
	_drone_swarm.setup(self)
	add_child(_drone_swarm)
	_ied = PlayerIED.new()
	_ied.setup(self)
	add_child(_ied)
	PerkState.perks_changed.connect(_drone_swarm.reconcile)
	_doomsayer = PlayerDoomsayer.new()
	_doomsayer.setup(self)
	add_child(_doomsayer)
	_shield = PlayerShield.new()
	_shield.setup(self)
	add_child(_shield)
	_grenade = PlayerGrenade.new()
	_grenade.setup(self)
	add_child(_grenade)
	PerkState.perks_changed.connect(_doomsayer.reconcile)
	# Put player meshes on an extra render layer so equipped lights can
	# exclude it from shadow casting (no self-shadow under own flashlight).
	if visual != null:
		for child in visual.get_children():
			if child is VisualInstance3D:
				child.layers |= (1 << (PLAYER_VISUAL_LAYER - 1))
			for grandchild in child.get_children():
				if grandchild is VisualInstance3D:
					grandchild.layers |= (1 << (PLAYER_VISUAL_LAYER - 1))
	_base_max_health = max_health
	if resource_pool != null:
		_base_resource_max = resource_pool.max_value
	_recompute_stat_bonuses()
	_health = max_health
	_ensure_loop(ANIM_IDLE)
	_ensure_loop(ANIM_RUN)
	_ensure_loop(ANIM_WALK_BACK)
	_ensure_loop(ANIM_CROUCH_IDLE)
	_ensure_loop(ANIM_CROUCH_MOVE)
	_ensure_loop(ANIM_JUMP_AIR)
	if anim_player != null:
		anim_player.animation_finished.connect(_on_anim_finished)
	_play_anim(ANIM_IDLE)
	_apply_class_appearance()
	_build_light_mount()
	var we_node := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we_node != null:
		_world_env = we_node.environment
	if resource_pool != null:
		_resource_current = float(resource_pool.start_value)
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)
	_apply_saved_state()
	_apply_debug_overrides()
	_spawn_position = global_position
	_build_crosshair()
	_stand_test_shape = CapsuleShape3D.new()
	_stand_test_shape.radius = 0.4
	# Probe only the slab ABOVE the crouch capsule — the volume that
	# needs to be clear for the player to stand. Probing the full
	# stand-height capsule would catch the floor under the player every
	# tick (bottom hemisphere reaches y=0) and lock crouch on. Mirrors
	# the enemy's CROUCH_PROBE_HEIGHT pattern.
	_stand_test_shape.height = STAND_HEIGHT - CROUCH_HEIGHT
	_build_stat_vfx()
	_drone_swarm.reconcile()
	_doomsayer.reconcile()

func _build_stat_vfx() -> void:
	if _base_mat == null or visual == null:
		return
	var controller := StatVFXController.new()
	add_child(controller)
	controller.setup(visual, _base_mat)

func _apply_class_appearance() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UIThemeState.palette.player_color
	mat.metallic = 0.1
	mat.roughness = 0.6
	_base_mat = mat
	_tint_meshes(visual, mat)

func _tint_meshes(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint_meshes(child, mat)

func _apply_saved_state() -> void:
	# Restore accumulated level-up HP before recomputing stats so max_health
	# reflects all past level-up rolls, not just the base @export value.
	if PlayerState.saved_level_hp_bonus > 0:
		_level_hp_bonus = PlayerState.saved_level_hp_bonus
		_recompute_stat_bonuses()
	# Restore current health. -1 means fresh character → use max_health.
	if PlayerState.saved_health >= 0:
		_health = mini(PlayerState.saved_health, max_health)
	else:
		_health = max_health
	health_changed.emit(_health, max_health)
	if PlayerState.saved_credits > 0:
		_credits = PlayerState.saved_credits
		credits_changed.emit(_credits)
	if PlayerState.saved_resource_current > 0.0 and resource_pool != null:
		_resource_current = minf(PlayerState.saved_resource_current, float(resource_pool.max_value))
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)


func _apply_debug_overrides() -> void:
	var cfg: DebugConfig = DebugState.config
	if cfg == null:
		return
	if cfg.override_start_position:
		global_position = cfg.start_position
	if cfg.starting_credits > 0:
		_credits = cfg.starting_credits
		credits_changed.emit(_credits)
	if not cfg.starter_loadout.is_empty():
		_apply_debug_loadout(cfg.starter_loadout)


func _apply_debug_loadout(entries: PackedStringArray) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ilvl := maxi(1, PlayerState.level)
	for entry in entries:
		if entry.strip_edges().is_empty():
			continue
		var item: Item = ItemRoller.roll_debug_entry(entry, ilvl, rng)
		if item == null:
			continue
		var slot: StringName = item.kind
		if slot != &"" and InventoryState.get_equipped(slot) == null:
			InventoryState.set_equipped(slot, item)
		else:
			InventoryState.add_to_inventory(item)

func is_alive() -> bool:
	return _alive


func is_player_friendly(target: Node) -> bool:
	return _combat.is_player_friendly(target)


func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0) -> void:
	if not _alive:
		return
	if DebugState.config != null and DebugState.config.god_mode:
		return
	# Flat damage reduction from armor gear bonuses.
	if _gear_damage_reduction > 0:
		amount = maxi(1, amount - _gear_damage_reduction)
	# Knockback reduction from the active shield. Computed BEFORE the
	var shield_result := _shield.absorb_damage(amount, knockback_strength)
	amount = shield_result.amount
	knockback_strength = shield_result.knockback
	_health = max(_health - amount, 0)
	health_changed.emit(_health, max_health)
	# Reset out-of-combat regen — any take_damage() call delays HP recovery
	# by the full configured window. Environmental DoTs / pit damage / boss
	# AoE all flow through this path, so regen pauses uniformly regardless
	# of damage source.
	_out_of_combat_t = 0.0
	_hp_regen_accum = 0.0
	_hit_flash_tween = HitFlash.play(self, visual, _hit_flash_tween)
	if knockback_strength > 0.0:
		var dir := global_position - knockback_from
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			_knockback_vel = dir.normalized() * knockback_strength
			_knockback_remain = KNOCKBACK_DURATION
	if _health <= 0:
		_die()

func _on_player_leveled_up(new_level: int, hp_gain: int) -> void:
	_level_hp_bonus += hp_gain
	_recompute_stat_bonuses()
	_health = max_health
	health_changed.emit(_health, max_health)
	notification_requested.emit(tr("HUD_LEVEL_UP_FORMAT") % new_level)
	_play_levelup_vfx()

func _play_levelup_vfx() -> void:
	if visual == null:
		return
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.7
	torus.rings = 32
	torus.ring_segments = 8
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.4)
	mat.emission_energy_multiplier = 3.0
	ring.material_override = mat
	add_child(ring)
	ring.position = Vector3(0.0, 0.05, 0.0)
	ring.scale = Vector3(0.4, 0.4, 0.4)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(ring, "scale", Vector3(3.5, 0.4, 3.5), 0.7) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(ring, "position:y", 0.6, 0.7) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(ring.queue_free)

func _recompute_stat_bonuses() -> void:
	# Aggregate all gear-driven bonuses from every equipped slot.
	var hp_bonus := 0
	var res_bonus := 0
	var dmg_red := 0
	var move_spd := 0
	var base_dmg := 0
	var crit := 0.0
	var atk_spd := 0.0
	var hit := 0.0
	var cdr := 0.0
	var hp_regen_bonus := 0.0
	var regen_delay_red := 0.0
	for slot in SlotRegistry.SLOTS:
		var item: Item = InventoryState.get_equipped(slot)
		if item == null:
			continue
		# All gear bonuses here contribute to combat power, so they go
		# through get_effective_modifier — the aggregate respects ilvl
		# scaling. Storage stats (inventory_bonus) are read elsewhere via
		# the raw get_modifier so backpack capacity doesn't shrink with level.
		hp_bonus += item.get_effective_modifier(&"max_health_bonus")
		res_bonus += item.get_effective_modifier(&"max_resource_bonus")
		dmg_red += item.get_effective_modifier(&"damage_reduction")
		move_spd += item.get_effective_modifier(&"move_speed_bonus")
		base_dmg += item.get_effective_modifier(&"base_damage_bonus")
		crit += float(item.get_effective_modifier(&"crit_chance_bonus")) * 0.01
		atk_spd += float(item.get_effective_modifier(&"attack_speed_bonus")) * 0.01
		hit += float(item.get_effective_modifier(&"hit_chance_bonus")) * 0.01
		cdr += float(item.get_effective_modifier(&"cooldown_reduction")) * 0.01
		hp_regen_bonus += float(item.get_effective_modifier(&"hp_regen_bonus"))
		regen_delay_red += float(item.get_effective_modifier(&"regen_delay_reduction"))
	_gear_damage_reduction = dmg_red
	_gear_move_speed_bonus = move_spd
	_gear_base_damage_bonus = base_dmg
	_gear_crit_chance_bonus = crit
	_gear_attack_speed_bonus = atk_spd
	_gear_hit_chance_bonus = hit
	_gear_cooldown_reduction = cdr
	_gear_hp_regen_bonus = hp_regen_bonus
	_gear_regen_delay_reduction = regen_delay_red
	var new_max := _base_max_health + _level_hp_bonus + hp_bonus
	if new_max != max_health:
		var old_max := max_health
		max_health = new_max
		# Scale current HP proportionally so equipping gear doesn't leave the
		# player at 50/200 when they were at 50/100. On first call (_health==0)
		# just fill to max.
		if old_max > 0 and _health > 0:
			_health = clampi(int(round(float(_health) * float(new_max) / float(old_max))), 1, new_max)
		health_changed.emit(_health, max_health)
	if resource_pool != null:
		var new_res_max := _base_resource_max + res_bonus
		if new_res_max != resource_pool.max_value:
			var old_res_max := resource_pool.max_value
			resource_pool.max_value = new_res_max
			# Scale current resource proportionally, same logic as HP.
			if old_res_max > 0 and _resource_current > 0.0:
				_resource_current = clampf(_resource_current * float(new_res_max) / float(old_res_max), 0.0, float(new_res_max))
			_emit_resource_if_changed()
			# Force emit even if int didn't change, since max changed.
			resource_changed.emit(int(_resource_current), resource_pool.max_value)
	stats_changed.emit()

func _process(delta: float) -> void:
	RenderingServer.global_shader_parameter_set(PLAYER_WORLD_POS_PARAM, global_position)
	if _fps_mode:
		_fps_hover_timer -= delta
		if _fps_hover_timer <= 0.0:
			_fps_hover_timer = FPS_HOVER_INTERVAL
			_update_fps_hover()
	else:
		_update_interact_cursor()
	_tick_fps_mouse_mode()

func _tick_fps_mouse_mode() -> void:
	if not _fps_mode or _fps_transitioning:
		return
	var want_captured := not _is_any_modal_open()
	var current := Input.get_mouse_mode()
	if want_captured and current != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif not want_captured and current == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta: float) -> void:
	if not _alive:
		velocity = Vector3.ZERO
		return
	if not Input.is_action_pressed(SKILL_INPUTS[0]):
		_click_consumed = false
	_update_lock_target()
	_combat.tick_cooldowns(delta)
	_tick_resource_regen(delta)
	_tick_health_regen(delta)
	_telekinesis.tick(delta)
	_shield.tick(delta)
	_doomsayer.tick(delta)
	_grenade.tick(delta)
	_ied.tick(delta)

	var on_floor := is_on_floor()

	if not on_floor:
		velocity.y -= GRAVITY * delta
	elif not _is_airborne:
		velocity.y = 0.0

	if on_floor and not _crouching and Input.is_action_just_pressed(&"jump"):
		_interacting = false
		velocity.y = JUMP_VELOCITY
		_is_airborne = true
		_play_anim(ANIM_JUMP_START, 1.2)

	if _is_airborne and on_floor and velocity.y <= 0.0:
		_is_airborne = false

	if _knockback_remain > 0.0:
		# Quadratic ease-out: matches PrototypeEnemy so the player coasts to a
		# stop on hit instead of snapping back to input mid-shove.
		var t: float = _knockback_remain / KNOCKBACK_DURATION
		var falloff: float = t * t
		velocity.x = _knockback_vel.x * falloff
		velocity.z = _knockback_vel.z * falloff
		_knockback_remain -= delta
		_want_dir = Vector3.ZERO
	elif _is_attack_committed() and not _is_airborne:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var input_vec := Vector2(
			Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
			Input.get_action_strength(&"move_down") - Input.get_action_strength(&"move_up"),
		)
		var wish_dir := Vector3.ZERO
		if input_vec.length_squared() > 0.0:
			# Manual WASD cancels auto-walk-to-interact — the player took
			# direct control.
			_walk_to_interact_target = null
			var ref_cam: Camera3D = _fps_camera if _fps_mode else _camera
			var cam_forward := _flatten(-ref_cam.global_transform.basis.z)
			var cam_right := _flatten(ref_cam.global_transform.basis.x)
			wish_dir = (cam_right * input_vec.x - cam_forward * input_vec.y).normalized()
		elif _walk_to_interact_target != null:
			wish_dir = _tick_walk_to_interact()
		_want_dir = wish_dir
		if _interacting and wish_dir.length_squared() > 0.01:
			_interacting = false
		_backing = not _is_airborne and wish_dir.length_squared() > 0.01 and wish_dir.dot(-visual.global_transform.basis.z) < -0.3
		if not _is_airborne:
			# Sprint: hold shift while moving to spend resource for a speed burst.
			# Can't sprint while crouching, backing, airborne, or out of resource.
			var wants_sprint := Input.is_action_pressed(&"sprint") and wish_dir.length_squared() > 0.01
			var infinite_res := DebugState.config != null and DebugState.config.infinite_resource
			_sprinting = wants_sprint and not _crouching and not _backing and (infinite_res or _resource_current > 0.0)
			if _chromatic != null:
				_chromatic.set_active(_sprinting)
			if _sprinting and not infinite_res:
				var drain := SPRINT_RESOURCE_PER_SEC * delta
				var was_above_zero := _resource_current > 0.0
				_resource_current = maxf(0.0, _resource_current - drain)
				_emit_resource_if_changed()
				if was_above_zero and _resource_current <= 0.0:
					_sprint_regen_penalty = SPRINT_EMPTY_REGEN_DELAY
			# Active Shield (SHIELD_HOLD) slows the player to 20% — the
			# trade for full damage block is being a near-stationary
			# target. Buff (SHIELD_BUFF) doesn't slow; it's a passive
			# 25% reduction that shouldn't impact mobility.
			var shield_factor: float = _shield.get_speed_factor()
			var sprint_factor: float = SPRINT_SPEED_FACTOR if _sprinting else 1.0
			var gear_speed_factor := 1.0 + float(_gear_move_speed_bonus) * 0.01
			var speed := move_speed * (CROUCH_SPEED_FACTOR if _crouching else 1.0) * (0.5 if _backing else 1.0) * sprint_factor * shield_factor * gear_speed_factor
			var flat := Vector2(velocity.x, velocity.z)
			var target := Vector2(wish_dir.x, wish_dir.z) * speed
			var step := accel * (1.0 if wish_dir.length_squared() > 0.0 else 2.5) * delta
			flat = flat.move_toward(target, step)
			velocity.x = flat.x
			velocity.z = flat.y
	# Capture the wished horizontal motion before move_and_slide so step-up can
	# probe in that direction even if the slide zeroed velocity against a wall.
	var wish_horiz := Vector3(velocity.x, 0.0, velocity.z)
	move_and_slide()
	# Auto step-up over short obstacles (pit-edge fences, future stair steps).
	# 0.4m clears anything authored as "low wall" while staying below typical
	# crouch-tunnel ceiling heights.
	StepUp.try(self, wish_horiz, 0.4, delta)

	# Auto-uncrouch as soon as the key isn't held. Polls the physical key
	# directly because Godot's action system can miss the release event for
	# Ctrl when it's released while another key (e.g. WASD) is still held.
	if _crouching and not Input.is_physical_key_pressed(KEY_CTRL):
		_set_crouch(false)

	if _alive and not _is_attack_committed() and _knockback_remain <= 0.0:
		if _fps_mode:
			# In FPS the body follows camera yaw; snapping is fine because the
			# camera *is* the player view.
			var forward := -_fps_camera.global_transform.basis.z
			forward.y = 0.0
			if forward.length_squared() > 0.0001:
				_face_direction(forward.normalized())
			if _equipped_light is SpotLight3D:
				_equipped_light.rotation.x = _fps_pitch
		else:
			# Top-down: face the cursor while an attack input is held, otherwise
			# face the direction the player is travelling. Smooth in both cases
			# so direction changes have weight instead of snapping.
			var aiming := _is_aim_input_held()
			var target_dir := Vector3.ZERO
			if aiming:
				var offset := _cursor_offset()
				if offset.length_squared() > 0.0001:
					target_dir = offset.normalized()
			elif _want_dir.length_squared() > 0.01:
				target_dir = _want_dir
			elif Vector2(velocity.x, velocity.z).length_squared() > FACE_BY_VELOCITY_MIN * FACE_BY_VELOCITY_MIN:
				target_dir = Vector3(velocity.x, 0.0, velocity.z).normalized()
			if target_dir.length_squared() > 0.0001:
				_smooth_face(target_dir, TURN_RATE_AIM if aiming else TURN_RATE_MOVE, delta)
			# Flashlight tracks the cursor in world space, independent of body
			# facing — the body smooths toward movement direction, but the beam
			# should follow the mouse so aiming reads as instant.
			if _equipped_light is SpotLight3D:
				_aim_flashlight_at_cursor()
		if _is_airborne:
			anim_player.speed_scale = 1.0
			if velocity.y > 0.0:
				_play_anim(ANIM_JUMP_START, 1.2, 0.1)
			else:
				_play_anim(ANIM_JUMP_AIR, 1.0, 0.15)
		elif not _interacting:
			if _want_dir.length_squared() > 0.01:
				# Match feet to travel speed so animation tracks reality during
				# the accel ramp instead of looking like skating.
				var flat_speed := Vector2(velocity.x, velocity.z).length()
				var run_ratio := (flat_speed / move_speed) * RUN_ANIM_SPEED_FACTOR
				anim_player.speed_scale = clampf(run_ratio, RUN_ANIM_SPEED_MIN, RUN_ANIM_SPEED_MAX)
				if _crouching:
					_play_anim(ANIM_CROUCH_MOVE, 1.0, 0.15)
				elif _backing:
					_play_anim(ANIM_RUN, 0.5, 0.15)
				else:
					_play_anim(ANIM_RUN, 1.0, 0.15)
			else:
				anim_player.speed_scale = 1.0
				_play_anim(ANIM_CROUCH_IDLE if _crouching else ANIM_IDLE, 1.0, 0.15)

	_handle_skill_input()

func _unhandled_input(event: InputEvent) -> void:
	if not _alive:
		return
	if event.is_action_pressed(&"interact"):
		if _is_any_modal_open() or _is_mouse_over_ui():
			return
		_try_interact()
	elif event.is_action_pressed(&"toggle_light"):
		if _equipped_light != null:
			_light_on = not _light_on
			light_changed.emit(_light_on)
			_update_light_visibility()
		else:
			notification_requested.emit(tr("HUD_BANNER_NO_LIGHT"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"crouch"):
		_set_crouch(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"crouch"):
		_set_crouch(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_view") and BuildInfo.dev_tools_enabled():
		_handle_toggle_view()
		get_viewport().set_input_as_handled()
	elif _fps_mode and not _fps_transitioning and event is InputEventMouseMotion:
		var sens := DisplayState.config.fps_mouse_sensitivity if DisplayState.config != null else 0.006
		_fps_camera.rotation.y -= (event as InputEventMouseMotion).relative.x * sens
		_fps_pitch = clampf(_fps_pitch - (event as InputEventMouseMotion).relative.y * sens, -FPS_PITCH_LIMIT, FPS_PITCH_LIMIT)
		_fps_camera.rotation.x = _fps_pitch
		get_viewport().set_input_as_handled()

func _try_interact() -> void:
	var interact_range := sqrt(INTERACT_RANGE_SQ)
	var nearest := SpatialGrid.query_nearest(global_position, interact_range, &"interactables")
	if nearest != null and nearest.has_method(&"interact"):
		if not nearest.is_in_group(&"pickups") and not _is_airborne:
			_interacting = true
			_play_anim(ANIM_INTERACT, INTERACT_ANIM_SPEED, 0.1)
		nearest.interact(self)

func _handle_skill_input() -> void:
	# No global commit-window gate — each input path self-blocks via its
	# own busy flag (_lmb_busy / _skill_busy) so LMB-hold and RMB-hold
	# operate independently. The loop visits every input each frame
	# instead of returning after the first match.
	for i in SKILL_INPUTS.size():
		if not Input.is_action_pressed(SKILL_INPUTS[i]):
			continue
		if _is_any_modal_open() or _is_mouse_over_ui():
			return
		# LMB-only carve-outs: interactable click consumption + hovered
		# pickup walk-to-interact. These should never block RMB or
		# hotkeys, so they `continue` past LMB instead of returning.
		if i == 0 and _click_consumed:
			continue
		if i == 0 and _fps_mode and _fps_hovered != null and is_instance_valid(_fps_hovered):
			if Input.is_action_just_pressed(SKILL_INPUTS[i]):
				_try_interact_with(_fps_hovered)
			continue
		elif i == 0 and not _fps_mode:
			var hovered := _hovered_clickable()
			if hovered != null:
				if _within_interact_range(hovered):
					if Input.is_action_just_pressed(SKILL_INPUTS[i]):
						_click_consumed = true
						_walk_to_interact_target = null
						_interact_with_hovered(hovered)
					continue
				else:
					# Out of range — start walking to it. Movement loop in
					# _physics_process synthesises a wish_dir toward this
					# node each tick until in range, then fires the interact.
					if Input.is_action_just_pressed(SKILL_INPUTS[i]) and hovered is Node3D:
						_click_consumed = true
						_walk_to_interact_target = hovered as Node3D
					continue
		# LMB fans out across every equipped weapon slot (Forged Amalgamation
		# adds extras). _cast_lmb_combat handles per-slot cooldowns +
		# stagger; the single-skill _cast_skill path stays for RMB and the
		# hotkey skills (1-4 / Q / E).
		if i == 0:
			_cast_lmb_combat()
			continue
		var skill := resolve_skill(i)
		if skill != null:
			_cast_skill(skill)

func resolve_skill(index: int) -> Skill:
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	if index == 0:
		# LMB binds to the MAIN weapon's fire skill for HUD display. Extra
		# weapons (Amalgamation) fire alongside it via _cast_lmb_combat,
		# but the slot icon shows the main weapon's cooldown.
		return weapon.fire_skill if weapon != null else null
	elif index == 1:
		if weapon != null and weapon.two_handed:
			return weapon.alt_fire_skill
		var offhand: Item = InventoryState.get_equipped(&"offhand")
		return offhand.fire_skill if offhand != null else null
	# Hotkey slots (1, 2, 3, 4, Q, E). A talent that has granted a
	# skill to this slot wins over the player's @export skills array,
	# so a Sanctify node can replace the default skill_q with its own
	# active without reauthoring the player scene.
	var input_action: StringName = SKILL_INPUTS[index]
	var granted := TalentState.get_granted_skill_for_slot(input_action)
	if granted != null:
		return granted
	var skill_index := index - 2
	if skill_index < skills.size():
		return skills[skill_index]
	return null

func _is_near_world_interactable() -> bool:
	var interact_range := sqrt(INTERACT_RANGE_SQ)
	return SpatialGrid.query_nearest(global_position, interact_range, &"interactables") != null

func _hovered_clickable() -> Node:
	var nodes := get_tree().get_nodes_in_group(&"hovered_clickable")
	for node in nodes:
		if is_instance_valid(node):
			return node
	return null


# Distance check shared by the click-to-interact path and the cursor
# affordance. Without this, hovering a chest from across the room and
# clicking would silently fire the interact() (door unlocks, crate
# opens) regardless of how far away the player is — the proximity
# E-key path uses INTERACT_RANGE_SQ; this brings click-on-hover in line.
# Pickups don't go through this path (they self-handle in
# prototype_item_pickup._on_input_event), so their walk-to / click-to-
# loot behaviour is unchanged.
func _within_interact_range(node: Node) -> bool:
	if node == null or not (node is Node3D):
		return false
	return global_position.distance_squared_to((node as Node3D).global_position) <= INTERACT_RANGE_SQ


# Drive auto-walk toward _walk_to_interact_target. Returns the wish_dir
# the movement loop should use this frame, OR Vector3.ZERO when the
# target is invalid / in range / already interacted with. Side effects:
# clears _walk_to_interact_target on completion / invalidation, and
# fires _interact_with_hovered as soon as the player crosses the
# INTERACT_RANGE_SQ threshold. WASD cancellation is handled by the
# caller (movement loop in _physics_process).
func _tick_walk_to_interact() -> Vector3:
	var target: Node3D = _walk_to_interact_target
	if target == null or not is_instance_valid(target) or not target.has_method(&"interact"):
		_walk_to_interact_target = null
		return Vector3.ZERO
	if _within_interact_range(target):
		_walk_to_interact_target = null
		_interact_with_hovered(target)
		return Vector3.ZERO
	var to_target := target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return Vector3.ZERO
	return to_target.normalized()

# Pickups consume their own click via Area3D input_event, so we just suppress
# the skill cast and let the pickup handle it. Doors / switches need an explicit
# interact() call.
func _interact_with_hovered(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.has_method(&"interact"):
		return
	if not node.is_in_group(&"pickups") and not _is_airborne:
		_interacting = true
		_play_anim(ANIM_INTERACT, INTERACT_ANIM_SPEED, 0.1)
	node.interact(self)

func _is_any_modal_open() -> bool:
	# Cache is built lazily and rebuilt if any entry was freed since last call —
	# UI modals are usually long-lived, but level reset can free and replace them.
	var rebuild := _modal_nodes.is_empty()
	if not rebuild:
		for modal in _modal_nodes:
			if not is_instance_valid(modal):
				rebuild = true
				break
	if rebuild:
		_modal_nodes.clear()
		for node in get_tree().get_nodes_in_group(&"ui_modal"):
			if node is CanvasItem:
				_modal_nodes.append(node as CanvasItem)
	for modal in _modal_nodes:
		if modal.visible:
			return true
	return false

func _is_mouse_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null

## Fallback stagger when there's no main weapon to derive a reference
## interval from (e.g. main slot empty but extras equipped). Otherwise
## the per-volley stagger is computed dynamically: main weapon's effective
## attack interval (cooldown / attack_speed) divided by the number of
## ready weapons. So a 1s-interval main with 3 extras fires at 0 / 0.25 /
## 0.5 / 0.75; a 0.5s main with 1 extra fires at 0 / 0.25; etc.
const LMB_MULTI_STAGGER_FALLBACK := 1.0

## Per-arm spawn offsets for Forged Amalgamation extras. weapon_2 fires from
## the player's right (relative to aim), weapon_3 from the left, weapon_4
## from above. Magnitudes sized to clear the player capsule visually
## without throwing trajectories so far that targeting reads as off.
const ARM_OFFSET_LATERAL := 0.5
const ARM_OFFSET_VERTICAL := 1.0

# LMB attack path. Iterates every active weapon slot (main + Amalgamation
# extras), fires each whose slot cooldown is ready, and staggers their
# windups so the volley reads as a sequence not a single click. Each
# weapon's cooldown is tracked per-slot so two identical weapons don't
# share a timer; the main weapon also writes the skill-keyed cooldown so
# the HUD slot icon's progress ring stays accurate for the LMB display.
func _cast_lmb_combat() -> void:
	if _lmb_busy:
		return
	_interacting = false
	var aim := _aim_direction()
	if aim == Vector3.ZERO:
		return
	var infinite_resource := DebugState.config != null and DebugState.config.infinite_resource

	# Extra Amalgamation arms fire FREE — they don't gate on resource and
	# don't consume it. Otherwise a 4-arm Forged drains the pool in one
	# click. Only the main weapon's fire_skill spends resource.
	var slots := InventoryState.get_active_weapon_slots()
	var ready_fires: Array[Dictionary] = []
	for slot in slots:
		var item: Item = InventoryState.get_equipped(slot)
		if item == null or item.fire_skill == null:
			continue
		var skill: Skill = item.fire_skill
		if _combat.is_slot_on_cooldown(slot):
			continue
		var is_main := slot == &"weapon"
		if is_main and skill.resource_cost > 0 and not infinite_resource and _resource_current < float(skill.resource_cost):
			continue
		ready_fires.append({"slot": slot, "item": item, "skill": skill, "is_main": is_main})

	if ready_fires.is_empty():
		return

	# Stagger across the MAIN weapon's effective attack interval so a
	# 1s-interval Forged with 3 extras fires at 0 / 0.25 / 0.5 / 0.75
	# regardless of each individual weapon's speed. Reads off the equipped
	# main weapon directly (not ready_fires) so the cadence stays stable
	# even when main is on cooldown and only extras are ready this volley.
	var main_interval := LMB_MULTI_STAGGER_FALLBACK
	var main_item: Item = InventoryState.get_equipped(&"weapon")
	if main_item != null and main_item.fire_skill != null:
		var main_atk_spd: float = main_item.effective_attack_speed() if main_item.attack_speed > 0.0 else 1.0
		main_interval = main_item.fire_skill.cooldown / main_atk_spd
	var stagger: float = main_interval / float(ready_fires.size())

	# Aim-relative axes for per-arm offsets. aim_right is 90° clockwise from
	# the horizontal aim vector (Vector3.UP cross flat-aim), so an extra
	# arm's bullets emerge from the player's right relative to the cursor,
	# not relative to world space.
	var aim_flat := Vector3(aim.x, 0.0, aim.z)
	if aim_flat.length_squared() < 0.0001:
		aim_flat = Vector3.FORWARD
	else:
		aim_flat = aim_flat.normalized()
	var aim_right := aim_flat.cross(Vector3.UP).normalized()

	var max_fire_delay := 0.0
	for i in ready_fires.size():
		var f: Dictionary = ready_fires[i]
		var skill: Skill = f["skill"]
		var item: Item = f["item"]
		var slot: StringName = f["slot"]
		var is_main: bool = f["is_main"]
		var atk_spd: float = item.effective_attack_speed() if item.attack_speed > 0.0 else 1.0
		_combat.start_slot_cooldown(slot, skill, atk_spd)
		# Mirror onto the skill-keyed dict for the MAIN weapon so the HUD's
		# LMB slot reads cooldown the same way it always has.
		if is_main:
			_combat.start_cooldown(skill, atk_spd)
			if skill.resource_cost > 0 and not infinite_resource:
				_spend_resource(skill.resource_cost)
		var fire_delay: float = float(i) * stagger
		max_fire_delay = maxf(max_fire_delay, fire_delay)
		var captured_skill := skill
		var captured_item := item
		var captured_offset := _arm_offset_for_slot(slot, aim_right)
		# Schedule the actual hit at fire_delay. Re-aim at lock-on time so a
		# moving target still gets tracked even though the volley was queued
		# at LMB-press.
		get_tree().create_timer(fire_delay).timeout.connect(func() -> void:
			if not _alive:
				return
			var fire_aim := aim
			if _lock_target != null:
				var refreshed := _aim_direction()
				if refreshed != Vector3.ZERO:
					fire_aim = refreshed
			_combat.resolve_skill_hit(captured_skill, fire_aim, captured_item, captured_offset)
		, CONNECT_ONE_SHOT)

	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.4)
	_ied.toss_trap(_cursor_offset())
	# Hold the player still for a brief "swing commit" window so a click
	# reads as a deliberate strike, not a strafe-shot. Two contributors:
	#   - main weapon's wind_up scaled by its attack_speed (single-arm feel)
	#   - max_fire_delay across the staggered volley (Amalgamation feel)
	# Take the max so neither contributor swallows the other; a 4-arm
	# Forged with a 0.05s wind-up still pauses for the full volley span.
	var stop_duration := max_fire_delay
	if main_item != null and main_item.fire_skill != null:
		var main_wind_up: float = main_item.fire_skill.wind_up
		if main_wind_up > 0.0:
			var main_atk_spd_for_stop: float = main_item.effective_attack_speed() if main_item.attack_speed > 0.0 else 1.0
			stop_duration = maxf(stop_duration, main_wind_up / main_atk_spd_for_stop)
	if stop_duration > 0.0:
		_lmb_busy = true
		_attack_aim = aim
		await get_tree().create_timer(stop_duration).timeout
		_lmb_busy = false


# Per-arm world-space offset for the projectile / hitscan source position.
# weapon (main): no offset — fires from chest.
# weapon_2:      right of player (relative to aim direction).
# weapon_3:      left of player.
# weapon_4:      above the player.
# Aim_right is the precomputed horizontal "right relative to aim" vector.
func _arm_offset_for_slot(slot: StringName, aim_right: Vector3) -> Vector3:
	match slot:
		&"weapon_2":
			return aim_right * ARM_OFFSET_LATERAL
		&"weapon_3":
			return -aim_right * ARM_OFFSET_LATERAL
		&"weapon_4":
			return Vector3(0.0, ARM_OFFSET_VERTICAL, 0.0)
	return Vector3.ZERO


func _cast_skill(skill: Skill) -> void:
	if skill == null or _skill_busy:
		return
	# Active offhands (shield, grenade, generator) bypass the standard
	# fire pipeline — they own state machines that don't fit the
	# one-shot cone/aoe/projectile/hitscan model.
	if skill.active_kind != Skill.ActiveKind.NONE:
		match skill.active_kind:
			Skill.ActiveKind.SHIELD_BUFF, Skill.ActiveKind.SHIELD_HOLD:
				_shield.activate_offhand_skill(skill)
			Skill.ActiveKind.GRENADE:
				if _grenade.is_on_cooldown():
					return
				var infinite_res := DebugState.config != null and DebugState.config.infinite_resource
				if skill.resource_cost > 0 and not infinite_res and _resource_current < float(skill.resource_cost):
					return
				if skill.resource_cost > 0:
					_spend_resource(skill.resource_cost)
				var throw_dir := _cursor_offset()
				_face_direction(throw_dir)
				_play_anim(ANIM_ATTACK, 1.4)
				_grenade.activate(skill, throw_dir)
			Skill.ActiveKind.SECOND_WIND:
				_activate_second_wind(skill)
		return
	_interacting = false
	if _combat.is_on_cooldown(skill):
		return
	var infinite_resource := DebugState.config != null and DebugState.config.infinite_resource
	if skill.resource_cost > 0 and not infinite_resource and _resource_current < float(skill.resource_cost):
		return
	var aim := _aim_direction()
	if aim == Vector3.ZERO:
		return
	var weapon := _combat.resolve_skill_source(skill)
	var atk_spd := weapon.effective_attack_speed() if weapon != null else 1.0
	if atk_spd <= 0.0:
		atk_spd = 1.0
	_combat.start_cooldown(skill, atk_spd)
	if skill.resource_cost > 0:
		_spend_resource(skill.resource_cost)
	_skill_busy = true
	_attack_aim = aim
	_attack_weapon = weapon
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.4)
	PrototypeAttackIndicator.spawn(self, skill, aim, _combat.effective_range(skill, weapon))
	if skill.wind_up > 0.0:
		await get_tree().create_timer(skill.wind_up / atk_spd).timeout
	_skill_busy = false
	if not _alive:
		return
	var fire_aim := _attack_aim
	if _lock_target != null:
		var refreshed := _aim_direction()
		if refreshed != Vector3.ZERO:
			fire_aim = refreshed
	_combat.resolve_skill_hit(skill, fire_aim, _attack_weapon)

func _tick_resource_regen(delta: float) -> void:
	if resource_pool == null or resource_pool.regen_per_sec <= 0.0:
		return
	if _sprinting:
		return
	# Penalty cooldown after emptying resource while sprinting.
	if _sprint_regen_penalty > 0.0:
		_sprint_regen_penalty -= delta
		return
	if _resource_current >= float(resource_pool.max_value):
		return
	_resource_current = minf(float(resource_pool.max_value), _resource_current + resource_pool.regen_per_sec * delta)
	_emit_resource_if_changed()


# Out-of-combat HP regen. _out_of_combat_t counts up since the last
# take_damage() and crosses the (delay - reduction) threshold to start
# regenerating. Regen rate = HP_REGEN_BASE_PCT + gear bonus, applied as
# a percentage of max_health per second. Stops at full HP and on death.
# A sub-integer accumulator handles low-rate-low-fps cases where a single
# delta tick produces less than 1 HP — without it nothing ever regens.
func _tick_health_regen(delta: float) -> void:
	if not _alive:
		return
	if _health >= max_health:
		_hp_regen_accum = 0.0
		return
	_out_of_combat_t += delta
	var delay := maxf(HP_REGEN_DELAY - _gear_regen_delay_reduction, HP_REGEN_MIN_DELAY)
	if _out_of_combat_t < delay:
		return
	var rate_pct := HP_REGEN_BASE_PCT + _gear_hp_regen_bonus
	if rate_pct <= 0.0:
		return
	_hp_regen_accum += float(max_health) * (rate_pct / 100.0) * delta
	if _hp_regen_accum < 1.0:
		return
	var whole_hp := int(floor(_hp_regen_accum))
	_hp_regen_accum -= float(whole_hp)
	var prev := _health
	_health = mini(_health + whole_hp, max_health)
	if _health != prev:
		health_changed.emit(_health, max_health)


# Public accessors for the buff bar. Live counts of the per-spec
# entity lists the player owns — charmed pets (AMB), IED traps (ING),
# orbiting drones (OPT). Max counters are derived from the perk
# aggregates so the HUD can render "X/Y" without re-reading internals.
func get_charm_count() -> int:
	return _doomsayer.get_charm_count()


func get_charm_max() -> int:
	return _doomsayer.get_charm_max()


func get_trap_count() -> int:
	return _ied.get_trap_count()


func get_trap_max() -> int:
	return _ied.get_trap_max()


func get_drone_count() -> int:
	return _drone_swarm.get_drone_count()


func _activate_second_wind(skill: Skill) -> void:
	if _combat.is_on_cooldown(skill):
		return
	if resource_pool == null:
		return
	_resource_current = float(resource_pool.max_value)
	_sprint_regen_penalty = 0.0
	_emit_resource_if_changed()
	resource_changed.emit(int(_resource_current), resource_pool.max_value)
	_combat.start_cooldown(skill, 1.0)


func _spend_resource(amount: int) -> void:
	if resource_pool == null:
		return
	if DebugState.config != null and DebugState.config.infinite_resource:
		return
	_resource_current = maxf(0.0, _resource_current - float(amount))
	_emit_resource_if_changed()

func _emit_resource_if_changed() -> void:
	var new_int := int(_resource_current)
	if new_int != _resource_last_int:
		_resource_last_int = new_int
		resource_changed.emit(new_int, resource_pool.max_value)

func add_credits(amount: int) -> void:
	if amount <= 0:
		return
	_credits += amount
	credits_changed.emit(_credits)

func get_credits() -> int:
	return _credits

func get_cooldown_ratio(skill: Skill) -> float:
	if skill != null and _shield.is_shield_skill(skill):
		return _shield.get_cooldown_ratio(skill)
	if skill != null and _grenade.is_grenade_skill(skill):
		return _grenade.get_cooldown_ratio(skill)
	return _combat.get_cooldown_ratio(skill)


func get_cooldown_remain(skill: Skill) -> float:
	if skill == null:
		return 0.0
	if _shield.is_shield_skill(skill):
		return _shield.get_cooldown_remain(skill)
	if _grenade.is_grenade_skill(skill):
		return _grenade.get_cooldown_remain(skill)
	return _combat.get_cooldown_remain(skill)

# Public entry for the Count Exile expire callback. PrototypeEnemy._tick_curse
# calls this when the curse timer drains; we forward to PlayerCombat where
# the shot's damage / VFX live. Thin proxy so the enemy doesn't reach into
# the player's private _combat field.
func fire_exile_shot(target: Node3D) -> void:
	_combat.fire_exile_shot(target)

func _die() -> void:
	_alive = false
	died.emit()
	_sprinting = false
	if _chromatic != null:
		_chromatic.set_active(false)
	_drone_swarm.cleanup()
	_ied.cleanup()
	_doomsayer.cleanup()
	_shield.cleanup()
	_grenade.cleanup()
	var played := _play_anim(ANIM_DEATH, 1.0)
	if not played and anim_player != null:
		anim_player.pause()
	if visual != null:
		_death_tween = create_tween()
		_death_tween.tween_property(visual, "scale:y", 0.15, 0.5)
	await get_tree().create_timer(DEATH_HOLD).timeout
	_show_death_screen()

# Update both the player's current position and the respawn anchor used by
# respawn() / NG+. Called by PrototypeRoot._move_player_to_spawn() after the
# level builder has placed a player_spawn marker — without this, the player
# would respawn at its scene-defined transform after death.
func set_spawn_position(pos: Vector3) -> void:
	_spawn_position = pos
	global_position = pos


func _show_death_screen() -> void:
	var screen := DeathScreen.new()
	screen.continue_pressed.connect(respawn)
	add_child(screen)
	screen.show_death(PlayerState.hardcore)


func respawn() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
		_death_tween = null
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_knockback_remain = 0.0
	_lmb_busy = false
	_skill_busy = false
	_recompute_stat_bonuses()
	_health = max_health
	_alive = true
	_combat.clear_cooldowns()
	_drone_swarm.reconcile()
	_doomsayer.reconcile()
	if visual != null:
		visual.scale = Vector3.ONE
	if resource_pool != null:
		_resource_current = float(resource_pool.max_value)
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)
	health_changed.emit(_health, max_health)
	_play_anim(ANIM_IDLE)

func _cursor_offset() -> Vector3:
	if _camera == null:
		return Vector3.ZERO
	var mouse_pos := get_viewport().get_mouse_position()
	var from := _camera.project_ray_origin(mouse_pos)
	var dir := _camera.project_ray_normal(mouse_pos)
	if absf(dir.y) < 0.001:
		return Vector3.ZERO
	var t: float = (global_position.y - from.y) / dir.y
	if t < 0.0:
		return Vector3.ZERO
	var flat := (from + dir * t) - global_position
	flat.y = 0.0
	return flat

func _aim_direction() -> Vector3:
	if _fps_mode:
		var forward := -_fps_camera.global_transform.basis.z
		forward.y = 0.0
		return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.ZERO
	if _lock_target != null:
		var to_target := _lock_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.0001:
			return to_target.normalized()
	var offset := _cursor_offset()
	if offset.length_squared() < 0.0001:
		return Vector3.ZERO
	return offset.normalized()

# Engages on LMB-press over a hovered enemy; releases on LMB-up or when the
# target dies / leaves the enemies group. FPS mode uses its own raycast hover
# and skips lock-on entirely.
func _update_lock_target() -> void:
	if _fps_mode:
		_lock_target = null
		return
	if not Input.is_action_pressed(SKILL_INPUTS[0]):
		_lock_target = null
		return
	if _lock_target != null:
		if not is_instance_valid(_lock_target) or not _lock_target.is_in_group(&"enemies"):
			_lock_target = null
	if _lock_target == null and Input.is_action_just_pressed(SKILL_INPUTS[0]):
		for n in get_tree().get_nodes_in_group(&"tooltip_target"):
			if not is_instance_valid(n):
				continue
			if n is Node3D and n.is_in_group(&"enemies"):
				_lock_target = n
				break

# Three-state V-key cycler:
#   - in FPS                           → exit FPS (back to iso default)
#   - in iso with tilted pitch         → reset iso pitch to default
#   - in iso already at default pitch  → enter FPS
# Lets a single key both undo a debug tilt and toggle between camera modes.
func _handle_toggle_view() -> void:
	if _fps_mode:
		_toggle_fps()
		return
	var iso_cam := _camera as PrototypeCamera
	if iso_cam != null and not iso_cam.is_at_default_pitch():
		iso_cam.reset_pitch()
		return
	_toggle_fps()


func _toggle_fps() -> void:
	if _fps_transitioning:
		return
	_fps_transitioning = true
	var tween := create_tween()
	tween.tween_property(_fade_rect, "color:a", 1.0, 0.1).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func() -> void:
		_fps_mode = not _fps_mode
		if _fps_mode:
			_fps_camera.rotation.y = visual.rotation.y
			_fps_pitch = 0.0
			_fps_camera.rotation.x = 0.0
			_fps_camera.position = FPS_CROUCH_OFFSET if _crouching else FPS_HEAD_OFFSET
			_fps_camera.current = true
			_set_meshes_visible(visual, false)
			_set_group_visible(&"fps_ceiling", true)
			_set_fps_fog(true)
			if _crosshair_root != null:
				_crosshair_root.visible = true
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		else:
			_clear_fps_hover()
			_fps_camera.current = false
			_camera.current = true
			_fps_camera.position = FPS_HEAD_OFFSET
			_set_fps_fog(false)
			_set_group_visible(&"fps_ceiling", false)
			_set_meshes_visible(visual, true)
			if _crosshair_root != null:
				_crosshair_root.visible = false
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	)
	tween.tween_property(_fade_rect, "color:a", 0.0, 0.15).set_trans(Tween.TRANS_LINEAR)
	tween.tween_callback(func() -> void:
		_fps_transitioning = false
	)

func _set_meshes_visible(node: Node, make_visible: bool) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = make_visible
	for child in node.get_children():
		_set_meshes_visible(child, make_visible)

func _set_group_visible(group: StringName, make_visible: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group(group):
		if node is Node3D:
			(node as Node3D).visible = make_visible

func _set_fps_fog(enabled: bool) -> void:
	if _fps_fill_light != null:
		_fps_fill_light.visible = enabled
	if _world_env != null:
		_world_env.fog_enabled = enabled

func _build_light_mount() -> void:
	if visual == null:
		return
	InventoryState.equipment_changed.connect(_on_equipment_changed)
	InventoryState.items_overflowed.connect(_on_items_overflowed)
	_apply_light_item()

func _on_equipment_changed(slot: StringName) -> void:
	_recompute_stat_bonuses()
	if slot == &"head":
		_apply_light_item()
	elif slot == &"weapon":
		light_changed.emit(_light_on)
	elif slot == &"offhand":
		# No stacking: removing the offhand drops every effect it
		# granted. Re-equipping a different shield offhand requires
		# the player to re-press RMB to activate.
		_shield.cleanup()

func _on_items_overflowed(overflow: Array[Item]) -> void:
	for displaced_item in overflow:
		drop_item(displaced_item)


func get_shield_buff_kind() -> Skill.ActiveKind:
	return _shield.get_shield_buff_kind()


func get_shield_buff_state() -> Dictionary:
	return _shield.get_shield_buff_state()


func drop_item(item: Item) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var pickup := ITEM_PICKUP_SCENE.instantiate() as Node3D
	pickup.configure(item)
	parent.add_child(pickup)
	pickup.global_position = global_position + Vector3(randf_range(-0.5, 0.5), 0.0, randf_range(-0.5, 0.5))

func _apply_light_item() -> void:
	if visual == null:
		return
	if _equipped_light != null:
		_equipped_light.queue_free()
		_equipped_light = null
	var head: Item = InventoryState.get_equipped(&"head")
	if head == null or head.light_mod == Item.LightMod.NONE:
		_light_on = false
		light_changed.emit(false)
		return
	var spot := SpotLight3D.new()
	spot.spot_angle = 50.0
	spot.spot_attenuation = 1.0
	spot.spot_angle_attenuation = 0.6
	spot.shadow_enabled = true
	spot.shadow_bias = 0.02
	spot.shadow_normal_bias = 0.3
	spot.light_color = head.light_color
	spot.light_energy = head.light_energy
	spot.spot_range = head.light_range
	match head.light_mod:
		Item.LightMod.FLASHLIGHT:
			spot.light_energy *= 1.5
			spot.spot_range *= 1.2
		Item.LightMod.RADIANT:
			spot.spot_angle = 90.0
			spot.spot_attenuation = 1.6
		Item.LightMod.UV:
			spot.spot_angle = 45.0
		Item.LightMod.SCANNER:
			spot.spot_angle = 60.0
	# Keep the player layer in light_cull_mask (player is lit) but remove
	# it from shadow_caster_mask so the player model doesn't cast a shadow
	# from their own headlamp.
	spot.shadow_caster_mask &= ~(1 << (PLAYER_VISUAL_LAYER - 1))
	spot.position = FLASHLIGHT_OFFSET
	_light_on = true
	spot.visible = true
	_equipped_light = spot
	visual.add_child(spot)
	_update_flashlight_pitch(0.0)
	light_changed.emit(_light_on)


func is_scanner_active() -> bool:
	var head: Item = InventoryState.get_equipped(&"head")
	return head != null and head.light_mod == Item.LightMod.SCANNER and _light_on

func _update_light_visibility() -> void:
	if _equipped_light != null:
		_equipped_light.visible = _light_on

func _update_flashlight_pitch(cursor_distance: float) -> void:
	if not _equipped_light is SpotLight3D:
		return
	var forward_offset := -FLASHLIGHT_OFFSET.z
	var d := maxf(0.01, cursor_distance - forward_offset)
	# The aim target lifts off the floor as the cursor moves away, going from
	# "floor in front of player" through the flashlight's own height (parallel)
	# and ending slightly above it (a touch of upward tilt at the far end).
	var lift_t := clampf(cursor_distance / FLASHLIGHT_LEVEL_DISTANCE, 0.0, 1.0)
	var vertical := FLASHLIGHT_OFFSET.y - lift_t * (FLASHLIGHT_OFFSET.y + FLASHLIGHT_OVER_LIFT)
	var pitch := atan2(vertical, d)
	pitch = clampf(pitch, -deg_to_rad(FLASHLIGHT_MAX_UP_DEG), deg_to_rad(FLASHLIGHT_MAX_PITCH_DEG))
	_equipped_light.rotation.x = -pitch

# Top-down aim: set the flashlight's world rotation directly so its yaw follows
# the cursor instead of the player visual. Pitch reuses the same lift curve as
# the FPS path (target Y derived from cursor distance).
func _aim_flashlight_at_cursor() -> void:
	if not _equipped_light is SpotLight3D:
		return
	var offset := _cursor_offset()
	var cursor_distance := offset.length()
	var horiz_dir: Vector3
	if cursor_distance > 0.0001:
		horiz_dir = offset / cursor_distance
	elif visual != null:
		horiz_dir = -visual.global_transform.basis.z
		horiz_dir.y = 0.0
		if horiz_dir.length_squared() < 0.0001:
			return
		horiz_dir = horiz_dir.normalized()
	else:
		return
	var forward_offset := -FLASHLIGHT_OFFSET.z
	var d := maxf(0.01, cursor_distance - forward_offset)
	var lift_t := clampf(cursor_distance / FLASHLIGHT_LEVEL_DISTANCE, 0.0, 1.0)
	var vertical := FLASHLIGHT_OFFSET.y - lift_t * (FLASHLIGHT_OFFSET.y + FLASHLIGHT_OVER_LIFT)
	var pitch := atan2(vertical, d)
	pitch = clampf(pitch, -deg_to_rad(FLASHLIGHT_MAX_UP_DEG), deg_to_rad(FLASHLIGHT_MAX_PITCH_DEG))
	var clamped_vertical := tan(pitch) * d
	var fl_pos := _equipped_light.global_position
	var target := fl_pos + horiz_dir * d + Vector3(0.0, -clamped_vertical, 0.0)
	_equipped_light.look_at(target, Vector3.UP)

func _face_direction(dir: Vector3) -> void:
	if visual == null or dir.length_squared() < 0.0001:
		return
	visual.look_at(visual.global_position + dir, Vector3.UP)

func _smooth_face(dir: Vector3, turn_rate: float, delta: float) -> void:
	# Rotate the visual yaw toward `dir` at most `turn_rate` rad/sec, taking
	# the shortest angular path. Only modifies the Y axis so animation tilt
	# (e.g. crouch lean) is preserved.
	if visual == null or dir.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	var current_yaw := visual.rotation.y
	var diff := wrapf(target_yaw - current_yaw, -PI, PI)
	var step := turn_rate * delta
	visual.rotation.y = current_yaw + clampf(diff, -step, step)

func _is_aim_input_held() -> bool:
	for action in SKILL_INPUTS:
		if not Input.is_action_pressed(action):
			continue
		# Holding RMB on a SHIELD_HOLD offhand isn't an aim — it's a
		# passive block. Movement-facing should win so the player
		# walks normally (just slower) instead of pinning to the
		# cursor. Same logic would apply to any future "hold to do
		# something non-aimed" RMB skill.
		if action == &"alt_fire":
			var rmb_skill := resolve_skill(1)
			if rmb_skill != null and rmb_skill.active_kind == Skill.ActiveKind.SHIELD_HOLD:
				continue
		return true
	return false

func _play_anim(candidates: Array[StringName], speed: float = 1.0, blend: float = 0.0) -> bool:
	if anim_player == null:
		return false
	var reverse := speed < 0.0
	for anim_name in candidates:
		if not anim_player.has_animation(anim_name):
			continue
		var name_str := String(anim_name)
		if anim_player.current_animation == name_str and anim_player.is_playing() and _anim_reverse == reverse:
			return true
		_anim_reverse = reverse
		anim_player.play(name_str, blend, absf(speed), reverse)
		return true
	push_warning("[player] _play_anim: no match found for candidates %s (current: %s)" % [str(candidates), anim_player.current_animation])
	return false

func _ensure_loop(candidates: Array[StringName]) -> void:
	if anim_player == null:
		return
	for anim_name in candidates:
		if not anim_player.has_animation(anim_name):
			continue
		var anim := anim_player.get_animation(anim_name)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		return

func _build_crosshair() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 99
	add_child(canvas)
	_crosshair_root = Control.new()
	_crosshair_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crosshair_root.visible = false
	canvas.add_child(_crosshair_root)
	var a := CROSSHAIR_ARM
	var g := CROSSHAIR_GAP
	var h := CROSSHAIR_THICK * 0.5
	_crosshair_bars.append(_make_crosshair_bar(-(a + g), -h, -g, h))
	_crosshair_bars.append(_make_crosshair_bar(g, -h, a + g, h))
	_crosshair_bars.append(_make_crosshair_bar(-h, -(a + g), h, -g))
	_crosshair_bars.append(_make_crosshair_bar(-h, g, h, a + g))
	for bar in _crosshair_bars:
		_crosshair_root.add_child(bar)

func _make_crosshair_bar(ol: float, ot: float, or_: float, ob: float) -> ColorRect:
	var bar := ColorRect.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.color = Color.WHITE
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 0.5
	bar.anchor_bottom = 0.5
	bar.offset_left = ol
	bar.offset_top = ot
	bar.offset_right = or_
	bar.offset_bottom = ob
	return bar

func _update_fps_hover() -> void:
	var space := get_world_3d().direct_space_state
	var from := _fps_camera.global_position
	var forward := -_fps_camera.global_transform.basis.z
	var to := from + forward * sqrt(INTERACT_RANGE_SQ)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.exclude = [get_rid()]
	var result := space.intersect_ray(params)
	var hit: Node3D = null
	if result.size() > 0:
		var col = result.get("collider")
		if col is Node3D and (col as Node3D).is_in_group(&"interactables"):
			hit = col as Node3D
	if hit == _fps_hovered:
		return
	if _fps_hovered != null and is_instance_valid(_fps_hovered):
		_fps_hovered.call(&"_on_mouse_exited")
	_fps_hovered = hit
	if _fps_hovered != null:
		_fps_hovered.call(&"_on_mouse_entered")
		_set_crosshair_color(UIThemeState.palette.accent)
	else:
		_set_crosshair_color(Color.WHITE)

func _clear_fps_hover() -> void:
	if _fps_hovered != null and is_instance_valid(_fps_hovered):
		_fps_hovered.call(&"_on_mouse_exited")
	_fps_hovered = null
	_set_crosshair_color(Color.WHITE)

func _set_crosshair_color(color: Color) -> void:
	for bar in _crosshair_bars:
		bar.color = color

func _try_interact_with(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not node.is_in_group(&"pickups") and not _is_airborne:
		_interacting = true
		_play_anim(ANIM_INTERACT, INTERACT_ANIM_SPEED, 0.1)
	if node.has_method(&"interact"):
		node.interact(self)

func _update_interact_cursor() -> void:
	if not _alive or _is_any_modal_open():
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		return
	var hovered := _hovered_clickable()
	if hovered != null and _within_interact_range(hovered):
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
	else:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func _on_anim_finished(anim_name: String) -> void:
	if anim_name == "Interact":
		_interacting = false

func _would_hit_ceiling_if_standing() -> bool:
	if _stand_test_shape == null:
		return false
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _stand_test_shape
	# Centre the slab probe between the top of the crouch capsule and
	# the top of the stand capsule, so it covers exactly the headroom
	# the player needs to clear to stand.
	var slab_center_y := CROUCH_HEIGHT + (STAND_HEIGHT - CROUCH_HEIGHT) * 0.5
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, slab_center_y, 0.0))
	query.exclude = [get_rid()]
	# Probe ONLY the world layer — without this the default mask (all
	# layers) catches charmed pets hugging the player at layer 16, plus
	# any hostile enemy at layer 2 standing close, and reports "ceiling
	# blocked" even in a wide-open room. Crouch then locks on until the
	# offending body wanders away. World-only matches the enemy crouch
	# probe and is the right semantics: only solid architecture should
	# prevent standing.
	query.collision_mask = 1
	return space.intersect_shape(query, 1).size() > 0

func _set_crouch(value: bool) -> void:
	if not value and _would_hit_ceiling_if_standing():
		return
	_crouching = value
	crouch_changed.emit(_crouching)
	if _collision != null and _collision.shape is CapsuleShape3D:
		var shape := _collision.shape as CapsuleShape3D
		shape.height = CROUCH_HEIGHT if value else STAND_HEIGHT
		_collision.position.y = shape.height * 0.5
	if _fps_mode and not _fps_transitioning:
		var target := FPS_CROUCH_OFFSET if value else FPS_HEAD_OFFSET
		create_tween().tween_property(_fps_camera, "position", target, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _flatten(v: Vector3) -> Vector3:
	v.y = 0.0
	return v.normalized()
