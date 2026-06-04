class_name EnemyAfflictions
extends Node
## Extracted from PrototypeEnemy — curse, DoTs, CC, charm, buffs, markers.

var _host: PrototypeEnemy

# Damage buff from support allies.
var _damage_buff_mult: float = 0.0
var _damage_buff_remain: float = 0.0

# Curse (Count Exile).
var _curse_remain: float = 0.0
var _curse_damage_pct: float = 0.0
var _curse_marker: Label3D = null
var _curse_laser: MeshInstance3D = null

# DoTs.
const IGNITE_TICK_INTERVAL := 0.5
var _ignite_remain: float = 0.0
var _ignite_dps: float = 0.0
var _ignite_tick_accum: float = 0.0

const BLEED_TICK_INTERVAL := 0.5
const BLEED_HP_PCT_PER_SEC := 0.02
const BLEED_MAX_STACKS := 5
var _bleed_remain: float = 0.0
var _bleed_stacks: int = 0
var _bleed_tick_accum: float = 0.0

# CC.
var _stun_remain: float = 0.0

# Charm (Doomsayer).
var _charmed: bool = false
var _charm_target: Node3D = null
var _loose_running: bool = false

# Weaken (Doomsayer).
var _weaken_remain: float = 0.0
var _weaken_mult: float = 0.0

# ISR drone marks.
var _isr_vuln_count: int = 0

# Sniper first-mark tracking.
const SNIPER_FIRST_MARK_FRESH_INTERVAL := 5.0
const SNIPER_FIRST_MARK_BONUS_MULT := 1.5
var _sniper_last_hit_t: float = -999.0

# Taser static discharge.
const TASER_STATIC_INTERVAL := 10
const TASER_STATIC_RELEASE_MULT := 3.0
var _taser_hit_count: int = 0

# Affliction marker Label3D.
var _affliction_marker: Label3D = null

# Curse laser constants.
const CURSE_LASER_RADIUS: float = 0.005
const CURSE_LASER_COLOR: Color = Color(1.0, 0.18, 0.18, 0.25)
const CURSE_LASER_PLAYER_OFFSET: Vector3 = Vector3(0.0, 1.0, 0.0)
const CURSE_LASER_TARGET_OFFSET: Vector3 = Vector3(0.0, 1.0, 0.0)

# Collision layer constants for charm.
const _LAYER_WORLD := 1
const _LAYER_ENEMY := 2
const _LAYER_PLAYER := 4
const _LAYER_CHARMED_ALLY := 16
const _LAYER_INTERACTABLE := 64
const _LAYER_PILLAR := 128
# PILLAR intentionally absent: enemies physically phase through destructible
# clutter (barrels, crates, chairs) so they don't get stuck on knee-high props
# whose bullet-catch collision extends to chest height. Indestructible cover
# (cell bars, exam tables) keeps blocking enemy movement via its WORLD-layer
# membership — see clutter_builder._create_indestructible.
const _DEFAULT_ENEMY_MASK := _LAYER_WORLD | _LAYER_ENEMY | _LAYER_PLAYER | _LAYER_CHARMED_ALLY | _LAYER_INTERACTABLE
const _CHARMED_PET_MASK := _LAYER_WORLD | _LAYER_ENEMY | _LAYER_CHARMED_ALLY | _LAYER_INTERACTABLE


func setup(host: PrototypeEnemy) -> void:
	_host = host


func reset() -> void:
	_damage_buff_mult = 0.0
	_damage_buff_remain = 0.0
	_curse_remain = 0.0
	_curse_damage_pct = 0.0
	_clear_curse_marker()
	_clear_curse_laser()
	_ignite_remain = 0.0
	_ignite_dps = 0.0
	_ignite_tick_accum = 0.0
	_bleed_remain = 0.0
	_bleed_stacks = 0
	_bleed_tick_accum = 0.0
	_stun_remain = 0.0
	_charmed = false
	_charm_target = null
	_loose_running = false
	_weaken_remain = 0.0
	_weaken_mult = 0.0
	_isr_vuln_count = 0
	_sniper_last_hit_t = -999.0
	_taser_hit_count = 0
	_clear_affliction_marker()


# ── Curse (Count Exile) ───────────────────────────────────────────────────

