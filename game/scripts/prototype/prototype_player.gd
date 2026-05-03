extends CharacterBody3D
class_name PrototypePlayer

signal health_changed(current: int, max_value: int)
signal resource_changed(current: int, max_value: int)
signal credits_changed(amount: int)
signal died
signal notification_requested(text: String)
signal crouch_changed(is_crouching: bool)
signal light_changed(is_on: bool)
# Fires whenever the count of currently-charmed (Doomsayer) enemies
# changes. HUD listens to update the per-perk badge count.
signal charm_count_changed(current: int, max_value: int)

const ITEM_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_item_pickup.tscn")

const KNOCKBACK_DURATION := 0.22
const DEATH_HOLD := 0.9
const RESPAWN_DELAY := 1.0
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
var _attacking: bool = false
var _attack_aim: Vector3 = Vector3.ZERO
var _click_consumed: bool = false
# Auto-aim target while LMB is held over an enemy. Cleared on release, on
# target death/pooling, or in FPS mode. Drives _aim_direction when set.
var _lock_target: Node3D = null

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
var _telekinesis_t: float = 0.0
var _doomsayer_t: float = 0.0
var _doomsayer_aura: DoomsayerAura = null
var _drones: Array[PrototypeDrone] = []
var _ied_traps: Array[PrototypeTrap] = []
var _charmed_enemies: Array[PrototypeEnemy] = []
var _spawn_position: Vector3 = Vector3.ZERO
var _equipped_light: Light3D
var _scanner_active: bool = false
var _uv_active: bool = false
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
var _crouching: bool = false
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

func _ready() -> void:
	_combat = PlayerCombat.new()
	_combat.setup(self)
	add_child(_combat)
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
	add_to_group(&"player")
	add_to_group(&"world_item_dropper")
	SpatialGrid.register(self, &"player")
	class_id = PlayerState.class_id
	spec_id = PlayerState.spec_id
	PlayerState.leveled_up.connect(_on_player_leveled_up)
	AttributeState.stats_changed.connect(_recompute_stat_bonuses)
	# Reconcile the Automaton drone pool whenever the perk aggregate
	# could change — perk recompute (gear swap, tier crossing) and
	# class/spec swap. Death/respawn paths also call _reconcile_drones
	# directly so dying despawns the swarm. Initial bootstrap call
	# happens in _ready_post_setup below; PerkState._ready may have
	# already fired its first perks_changed before our connect lands.
	PerkState.perks_changed.connect(_reconcile_drones)
	PerkState.perks_changed.connect(_reconcile_charms)
	PerkState.perks_changed.connect(_reconcile_doomsayer_aura)
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
	_apply_debug_overrides()
	_spawn_position = global_position
	_build_crosshair()
	_stand_test_shape = CapsuleShape3D.new()
	_stand_test_shape.radius = 0.4
	_stand_test_shape.height = STAND_HEIGHT
	_build_stat_vfx()
	# Initial drone reconcile — PerkState may have already fired its first
	# perks_changed before our connect landed (autoload-vs-scene order),
	# so seed the drone pool here.
	_reconcile_drones()
	# Charm list is empty at boot but call the reconcile anyway so the
	# wiring matches the drone pattern (and a respec at the title screen
	# that drops the cap before any procs land doesn't get a free turn).
	_reconcile_charms()
	# Build the Doomsayer miasma aura node and seed its tier from the
	# current perk state. Same autoload-vs-scene-order safety as drones.
	_doomsayer_aura = DoomsayerAura.new()
	add_child(_doomsayer_aura)
	_reconcile_doomsayer_aura()

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

func _apply_debug_overrides() -> void:
	var cfg: DebugConfig = DebugState.config
	if cfg == null:
		return
	if cfg.override_start_position:
		global_position = cfg.start_position
	if cfg.starting_credits > 0:
		_credits = cfg.starting_credits
		credits_changed.emit(_credits)

