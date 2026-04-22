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

const KNOCKBACK_DURATION := 0.15
const DEATH_HOLD := 0.9
const RESPAWN_DELAY := 1.0
const INTERACT_RANGE_SQ := 6.25
const PLAYER_WORLD_POS_PARAM := &"player_world_pos"

const SKILL_INPUTS: Array[StringName] = [
	&"attack_single",
	&"attack_aoe",
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

@export var move_speed: float = 6.0
@export var accel: float = 200.0
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
const FLASHLIGHT_MAX_PITCH_DEG := 82.0
const FLASHLIGHT_MAX_UP_DEG := 10.0
# Cursor distance at which the beam fully levels off (and begins tilting up).
const FLASHLIGHT_LEVEL_DISTANCE := 9.0
# How far above the flashlight the beam targets at max cursor distance. This is
# what tilts the beam slightly above horizontal at the far end.
const FLASHLIGHT_OVER_LIFT := 0.8

var class_id: StringName = &""
var spec_id: StringName = &""
var _camera: Camera3D
var _health: int
var _alive: bool = true
var _knockback_vel: Vector3 = Vector3.ZERO
var _knockback_remain: float = 0.0
var _attacking: bool = false
var _attack_aim: Vector3 = Vector3.ZERO
var _want_dir: Vector3 = Vector3.ZERO
var _cooldowns: Dictionary = {}
var _resource_current: float = 0.0
var _resource_last_int: int = 0
var _credits: int = 0
var _death_tween: Tween
var _flashlight: SpotLight3D
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

func _ready() -> void:
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
	_build_flashlight()
	var we_node := get_parent().get_node_or_null("WorldEnvironment") as WorldEnvironment
	if we_node != null:
		_world_env = we_node.environment
	if resource_pool != null:
		_resource_current = float(resource_pool.start_value)
		_resource_last_int = int(_resource_current)
		resource_changed.emit(_resource_last_int, resource_pool.max_value)
	_apply_debug_overrides()
	_build_crosshair()
	_stand_test_shape = CapsuleShape3D.new()
	_stand_test_shape.radius = 0.4
	_stand_test_shape.height = STAND_HEIGHT

func _apply_class_appearance() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = UIThemeState.palette.player_color
	mat.metallic = 0.1
	mat.roughness = 0.6
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
	if knockback_strength > 0.0:
		var dir := global_position - knockback_from
		dir.y = 0.0
		if dir.length_squared() > 0.0001:
			_knockback_vel = dir.normalized() * knockback_strength
			_knockback_remain = KNOCKBACK_DURATION
	if _health <= 0:
		_die()

func _process(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set(PLAYER_WORLD_POS_PARAM, global_position)
	if _fps_mode:
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
	_tick_cooldowns(delta)
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
		velocity.x = _knockback_vel.x
		velocity.z = _knockback_vel.z
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
	move_and_slide()

	# Auto-uncrouch as soon as there's headroom and the key isn't held.
	if _crouching and not Input.is_action_pressed(&"crouch"):
		_set_crouch(false)

	if _alive and not _attacking and _knockback_remain <= 0.0:
		if _fps_mode:
			var forward := -_fps_camera.global_transform.basis.z
			forward.y = 0.0
			if forward.length_squared() > 0.0001:
				_face_direction(forward.normalized())
			if _flashlight != null:
				_flashlight.rotation.x = _fps_pitch
		else:
			var offset := _cursor_offset()
			if offset.length_squared() > 0.0001:
				_face_direction(offset.normalized())
				_update_flashlight_pitch(offset.length())
		if _is_airborne:
			if velocity.y > 0.0:
				_play_anim(ANIM_JUMP_START, 1.2, 0.1)
			else:
				_play_anim(ANIM_JUMP_AIR, 1.0, 0.15)
		elif not _interacting:
			if _want_dir.length_squared() > 0.01:
				if _crouching:
					_play_anim(ANIM_CROUCH_MOVE, 1.0, 0.15)
				elif _backing:
					_play_anim(ANIM_RUN, 0.5, 0.15)
				else:
					_play_anim(ANIM_RUN, 1.0, 0.15)
			else:
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
		if InventoryState.get_equipped(&"light") != null:
			_light_on = not _light_on
			light_changed.emit(_light_on)
			_apply_light_item()
		else:
			notification_requested.emit(tr("HUD_BANNER_NO_LIGHT"))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"crouch"):
		_set_crouch(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(&"crouch"):
		_set_crouch(false)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"toggle_view"):
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
		if i == 0 and _fps_mode and _fps_hovered != null:
			if Input.is_action_just_pressed(SKILL_INPUTS[i]):
				_try_interact_with(_fps_hovered)
			return
		elif i == 0 and not _fps_mode and _is_near_world_interactable():
			if Input.is_action_just_pressed(SKILL_INPUTS[i]):
				_try_interact()
			return
		if i < skills.size():
			_cast_skill(skills[i])
		return

func _is_near_world_interactable() -> bool:
	var interact_range := sqrt(INTERACT_RANGE_SQ)
	return SpatialGrid.query_nearest(global_position, interact_range, &"interactables") != null

func _is_any_modal_open() -> bool:
	if _modal_nodes.is_empty():
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
	if _cooldowns.get(skill, 0.0) > 0.0:
		return
	var infinite_resource := DebugState.config != null and DebugState.config.infinite_resource
	if skill.resource_cost > 0 and not infinite_resource and _resource_current < float(skill.resource_cost):
		return
	var aim := _aim_direction()
	if aim == Vector3.ZERO:
		return
	_cooldowns[skill] = skill.cooldown
	if skill.resource_cost > 0:
		_spend_resource(skill.resource_cost)
	_attacking = true
	_attack_aim = aim
	_face_direction(aim)
	_play_anim(ANIM_ATTACK, 1.4)
	PrototypeAttackIndicator.spawn(self, skill, aim)
	if skill.wind_up > 0.0:
		await get_tree().create_timer(skill.wind_up).timeout
	_attacking = false
	if not _alive:
		return
	_resolve_skill_hit(skill, _attack_aim)

func _resolve_skill_hit(skill: Skill, aim: Vector3) -> void:
	match skill.targeting_mode:
		Skill.TargetingMode.SINGLE_CONE:
			PrototypeAttackIndicator.spawn_hit_cone(self, aim, skill.range, skill.cone_deg)
			_resolve_cone(skill, aim)
		Skill.TargetingMode.AOE_RADIAL:
			PrototypeAttackIndicator.spawn_hit_radial(self, skill.range)
			_resolve_aoe(skill)

func _resolve_cone(skill: Skill, aim: Vector3) -> void:
	var half_cos := cos(deg_to_rad(skill.cone_deg * 0.5))
	for enode: Node3D in SpatialGrid.query_cone(global_position, aim, skill.range, half_cos, &"enemies"):
		if enode.has_method(&"take_damage"):
			enode.take_damage(skill.damage, global_position, skill.knockback)

func _resolve_aoe(skill: Skill) -> void:
	for enode: Node3D in SpatialGrid.query_radius(global_position, skill.range, &"enemies"):
		if enode.has_method(&"take_damage"):
			enode.take_damage(skill.damage, global_position, skill.knockback)

func _tick_cooldowns(delta: float) -> void:
	for skill in _cooldowns.keys():
		_cooldowns[skill] = maxf(0.0, _cooldowns[skill] - delta)

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
	if skill == null or skill.cooldown <= 0.0:
		return 0.0
	var remaining: float = _cooldowns.get(skill, 0.0)
	return clampf(remaining / skill.cooldown, 0.0, 1.0)

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
	_respawn()

func _respawn() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.kill()
		_death_tween = null
	global_position = Vector3(0.0, 0.0, -4.0)
	velocity = Vector3.ZERO
	_knockback_remain = 0.0
	_attacking = false
	_health = max_health
	_alive = true
	_cooldowns.clear()
	if visual != null:
		visual.scale = Vector3.ONE
	if resource_pool != null:
		_resource_current = float(resource_pool.start_value)
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
	var offset := _cursor_offset()
	if offset.length_squared() < 0.0001:
		return Vector3.ZERO
	return offset.normalized()

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

func _set_meshes_visible(node: Node, is_visible: bool) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).visible = is_visible
	for child in node.get_children():
		_set_meshes_visible(child, is_visible)

