extends CharacterBody3D
class_name PrototypePlayer

signal health_changed(current: int, max_value: int)
signal resource_changed(current: int, max_value: int)
signal credits_changed(amount: int)
signal died
signal notification_requested(text: String)
signal crouch_changed(is_crouching: bool)
signal light_changed(is_on: bool)

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
		var skill := resolve_skill(i)
		if skill != null:
			_cast_skill(skill)
		return

func resolve_skill(index: int) -> Skill:
	var weapon: Item = InventoryState.get_equipped(&"weapon")
	if index == 0:
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

func _die() -> void:
	_alive = false
	died.emit()
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