func apply_curse(damage_pct: float, duration: float) -> void:
	if not _host._is_alive() or damage_pct <= 0.0 or duration <= 0.0:
		return
	if _host.is_player_friendly():
		return
	if _curse_remain > 0.0:
		return
	_curse_damage_pct = damage_pct
	_curse_remain = duration
	_show_curse_marker()
	_show_curse_laser()
	_host._visuals.refresh_tooltip_if_hovered()


func tick_curse(delta: float) -> void:
	if _curse_remain <= 0.0:
		return
	_curse_remain -= delta
	if _curse_remain > 0.0:
		_update_curse_laser()
		return
	_curse_damage_pct = 0.0
	_curse_remain = 0.0
	_clear_curse_marker()
	var player: Node3D = _host._player_ref
	if player == null or not is_instance_valid(player):
		player = _host.get_tree().get_first_node_in_group(&"player") as Node3D
	if player != null and player.has_method(&"fire_exile_shot"):
		player.fire_exile_shot(_host)
	_clear_curse_laser()


func _show_curse_marker() -> void:
	if _curse_marker != null and is_instance_valid(_curse_marker):
		return
	var lbl := Label3D.new()
	lbl.text = "✦"
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	# Projection-aware fixed_size scaling — keeps the curse glyph the
	# same on-screen size under ortho or perspective.
	lbl.pixel_size = 0.0014 * PrototypeCamera.label_fixed_size_scale()
	lbl.font_size = 32
	lbl.outline_size = 8
	lbl.modulate = Color(0.95, 0.85, 0.3, 1.0)
	lbl.outline_modulate = Color(0.05, 0.0, 0.1, 1.0)
	lbl.position = Vector3(0.0, 2.4, 0.0)
	_host.add_child(lbl)
	_curse_marker = lbl


func _clear_curse_marker() -> void:
	if _curse_marker != null and is_instance_valid(_curse_marker):
		_curse_marker.queue_free()
	_curse_marker = null


func _show_curse_laser() -> void:
	if _curse_laser != null and is_instance_valid(_curse_laser):
		return
	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = CURSE_LASER_RADIUS
	cyl.bottom_radius = CURSE_LASER_RADIUS
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.cap_top = false
	cyl.cap_bottom = false
	mesh_inst.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = CURSE_LASER_COLOR
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.25, 0.25, 1.0)
	mat.emission_energy_multiplier = 0.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shadow_to_opacity = false
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_inst.top_level = true
	_host.add_child(mesh_inst)
	_curse_laser = mesh_inst
	_update_curse_laser()


func _clear_curse_laser() -> void:
	if _curse_laser != null and is_instance_valid(_curse_laser):
		_curse_laser.queue_free()
	_curse_laser = null


func _update_curse_laser() -> void:
	if _curse_laser == null or not is_instance_valid(_curse_laser):
		return
	var player: Node3D = _host._player_ref
	if player == null or not is_instance_valid(player):
		player = _host.get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null or not _host.is_inside_tree():
		_curse_laser.visible = false
		return
	var p_pos: Vector3 = player.global_position + CURSE_LASER_PLAYER_OFFSET
	var e_pos: Vector3 = _host.global_position + CURSE_LASER_TARGET_OFFSET
	var diff := e_pos - p_pos
	var dist := diff.length()
	if dist < 0.05:
		_curse_laser.visible = false
		return
	_curse_laser.visible = true
	_curse_laser.global_position = (p_pos + e_pos) * 0.5
	var dir := diff / dist
	if dir.dot(Vector3.UP) < -0.9999:
		_curse_laser.basis = Basis(Vector3(1.0, 0.0, 0.0), PI)
	else:
		_curse_laser.basis = Basis(Quaternion(Vector3.UP, dir))
	_curse_laser.scale = Vector3(1.0, dist, 1.0)


# ── DoTs ───────────────────────────────────────────────────────────────────

func apply_ignite(dps: float, duration: float) -> void:
	if dps <= 0.0 or duration <= 0.0:
		return
	if not _host._is_alive():
		return
	if dps > _ignite_dps:
		_ignite_dps = dps
	if duration > _ignite_remain:
		_ignite_remain = duration