func _set_group_visible(group: StringName, is_visible: bool) -> void:
	for node: Node in get_tree().get_nodes_in_group(group):
		if node is Node3D:
			(node as Node3D).visible = is_visible

func _set_fps_fog(enabled: bool) -> void:
	if _fps_fill_light != null:
		_fps_fill_light.visible = enabled
	if _world_env != null:
		_world_env.fog_enabled = enabled

func _build_flashlight() -> void:
	if visual == null:
		return
	_flashlight = SpotLight3D.new()
	_flashlight.spot_angle = 20.0
	_flashlight.spot_attenuation = 1.4
	_flashlight.spot_angle_attenuation = 0.8
	_flashlight.shadow_enabled = true
	_flashlight.shadow_bias = 0.02
	_flashlight.shadow_normal_bias = 0.3
	_flashlight.position = FLASHLIGHT_OFFSET
	_flashlight.visible = false
	visual.add_child(_flashlight)
	_update_flashlight_pitch(0.0)
	InventoryState.equipment_changed.connect(_on_equipment_changed)
	InventoryState.items_overflowed.connect(_on_items_overflowed)
	_apply_light_item()

func _on_equipment_changed(slot: StringName) -> void:
	if slot != &"light":
		return
	_light_on = InventoryState.get_equipped(&"light") != null
	_apply_light_item()

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
	if _flashlight == null:
		return
	var item: Item = InventoryState.get_equipped(&"light")
	if item != null:
		_flashlight.light_color = item.light_color
		_flashlight.light_energy = item.light_energy
		_flashlight.spot_range = item.light_range
	_flashlight.visible = item != null and _light_on

func _update_flashlight_pitch(cursor_distance: float) -> void:
	if _flashlight == null:
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
	_flashlight.rotation.x = -pitch

func _face_direction(dir: Vector3) -> void:
	if visual == null or dir.length_squared() < 0.0001:
		return
	visual.look_at(visual.global_position + dir, Vector3.UP)

func _play_anim(candidates: Array[StringName], speed: float = 1.0, blend: float = 0.0) -> bool:
	if anim_player == null:
		return false
	var reverse := speed < 0.0
	for name in candidates:
		if not anim_player.has_animation(name):
			continue
		var name_str := String(name)
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
	for name in candidates:
		if not anim_player.has_animation(name):
			continue
		var anim := anim_player.get_animation(name)
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
	var cursor_world := global_position + _cursor_offset()
	var nearby := SpatialGrid.query_nearest(cursor_world, 1.5, &"interactables")
	if nearby != null:
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