func take_damage(amount: int, knockback_from: Vector3 = Vector3.ZERO, knockback_strength: float = 0.0) -> void:
	if not _alive:
		return
	if DebugState.config != null and DebugState.config.god_mode:
		return
	_health = max(_health - amount, 0)
	health_changed.emit(_health, max_health)
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
	var hp_bonus := AttributeState.get_stat_bonus_hp(class_id, spec_id)
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
		var res_bonus := AttributeState.get_stat_bonus_resource(class_id, spec_id)
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
	_tick_telekinesis(delta)
	_tick_doomsayer(delta)

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
	elif _attacking and not _is_airborne:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var input_vec := Vector2(
			Input.get_action_strength(&"move_right") - Input.get_action_strength(&"move_left"),
			Input.get_action_strength(&"move_down") - Input.get_action_strength(&"move_up"),
		)
		var wish_dir := Vector3.ZERO
		if input_vec.length_squared() > 0.0:
			var ref_cam: Camera3D = _fps_camera if _fps_mode else _camera
			var cam_forward := _flatten(-ref_cam.global_transform.basis.z)
			var cam_right := _flatten(ref_cam.global_transform.basis.x)
			wish_dir = (cam_right * input_vec.x - cam_forward * input_vec.y).normalized()
		_want_dir = wish_dir
		if _interacting and wish_dir.length_squared() > 0.01:
			_interacting = false
		_backing = not _is_airborne and wish_dir.length_squared() > 0.01 and wish_dir.dot(-visual.global_transform.basis.z) < -0.3
		if not _is_airborne:
			var speed := move_speed * (CROUCH_SPEED_FACTOR if _crouching else 1.0) * (0.5 if _backing else 1.0)
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

	if _alive and not _attacking and _knockback_remain <= 0.0:
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
		if InventoryState.get_equipped(&"optics") != null:
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
		_toggle_fps()
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
	if _attacking:
		return
	for i in SKILL_INPUTS.size():
		if not Input.is_action_pressed(SKILL_INPUTS[i]):
			continue
		if _is_any_modal_open() or _is_mouse_over_ui():
			return
		if i == 0 and _click_consumed:
			return
		if i == 0 and _fps_mode and _fps_hovered != null and is_instance_valid(_fps_hovered):
			if Input.is_action_just_pressed(SKILL_INPUTS[i]):
				_try_interact_with(_fps_hovered)
			return
		elif i == 0 and not _fps_mode:
			var hovered := _hovered_clickable()
			if hovered != null:
				if Input.is_action_just_pressed(SKILL_INPUTS[i]):
					_click_consumed = true
					_interact_with_hovered(hovered)
				return
		# LMB fans out across every equipped weapon slot (Forged Amalgamation
		# adds extras). _cast_lmb_combat handles per-slot cooldowns +
		# stagger; the single-skill _cast_skill path stays for RMB and the
		# hotkey skills (1-4 / Q / E).
		if i == 0:
			_cast_lmb_combat()
			return
		var skill := resolve_skill(i)
		if skill != null:
			_cast_skill(skill)
		return

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

## Polymath Telekinesis — auto-fires every TELEKINESIS_INTERVAL seconds when
## PerkState.get_aggregate(&"telekinesis_bolts") > 0. N bolts per trigger
## (sourced from the aggregate, capped sensibly). Each bolt picks one
## enemy in TELEKINESIS_RANGE — bolts within the same trigger pick distinct
## targets when possible — and spawns a TelekinesisGrab on it. The grab
## lifts the enemy over 2s, slams it back to the ground, and deals direct
## + radial AoE damage on impact. Damage scales with main stat (Clarity
## for Polymath); the BASE value is intentionally low because the
## multiplier scales aggressively with stat investment (a T3 Polymath
## has ~10×).
const TELEKINESIS_INTERVAL := 6.0
const TELEKINESIS_RANGE := 12.0
const TELEKINESIS_BASE_DAMAGE := 13    # was 8 (which felt weak); 25 was the original one-shot value
const TELEKINESIS_BOLT_STAGGER := 0.12
const TELEKINESIS_MAX_BOLTS := 8       # safety cap for future stacking sources