func apply_bleed(duration: float, stacks: int = 1) -> void:
	if not _host._is_alive() or duration <= 0.0 or stacks <= 0:
		return
	_bleed_stacks = mini(BLEED_MAX_STACKS, _bleed_stacks + stacks)
	if duration > _bleed_remain:
		_bleed_remain = duration


# ── CC ─────────────────────────────────────────────────────────────────────

func apply_stun(duration: float) -> void:
	if not _host._is_alive() or duration <= 0.0:
		return
	if _host._state == PrototypeEnemy.State.RETURNING or _host._state == PrototypeEnemy.State.JUMPING:
		return
	if duration > _stun_remain:
		_stun_remain = duration
	if _host._state != PrototypeEnemy.State.GRABBED:
		_host._change_state(PrototypeEnemy.State.STUNNED)
		_host.velocity = Vector3.ZERO
	show_affliction_marker("✱", Color(0.55, 0.7, 1.0, 1.0))
	_host._visuals.refresh_tooltip_if_hovered()


# ── Charm ──────────────────────────────────────────────────────────────────

func apply_charm() -> bool:
	if not _host._is_alive():
		return false
	if _host._state == PrototypeEnemy.State.RETURNING:
		return false
	if _charmed:
		return false
	if not _host.is_charmable():
		return false
	_charmed = true
	_charm_target = _host._pick_nearest_other_enemy()
	if _host._state != PrototypeEnemy.State.STUNNED:
		_host._change_state(PrototypeEnemy.State.CHASING)
	show_affliction_marker("♥", Color(1.0, 0.4, 0.7, 1.0))
	_host.collision_layer = _LAYER_CHARMED_ALLY
	_host.collision_mask = _CHARMED_PET_MASK
	_host.died.emit()
	_host._visuals.update_health_bar()
	_host._visuals.refresh_tooltip_if_hovered()
	return true


func release_charm() -> void:
	if not _charmed:
		return
	_charmed = false
	_charm_target = null
	_loose_running = false
	_host.collision_layer = _LAYER_ENEMY
	_host.collision_mask = _DEFAULT_ENEMY_MASK
	if _stun_remain <= 0.0 and _weaken_remain <= 0.0:
		_clear_affliction_marker()
	_host._visuals.update_health_bar()
	_host._visuals.refresh_tooltip_if_hovered()
	if _host._is_alive():
		_host.revived.emit()


# ── Grab (Telekinesis) ────────────────────────────────────────────────────

func apply_grab() -> bool:
	if not _host._is_alive():
		return false
	if _host._state == PrototypeEnemy.State.RETURNING or _host._state == PrototypeEnemy.State.GRABBED:
		return false
	_host._change_state(PrototypeEnemy.State.GRABBED)
	_host.velocity = Vector3.ZERO
	return true


func release_grab() -> void:
	if _host._state != PrototypeEnemy.State.GRABBED:
		return
	if _stun_remain > 0.0:
		_host._change_state(PrototypeEnemy.State.STUNNED)
		_host.velocity = Vector3.ZERO
	else:
		_host._change_state(PrototypeEnemy.State.IDLE)


# ── Weaken ─────────────────────────────────────────────────────────────────

func apply_weaken(magnitude: float, duration: float) -> void:
	if not _host._is_alive() or duration <= 0.0 or magnitude <= 0.0:
		return
	if magnitude > _weaken_mult:
		_weaken_mult = clampf(magnitude, 0.0, 1.0)
	if duration > _weaken_remain:
		_weaken_remain = duration
	show_affliction_marker("↓", Color(0.7, 0.7, 0.7, 1.0))
	_host._visuals.refresh_tooltip_if_hovered()


# ── Damage buff ────────────────────────────────────────────────────────────

func apply_damage_buff(magnitude: float, duration: float) -> void:
	if not _host._is_alive():
		return
	if magnitude > _damage_buff_mult:
		_damage_buff_mult = magnitude
	if duration > _damage_buff_remain:
		_damage_buff_remain = duration


# ── ISR marks ──────────────────────────────────────────────────────────────

func apply_isr_mark() -> void:
	_isr_vuln_count += 1
	show_affliction_marker("◎", Color(1.0, 0.45, 0.2, 1.0))
	_host._visuals.refresh_tooltip_if_hovered()