## Enculted Doomsayer aura — every DOOMSAYER_TICK_INTERVAL seconds, every
## enemy within the tier's aura radius rolls against the perk's per-second
## chance scaled by linear distance falloff. On a hit, ONE of three
## afflictions is applied at random — stun (frozen), charm (mind-control:
## attacks the nearest other enemy), or weaken (outgoing damage halved).
## Stun + weaken expire on a timer; charm is persistent — held in
## _charmed_enemies (FIFO-capped by doomsayer_max_charms aggregate),
## released only when the player dies or a new charm bumps it out.
## Effect handlers + state live on PrototypeEnemy. Aura radius scales
## per tier so the visible mist sphere (DoomsayerAura.RADIUS_PER_TIER)
## exactly matches the proc-eligible area — no ambiguous "is this enemy
## inside the aura?" gap between the visual and the actual range.
const DOOMSAYER_AURA_RADIUS_PER_TIER: Array[float] = [0.0, 5.0, 7.0, 9.0]
# Roll cadence for the per-enemy proc check. Lower = more frequent
# rolls = effectively more procs at the same per-tick chance. Was
# 1.0s; halved to 0.4s after playtesting found the original cadence
# read as "almost nothing's happening" even at T3. Per-tick chance
# stays at the perk magnitude (5/10/20%), so effective per-second
# proc rate roughly 2.5× the prior values.
const DOOMSAYER_TICK_INTERVAL := 0.4
# Per-tier base damage applied to every uncharmed enemy in the aura
# every tick, scaled by linear distance falloff (1.0 at center, 0.0
# at radius). Multiplied by main-stat damage_mult (Ambition for
# Enculted) so investing in the perk's stat ALSO heavies up the DoT.
# Per-tick × 2.5 ticks/sec gives roughly 10/17.5/30 base DPS at center
# (more once stat mult kicks in).
const DOOMSAYER_DOT_PER_TICK_PER_TIER: Array[float] = [0.0, 4.0, 7.0, 12.0]
const DOOMSAYER_MAX_CHARMS_CAP := 8      # safety ceiling for the charm list, well above current T3 (3)

## Survivalist IED — every LMB attack tosses a trap at the cursor while
## the perk is active. The active set is FIFO-capped at the perk
## aggregate; a trap detonates when an enemy enters its proximity radius
## or after 15s of idle. Damage scales with main stat (Ingenuity),
## captured by the trap on spawn so respec mid-trap-life doesn't change
## its yield. Higher tiers shorten the arming window — the trap pulses
## visibly during arm and won't detonate until the timer drains.
const IED_TRAP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_trap.tscn")
const IED_MAX_TRAPS_CAP := 8
# Indexed by IED tier (1/2/3 = Survivalist tiers I/II/III). Index 0 is
# unused (reconciled away by the max_traps gate), but kept for clean
# indexing without an off-by-one. Tier 1 sits at 2s so the player has to
# place the trap ahead of an incoming enemy; T3's 0.6s is closer to a
# "drop and forget" feel as the perk matures.
const IED_ARM_DELAY_BY_TIER: Array[float] = [0.0, 2.0, 1.2, 0.6]
# Cap on cursor placement distance from the player. Beyond this, the
# trap snaps to the max-range point along the cursor direction — keeps
# the perk from being a long-range artillery spam, and stops the player
# from baiting through walls they can't see past.
const IED_MAX_PLACEMENT_RANGE := 8.0

## Automaton Drone Swarm — N hover drones spawned from the
## `automaton_drones` perk aggregate. Drones are children of the player's
## parent so they keep world-space transforms (their own CharacterBody3D
## move_and_slide owns the position; parenting under the player would
## fight that with the player's transform). They look the player up via
## setup(). _reconcile_drones runs on perks_changed and on death/respawn
## to add or remove drones to match the aggregate; it clamps against
## AUTOMATON_MAX_DRONES as a safety ceiling.
const DRONE_SCENE: PackedScene = preload("res://scenes/prototype/prototype_drone.tscn")
const AUTOMATON_MAX_DRONES := 8


# LMB attack path. Iterates every active weapon slot (main + Amalgamation
# extras), fires each whose slot cooldown is ready, and staggers their
# windups so the volley reads as a sequence not a single click. Each
# weapon's cooldown is tracked per-slot so two identical weapons don't
# share a timer; the main weapon also writes the skill-keyed cooldown so
# the HUD slot icon's progress ring stays accurate for the LMB display.
func _cast_lmb_combat() -> void:
	if _attacking:
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
		var main_atk_spd: float = main_item.attack_speed if main_item.attack_speed > 0.0 else 1.0
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
		var atk_spd: float = item.attack_speed if item.attack_speed > 0.0 else 1.0
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
	# Survivalist IED — drop a trap at the cursor every LMB. No-op when
	# the perk isn't active. Placed here (not inside the per-slot loop) so
	# a Forged-Amalgamation 4-arm volley still tosses ONE trap per click,
	# not four.
	_toss_ied_trap()
	# Block input until the LAST staggered fire resolves — otherwise the
	# player could re-click before the volley completes and the per-slot
	# cooldown gate becomes the only thing preventing double-firing of
	# the trailing extras. With the new dynamic stagger the volley spans
	# the main weapon's full effective interval, so this also doubles as
	# a natural "you committed to this swing" beat before the next press.
	if max_fire_delay > 0.0:
		_attacking = true
		_attack_aim = aim
		await get_tree().create_timer(max_fire_delay).timeout
		_attacking = false


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
	if skill == null or _attacking:
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
	var atk_spd := weapon.attack_speed if weapon != null else 1.0
	if atk_spd <= 0.0:
		atk_spd = 1.0
	_combat.start_cooldown(skill, atk_spd)
	if skill.resource_cost > 0:
		_spend_resource(skill.resource_cost)
	_attacking = true
	_attack_aim = aim
	_attack_weapon = weapon
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.4)
	PrototypeAttackIndicator.spawn(self, skill, aim, _combat.effective_range(skill, weapon))
	if skill.wind_up > 0.0:
		await get_tree().create_timer(skill.wind_up / atk_spd).timeout
	_attacking = false
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
	if _resource_current >= float(resource_pool.max_value):
		return
	_resource_current = minf(float(resource_pool.max_value), _resource_current + resource_pool.regen_per_sec * delta)
	_emit_resource_if_changed()


# Polymath Telekinesis tick. Reads the perk aggregate every frame; when
# the cooldown elapses, picks distinct targets up-front and fires staggered
# bolts so a T3 4-bolt trigger reads as a sequence, not one chord. Targets
# are bound by closure to each scheduled callback so a fresh enemy walking
# in mid-stagger doesn't get pulled into a later bolt.
func _tick_telekinesis(delta: float) -> void:
	if not _alive:
		return
	var bolts := mini(int(round(PerkState.get_aggregate(&"telekinesis_bolts"))), TELEKINESIS_MAX_BOLTS)
	if bolts <= 0:
		return
	_telekinesis_t -= delta
	if _telekinesis_t > 0.0:
		return
	_telekinesis_t = TELEKINESIS_INTERVAL
	var targets := _pick_telekinesis_targets(bolts)
	if targets.is_empty():
		return
	var dmg := int(round(float(TELEKINESIS_BASE_DAMAGE) * AttributeState.get_player_damage_mult(class_id, spec_id)))
	for i in targets.size():
		var captured_target: Node3D = targets[i]
		if i == 0:
			_spawn_telekinesis_grab(captured_target, dmg)
		else:
			get_tree().create_timer(TELEKINESIS_BOLT_STAGGER * float(i)).timeout.connect(
				func() -> void: _spawn_telekinesis_grab(captured_target, dmg),
				CONNECT_ONE_SHOT)