func remove_isr_mark() -> void:
	_isr_vuln_count = maxi(0, _isr_vuln_count - 1)
	if _isr_vuln_count <= 0:
		if _stun_remain <= 0.0 and not _charmed and _weaken_remain <= 0.0:
			_clear_affliction_marker()
	_host._visuals.refresh_tooltip_if_hovered()


# ── Tick ───────────────────────────────────────────────────────────────────

func tick(delta: float) -> void:
	if _stun_remain > 0.0 and _host._state != PrototypeEnemy.State.GRABBED:
		_stun_remain -= delta
		if _stun_remain <= 0.0:
			_stun_remain = 0.0
			if _host._state == PrototypeEnemy.State.STUNNED:
				_host._change_state(PrototypeEnemy.State.IDLE)
	if _ignite_remain > 0.0:
		_ignite_remain -= delta
		_ignite_tick_accum += delta
		if _ignite_tick_accum >= IGNITE_TICK_INTERVAL:
			_ignite_tick_accum -= IGNITE_TICK_INTERVAL
			var tick_dmg: int = maxi(1, int(round(_ignite_dps * IGNITE_TICK_INTERVAL)))
			# is_dot=true → take_damage skips the per-hit blood burst +
			# floor droplets. Ignite is fire-based anyway, not a wound.
			_host.take_damage(tick_dmg, _host.global_position, 0.0, 1, false, &"", false, true)
		if _ignite_remain <= 0.0:
			_ignite_remain = 0.0
			_ignite_dps = 0.0
			_ignite_tick_accum = 0.0
	if _bleed_remain > 0.0 and _bleed_stacks > 0:
		_bleed_remain -= delta
		_bleed_tick_accum += delta
		if _bleed_tick_accum >= BLEED_TICK_INTERVAL:
			_bleed_tick_accum -= BLEED_TICK_INTERVAL
			var per_tick_pct: float = BLEED_HP_PCT_PER_SEC * BLEED_TICK_INTERVAL * float(_bleed_stacks)
			var tick_dmg: int = maxi(1, int(round(float(_host.max_health) * per_tick_pct)))
			# is_dot=true → take_damage skips the per-hit blood burst +
			# floor droplets. The trail drip below is the visual signature
			# for bleed instead, movement-gated so stationary bleeders
			# don't pool in place.
			_host.take_damage(tick_dmg, _host.global_position, 0.0, 1, false, &"", false, true)
			_host._stamp_bleed_drop()
		if _bleed_remain <= 0.0:
			_bleed_remain = 0.0
			_bleed_stacks = 0
			_bleed_tick_accum = 0.0
			# Reset the trail anchor so the next bleed application
			# always drops on its first tick, regardless of where the
			# enemy stood when the previous bleed ended.
			_host._bleed_drop_anchor_set = false
	if _charmed:
		var needs_repick := _charm_target == null or not _host._is_target_alive(_charm_target)
		if not needs_repick and _charm_target is PrototypeEnemy:
			if (_charm_target as PrototypeEnemy).is_player_friendly():
				needs_repick = true
		if needs_repick:
			_charm_target = _host._pick_nearest_other_enemy()
	if _weaken_remain > 0.0:
		_weaken_remain -= delta
		if _weaken_remain <= 0.0:
			_weaken_remain = 0.0
			_weaken_mult = 0.0
	if _stun_remain <= 0.0 and not _charmed and _weaken_remain <= 0.0:
		_clear_affliction_marker()


# ── Markers ────────────────────────────────────────────────────────────────

func show_affliction_marker(glyph: String, color: Color) -> void:
	_clear_affliction_marker()
	var lbl := Label3D.new()
	lbl.text = glyph
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	# Projection-aware fixed_size scaling (see other lbl setup above).
	lbl.pixel_size = 0.0014 * PrototypeCamera.label_fixed_size_scale()
	lbl.font_size = 32
	lbl.outline_size = 8
	lbl.modulate = color
	lbl.outline_modulate = Color(0.05, 0.0, 0.1, 1.0)
	lbl.position = Vector3(0.0, 2.7, 0.0)
	_host.add_child(lbl)
	_affliction_marker = lbl


func _clear_affliction_marker() -> void:
	if _affliction_marker != null and is_instance_valid(_affliction_marker):
		_affliction_marker.queue_free()
	_affliction_marker = null