# Pick up to `count` distinct enemies in TELEKINESIS_RANGE, shuffled.
# Returning fewer than `count` is fine — the extra bolts just don't
# fire (better than re-grabbing the same enemy four times). Filters
# out anything already in State.GRABBED so a previous trigger's lingering
# grab doesn't get hijacked.
func _pick_telekinesis_targets(count: int) -> Array[Node3D]:
	var pool: Array[Node3D] = []
	for n in SpatialGrid.query_radius(global_position, TELEKINESIS_RANGE, &"enemies"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if not n.has_method(&"apply_grab"):
			continue
		# Skip player-friendly (charmed) enemies — Telekinesis lifting
		# our own allies would be friendly fire.
		if n.has_method(&"is_player_friendly") and n.is_player_friendly():
			continue
		pool.append(n)
	if pool.is_empty():
		return []
	pool.shuffle()
	if pool.size() <= count:
		return pool
	return pool.slice(0, count)


func _spawn_telekinesis_grab(target: Node3D, dmg: int) -> void:
	if not _alive or target == null or not is_instance_valid(target):
		return
	var grab := TelekinesisGrab.new()
	grab.setup(self, target, dmg)
	get_parent().add_child(grab)


# Enculted Doomsayer aura tick. Two effects per tick:
#   1. DAMAGE OVER TIME — every uncharmed enemy in the aura takes
#      base_dot × distance_falloff damage. Linear falloff: 100% at
#      the player's centre, 0% at the aura radius.
#   2. CHARM — if the charm list is below the per-tier cap, find the
#      nearest uncharmed enemy in range and charm it. The cap acts as
#      a natural rate-limit: charms keep flowing until full, then stop
#      until one of the controlled enemies dies (which makes room).
# Charmed enemies are immune to both effects (they're allies — see
# is_player_friendly() on the enemy side).
func _tick_doomsayer(delta: float) -> void:
	if not _alive:
		return
	var tier := AttributeState.get_unlocked_tier(&"amb", PlayerState.class_id, PlayerState.spec_id)
	if tier <= 0:
		return
	_doomsayer_t -= delta
	if _doomsayer_t > 0.0:
		return
	_doomsayer_t = DOOMSAYER_TICK_INTERVAL
	var radius: float = DOOMSAYER_AURA_RADIUS_PER_TIER[clampi(tier, 0, 3)]
	if radius <= 0.0:
		return
	var dot_per_tick: float = DOOMSAYER_DOT_PER_TICK_PER_TIER[clampi(tier, 0, 3)]
	var dmg_mult := AttributeState.get_player_damage_mult(class_id, spec_id)
	# Resolve the charm slot situation up-front so we don't redo work
	# per enemy. apply_charm is best-effort — when at cap we just don't
	# try (no FIFO eviction; charms hold until the controlled enemy
	# dies, then a new charm naturally fills the slot).
	var max_charms := mini(int(round(PerkState.get_aggregate(&"doomsayer_max_charms"))), DOOMSAYER_MAX_CHARMS_CAP)
	_prune_charm_list()
	var charm_capacity := max_charms - _charmed_enemies.size()
	# Track the closest charmable candidate as we walk the radius
	# query — committing to it after the loop avoids charming several
	# enemies per tick (the "should happen much more frequently" feel
	# is per-tick = ~2.5/sec; one new charm per tick is plenty).
	var charm_candidate: PrototypeEnemy = null
	var charm_candidate_dist_sq := INF
	for n in SpatialGrid.query_radius(global_position, radius, &"enemies"):
		if not (n is PrototypeEnemy) or not is_instance_valid(n):
			continue
		var enemy: PrototypeEnemy = n
		# Skip player-friendly (charmed) enemies — they're our allies.
		if enemy.is_player_friendly():
			continue
		var dist := global_position.distance_to(enemy.global_position)
		var falloff := clampf(1.0 - dist / radius, 0.0, 1.0)
		# DoT — round to int for take_damage; falloff scaling can produce
		# tiny values which would otherwise floor to zero, so we max(1)
		# anything in range to keep the aura from feeling dead at the edge.
		if falloff > 0.0 and enemy.has_method(&"take_damage"):
			var dmg_f := dot_per_tick * falloff * dmg_mult
			var dmg := maxi(1, int(round(dmg_f)))
			enemy.take_damage(dmg, global_position, 0.0)
		# Charm tracking — only consider candidates if we have capacity,
		# AND only if apply_charm would succeed (filters out leashed,
		# already-grabbed, etc.).
		if charm_capacity > 0:
			var d2 := global_position.distance_squared_to(enemy.global_position)
			if d2 < charm_candidate_dist_sq:
				charm_candidate_dist_sq = d2
				charm_candidate = enemy
	if charm_candidate != null and charm_capacity > 0:
		if charm_candidate.apply_charm():
			_charmed_enemies.append(charm_candidate)
			_emit_charm_count_changed()


# Public accessors for the buff bar. Charm count is the live size of
# the active list; max is the per-tier doomsayer_max_charms aggregate.
func get_charm_count() -> int:
	return _charmed_enemies.size()


func get_charm_max() -> int:
	return mini(int(round(PerkState.get_aggregate(&"doomsayer_max_charms"))), DOOMSAYER_MAX_CHARMS_CAP)


func _emit_charm_count_changed() -> void:
	charm_count_changed.emit(_charmed_enemies.size(), get_charm_max())


# Compact the charm list — drops freed / dead / corpse'd entries.
# Called by _tick_doomsayer before computing capacity, and by the
# external reconcile helpers below. Emits the charm_count_changed
# signal when the list size actually shrunk so the HUD count stays
# in sync as pets die in combat.
func _prune_charm_list() -> void:
	var prev_size := _charmed_enemies.size()
	var live: Array[PrototypeEnemy] = []
	for e in _charmed_enemies:
		if e != null and is_instance_valid(e) and e.is_in_group(&"enemies"):
			live.append(e)
		elif e != null and is_instance_valid(e):
			# Defensive release in case the entry's _charmed flag
			# survived a death path that skipped release_grab.
			e.release_charm()
	_charmed_enemies = live
	if _charmed_enemies.size() != prev_size:
		_emit_charm_count_changed()


# Release every active charm. Called from _die so charms don't persist
# across the player's death — design says "until the player dies." On
# respawn the list is empty and refills naturally as the aura procs.
func _clear_charms() -> void:
	var had_any := not _charmed_enemies.is_empty()
	for e in _charmed_enemies:
		if e != null and is_instance_valid(e):
			e.release_charm()
	_charmed_enemies.clear()
	if had_any:
		_emit_charm_count_changed()


# Trim the charm list down to the current cap. Called on perks_changed
# (gear / tier crossing / class swap / respec) so a tier downgrade or
# class swap doesn't leave above-cap charms hanging until the next proc
# lazily evicts them. Mirrors the drone reconcile pattern. Always FIFO-
# evicts from the front so the player's freshest charm wins.
func _reconcile_charms() -> void:
	_prune_charm_list()
	# When dead, target is zero — _die clears immediately, this just
	# protects against a perk recompute landing during the death-hold.
	var target := 0
	if _alive:
		target = mini(int(round(PerkState.get_aggregate(&"doomsayer_max_charms"))), DOOMSAYER_MAX_CHARMS_CAP)
	while _charmed_enemies.size() > target:
		var oldest: PrototypeEnemy = _charmed_enemies.pop_front()
		if oldest != null and is_instance_valid(oldest):
			oldest.release_charm()
	# Emit even when neither the list size nor the cap changed — keeps
	# the HUD synced with cap-only updates (e.g. tier crossing that
	# raises max_charms without immediately filling the new slots).
	_emit_charm_count_changed()


# Update the Doomsayer aura's tier readout. Reads the unlocked AMB tier
# directly (rather than dividing the proc aggregate) so the aura visually
# matches the actual tier the player has — including auto-grant of T1
# for spec primary stats, which the aggregate alone wouldn't reflect.
# Force-tier-zero on death so the miasma doesn't keep glowing on the
# corpse during the respawn delay.
func _reconcile_doomsayer_aura() -> void:
	if _doomsayer_aura == null:
		return
	var tier := 0
	if _alive and PlayerState.class_id != &"":
		tier = AttributeState.get_unlocked_tier(&"amb", PlayerState.class_id, PlayerState.spec_id)
	_doomsayer_aura.set_tier(tier)


# Toss an IED trap at the cursor's world position. Called from the LMB
# combat path after weapons fire — no-op when the perk isn't unlocked or
# the cursor projection failed (off-screen / camera missing). Active set
# is FIFO-capped: at the cap, the oldest trap is force-detonated cheaply
# (queue_free without explosion) so the new one can take its place — the
# perk is "max N traps active," not "lose all your DPS while at cap."
func _toss_ied_trap() -> void:
	if not _alive:
		return
	var max_traps := mini(int(round(PerkState.get_aggregate(&"ied_max_traps"))), IED_MAX_TRAPS_CAP)
	if max_traps <= 0:
		return
	var cursor_offset := _cursor_offset()
	if cursor_offset.length_squared() < 0.0001:
		return
	# Clamp cursor offset to the placement range. Aiming past max range
	# drops the trap at max range along the cursor direction instead of
	# either failing silently or letting the player place arbitrarily
	# far. Using length_squared first avoids a sqrt when the offset is
	# already inside range.
	var max_sq := IED_MAX_PLACEMENT_RANGE * IED_MAX_PLACEMENT_RANGE
	if cursor_offset.length_squared() > max_sq:
		cursor_offset = cursor_offset.normalized() * IED_MAX_PLACEMENT_RANGE
	# Prune any traps that detonated themselves before computing the cap —
	# otherwise a trap that exploded last frame still counts toward the
	# cap on this frame's toss and the player loses a slot to a ghost.
	var live: Array[PrototypeTrap] = []
	for t in _ied_traps:
		if t != null and is_instance_valid(t):
			live.append(t)
	_ied_traps = live
	while _ied_traps.size() >= max_traps:
		var oldest: PrototypeTrap = _ied_traps.pop_front()
		if oldest != null and is_instance_valid(oldest):
			oldest.queue_free()
	# IED tier drives the arm delay — read the unlocked Ingenuity tier
	# rather than dividing the aggregate, so spec-primary auto-grant
	# works for Survivalist (T1 free even at 0% allocation).
	var tier := AttributeState.get_unlocked_tier(&"ing", PlayerState.class_id, PlayerState.spec_id)
	var arm_delay: float = IED_ARM_DELAY_BY_TIER[clampi(tier, 1, IED_ARM_DELAY_BY_TIER.size() - 1)]
	var trap: PrototypeTrap = IED_TRAP_SCENE.instantiate()
	# Set arm_delay BEFORE add_child so the trap's _ready uses it
	# (otherwise _ready captures the @export default and we'd have to
	# re-set _arm_remain after the fact).
	trap.arm_delay = arm_delay
	get_parent().add_child(trap)
	# Snap to player Y so traps sit on the floor regardless of cursor
	# projection altitude. _cursor_offset already projects against the
	# player's Y plane, so adding it gives the cursor's world position at
	# floor level.
	trap.global_position = global_position + cursor_offset
	_ied_traps.append(trap)


# Reconcile the active drone count with the perk aggregate. Called on
# perks_changed (gear / tier crossing / class swap) and on death/respawn.
# Spawns missing drones up to the target count; despawns extras off the
# end (drones are interchangeable — orbit_index gets reassigned to keep
# the swarm visually evenly spaced after a despawn). Drone parents are
# the player's parent (the world root) so they don't ride the player's
# own _process and jitter against the camera.
func _reconcile_drones() -> void:
	# Prune any drones that were freed externally before computing target.
	var live: Array[PrototypeDrone] = []
	for d in _drones:
		if d != null and is_instance_valid(d):
			live.append(d)
	_drones = live
	# When dead, target is zero — _die clears immediately, this just
	# protects against a perk recompute landing during the death-hold.
	var target := 0
	if _alive:
		target = mini(int(round(PerkState.get_aggregate(&"automaton_drones"))), AUTOMATON_MAX_DRONES)
	# Despawn extras from the end. Existing drones keep their wander state
	# across reconciles — we don't re-call setup() on survivors, since that
	# would re-roll their offsets and reset cooldowns every perk recompute.
	while _drones.size() > target:
		var d: PrototypeDrone = _drones.pop_back()
		if d != null and is_instance_valid(d):
			d.queue_free()
	# Spawn any missing drones. Parent to world root so they don't stack-
	# transform with the player (the drone's CharacterBody3D owns its own
	# world-space position via move_and_slide).
	var parent := get_parent()
	while _drones.size() < target and parent != null:
		var d := DRONE_SCENE.instantiate() as PrototypeDrone
		if d == null:
			break
		parent.add_child(d)
		# Spawn at the player so the wander seek doesn't yank from world
		# origin on the first physics tick.
		d.global_position = global_position + Vector3(0.0, 1.6, 0.0)
		d.setup(self)
		_drones.append(d)


func _clear_drones() -> void:
	for d in _drones:
		if d != null and is_instance_valid(d):
			d.queue_free()
	_drones.clear()


func _clear_ied_traps() -> void:
	for t in _ied_traps:
		if t != null and is_instance_valid(t):
			t.queue_free()
	_ied_traps.clear()


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
	return _combat.get_cooldown_ratio(skill)

# Public entry for the Count Exile expire callback. PrototypeEnemy._tick_curse
# calls this when the curse timer drains; we forward to PlayerCombat where
# the shot's damage / VFX live. Thin proxy so the enemy doesn't reach into
# the player's private _combat field.
func fire_exile_shot(target: Node3D) -> void:
	_combat.fire_exile_shot(target)

func _die() -> void:
	_alive = false
	died.emit()
	# Drop the drone swarm — they shouldn't keep firing while the player
	# is in death-hold. Respawn re-spawns them via _reconcile_drones.
	_clear_drones()
	# Same for IED traps — leftover traps in the world after death feels
	# wrong; they re-populate naturally on the next attack post-respawn.
	_clear_ied_traps()
	# Doomsayer charms release on player death — the design pins charm
	# lifetime to "until you die or a new charm bumps you out." Without
	# this, post-respawn the player would inherit the pre-death charms.
	_clear_charms()
	# Hide the miasma aura too — _alive is now false so reconcile reads
	# tier 0 and switches off particles + light spill.
	_reconcile_doomsayer_aura()
	var played := _play_anim(ANIM_DEATH, 1.0)
	if not played and anim_player != null:
		anim_player.pause()
	if visual != null:
		_death_tween = create_tween()
		_death_tween.tween_property(visual, "scale:y", 0.15, 0.5)
	await get_tree().create_timer(DEATH_HOLD).timeout
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	respawn()

# Update both the player's current position and the respawn anchor used by
# respawn() / NG+. Called by PrototypeRoot._move_player_to_spawn() after the
# level builder has placed a player_spawn marker — without this, the player
# would respawn at its scene-defined transform after death.
func set_spawn_position(pos: Vector3) -> void:
	_spawn_position = pos
	global_position = pos


func respawn() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
		_death_tween = null
	global_position = _spawn_position
	velocity = Vector3.ZERO
	_knockback_remain = 0.0
	_attacking = false
	_recompute_stat_bonuses()
	_health = max_health
	_alive = true
	_combat.clear_cooldowns()
	# Re-spawn the drone swarm now that the player is back in play.
	_reconcile_drones()
	# Restore the Doomsayer miasma to its current tier.
	_reconcile_doomsayer_aura()
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
	if slot == &"optics":
		_light_on = InventoryState.get_equipped(&"optics") != null
		_apply_light_item()
	elif slot == &"weapon":
		light_changed.emit(_light_on)

func _on_items_overflowed(overflow: Array[Item]) -> void:
	for displaced_item in overflow:
		drop_item(displaced_item)

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
	# Tear down previous light nodes.
	if _equipped_light != null:
		_equipped_light.queue_free()
		_equipped_light = null
	_scanner_active = false
	_uv_active = false

	var item: Item = InventoryState.get_equipped(&"optics")
	if item == null:
		return

	match item.light_type:
		Item.LightType.DIRECTIONAL:
			var spot := SpotLight3D.new()
			spot.spot_angle = 28.0  # wider beam — easier to navigate dark rooms
			spot.spot_attenuation = 1.2
			spot.spot_angle_attenuation = 0.7
			spot.shadow_enabled = true
			spot.shadow_bias = 0.02
			spot.shadow_normal_bias = 0.3
			spot.light_color = item.light_color
			spot.light_energy = item.light_energy
			spot.spot_range = item.light_range
			spot.position = FLASHLIGHT_OFFSET
			_equipped_light = spot
			visual.add_child(spot)
			_update_flashlight_pitch(0.0)

		Item.LightType.RADIANT:
			var omni := OmniLight3D.new()
			omni.omni_range = item.light_range
			omni.omni_attenuation = 1.4
			omni.shadow_enabled = true
			omni.light_color = item.light_color
			omni.light_energy = item.light_energy
			omni.position = FLASHLIGHT_OFFSET
			_equipped_light = omni
			visual.add_child(omni)

		Item.LightType.SCANNER:
			_scanner_active = true

		Item.LightType.UV:
			_uv_active = true
			# Purple glow — reveals uv_hidden objects.
			var glow := OmniLight3D.new()
			glow.omni_range = item.light_range
			glow.omni_attenuation = 2.0
			glow.shadow_enabled = false
			glow.light_color = item.light_color
			glow.light_energy = item.light_energy
			glow.position = FLASHLIGHT_OFFSET
			_equipped_light = glow
			visual.add_child(glow)

	if _equipped_light != null:
		_equipped_light.visible = _light_on
	_notify_hud_scanner()


func _update_light_visibility() -> void:
	if _equipped_light != null:
		_equipped_light.visible = _light_on
	_notify_hud_scanner()

func is_scanner_active() -> bool:
	return _scanner_active and _light_on

func is_uv_active() -> bool:
	return _uv_active and _light_on

func get_uv_range() -> float:
	var item: Item = InventoryState.get_equipped(&"optics")
	if item == null:
		return 0.0
	return item.light_range

func _notify_hud_scanner() -> void:
	var hud_node := get_tree().get_first_node_in_group(&"hud")
	if hud_node == null or not is_instance_valid(hud_node):
		return
	var hud := hud_node as PrototypeHud
	if hud != null:
		hud.set_scanner_active(_scanner_active and _light_on)

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
		if Input.is_action_pressed(action):
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
	if _hovered_clickable() != null:
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
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3(0.0, STAND_HEIGHT * 0.5, 0.0))
	query.exclude = [get_rid()]
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
