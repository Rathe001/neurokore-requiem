class_name EnemyVisuals
extends Node
## Extracted from PrototypeEnemy — hover/outline, tooltip, display,
## floor ring, model tint, hit squash, health bar.

var _host: PrototypeEnemy

# Outline meshes collected from the visual tree.
var _outlined_meshes: Array[MeshInstance3D] = []
var _hovered: bool = false
var _tooltip_locked: bool = false

# Material cache for model tinting — avoids duplicating shared materials.
var _tint_cache: Dictionary = {}

# Static outline materials (shared across all enemies).
static var _s_outline_mat: StandardMaterial3D
static var _s_outline_mat_locked: StandardMaterial3D

# Floor ring material instance (per-enemy, owns its emission color).
var _floor_ring_mat: StandardMaterial3D


func setup(host: PrototypeEnemy) -> void:
	_host = host


func reset() -> void:
	_hovered = false
	_tooltip_locked = false
	_outlined_meshes.clear()
	_tint_cache.clear()


# ── Hover & Outline ────────────────────────────────────────────────────────

func setup_hover() -> void:
	collect_meshes()

func collect_meshes() -> void:
	_outlined_meshes.clear()
	if _host.visual == null:
		return
	_walk_meshes(_host.visual)

func _walk_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		_outlined_meshes.append(node)
	for child in node.get_children():
		_walk_meshes(child)

func refresh_outline() -> void:
	if _s_outline_mat == null:
		_s_outline_mat = StandardMaterial3D.new()
		_s_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_s_outline_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.6)
		_s_outline_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_s_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		_s_outline_mat.grow = true
		_s_outline_mat.grow_amount = PrototypeEnemy.OUTLINE_GROW
	if _s_outline_mat_locked == null:
		_s_outline_mat_locked = StandardMaterial3D.new()
		_s_outline_mat_locked.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_s_outline_mat_locked.albedo_color = Color(PrototypeEnemy.OUTLINE_LOCKED_COLOR.r,
			PrototypeEnemy.OUTLINE_LOCKED_COLOR.g, PrototypeEnemy.OUTLINE_LOCKED_COLOR.b, 0.6)
		_s_outline_mat_locked.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_s_outline_mat_locked.cull_mode = BaseMaterial3D.CULL_FRONT
		_s_outline_mat_locked.grow = true
		_s_outline_mat_locked.grow_amount = PrototypeEnemy.OUTLINE_GROW
	var mat: StandardMaterial3D = _s_outline_mat_locked if _tooltip_locked else _s_outline_mat
	var show := _hovered or _tooltip_locked
	for mesh in _outlined_meshes:
		if not is_instance_valid(mesh):
			continue
		mesh.material_overlay = mat if show else null


func on_mouse_entered() -> void:
	_hovered = true
	refresh_outline()
	push_tooltip()


func on_mouse_exited() -> void:
	_hovered = false
	if not _tooltip_locked:
		refresh_outline()
		var tree := _host.get_tree()
		if tree != null:
			tree.call_group(&"interactable_tooltip", &"hide_tooltip")


func set_tooltip_locked(locked: bool) -> void:
	_tooltip_locked = locked
	refresh_outline()
	if locked:
		push_tooltip()
	elif not _hovered:
		var tree := _host.get_tree()
		if tree != null:
			tree.call_group(&"interactable_tooltip", &"hide_tooltip")


# ── Tooltip ────────────────────────────────────────────────────────────────

func push_tooltip() -> void:
	if not _host._is_alive():
		return
	var title := "%s  Level %d" % [_host.display_name, _host.level]
	var body := _build_tooltip_body()
	# show_talent_node is the generic title+body method on prototype_tooltip
	# — same shape as enemy tooltips need. Name's a misnomer but it's the
	# pre-refactor entry point; renaming would touch the talent panel too.
	_host.get_tree().call_group(&"interactable_tooltip", &"show_talent_node", title, body)


func _build_tooltip_body() -> String:
	var lines: Array[String] = []
	lines.append(_describe_class())
	lines.append("HP: %d / %d" % [_host._health, _host.max_health])
	var afl := _host._afflictions
	if afl._charmed:
		lines.append("[color=#ff66aa]Charmed[/color]")
	if afl._stun_remain > 0.0:
		lines.append("[color=#8899ff]Stunned %.1fs[/color]" % afl._stun_remain)
	if afl._bleed_remain > 0.0:
		lines.append("[color=#cc3333]Bleeding ×%d %.1fs[/color]" % [afl._bleed_stacks, afl._bleed_remain])
	if afl._ignite_remain > 0.0:
		lines.append("[color=#ff8800]Ignited %.1fs[/color]" % afl._ignite_remain)
	if afl._weaken_remain > 0.0:
		lines.append("[color=#999999]Weakened %.0f%% %.1fs[/color]" % [afl._weaken_mult * 100.0, afl._weaken_remain])
	if afl._curse_remain > 0.0:
		lines.append("[color=#eedd44]Cursed %.1fs[/color]" % afl._curse_remain)
	if afl._isr_vuln_count > 0:
		lines.append("[color=#ff7733]ISR Mark ×%d[/color]" % afl._isr_vuln_count)
	var combat := _host._combat
	if combat._self_buff_remain > 0.0:
		lines.append("[color=#ff4444]Enraged %.1fs[/color]" % combat._self_buff_remain)
	for affix: MonsterAffix in _host.affixes:
		if affix != null:
			lines.append("[color=#ddaa22]%s[/color]" % affix.label)
	for skill: EnemySkill in _host._special_skills:
		if skill != null:
			var cd: float = combat._skill_cooldowns.get(skill, 0.0)
			if cd > 0.0:
				lines.append("%s (%.1fs)" % [skill.display_name, cd])
			else:
				lines.append(skill.display_name)
	return "\n".join(lines)


func _describe_class() -> String:
	var ec := _host.enemy_class
	if ec == null:
		return "Melee"
	var base := "Ranged" if ec.attack_mode == EnemyClass.AttackMode.RANGED else "Melee"
	match ec.support_role:
		EnemyClass.SupportRole.HEAL:
			return base + " + Healer"
		EnemyClass.SupportRole.DAMAGE_BUFF:
			return base + " + Buffer"
	return base


func refresh_tooltip_if_hovered() -> void:
	if _hovered or _tooltip_locked:
		push_tooltip()


# ── Display name ───────────────────────────────────────────────────────────

func roll_display_name() -> void:
	if _host.is_boss or _host.named_monster != null:
		return
	if randf() < 0.4:
		var base := PrototypeEnemy.NAME_PALETTE_NUMBERED[randi() % PrototypeEnemy.NAME_PALETTE_NUMBERED.size()]
		_host.display_name = "%s %d" % [base, randi_range(1, 99)]
	else:
		_host.display_name = PrototypeEnemy.NAME_PALETTE[randi() % PrototypeEnemy.NAME_PALETTE.size()]


# ── Floor ring tint ────────────────────────────────────────────────────────

func apply_floor_ring_tint(lv: int) -> void:
	apply_floor_ring_tint_color(PrototypeEnemy.LEVEL_RING_EMISSION[mini(lv, PrototypeEnemy.LEVEL_RING_EMISSION.size() - 1)])

func class_ring_color() -> Color:
	var ec := _host.enemy_class
	if ec == null:
		return PrototypeEnemy.LEVEL_RING_EMISSION[mini(clampi(_host.level, 0, PrototypeEnemy.MAX_LEVEL), PrototypeEnemy.LEVEL_RING_EMISSION.size() - 1)]
	if ec.support_role != EnemyClass.SupportRole.NONE:
		return PrototypeEnemy._CLASS_TINT_SUPPORT
	if ec.attack_mode == EnemyClass.AttackMode.RANGED:
		return PrototypeEnemy._CLASS_TINT_RANGED
	return PrototypeEnemy._CLASS_TINT_MELEE

func apply_floor_ring_tint_color(color: Color) -> void:
	if _host.floor_ring == null:
		return
	if _floor_ring_mat == null:
		_floor_ring_mat = StandardMaterial3D.new()
		_floor_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_floor_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		# Transparent-black albedo so ONLY the emission shows — without
		# this, the default opaque white albedo dominates and the ring
		# reads as a solid white disc under every enemy.
		_floor_ring_mat.albedo_color = Color(0, 0, 0, 0)
		_floor_ring_mat.emission_enabled = true
		_floor_ring_mat.emission_energy_multiplier = 4.0
	_floor_ring_mat.emission = color
	_host.floor_ring.material_override = _floor_ring_mat


# ── Model tint ─────────────────────────────────────────────────────────────

func apply_model_tint(color: Color) -> void:
	if _host.visual == null:
		return
	_walk_and_tint(_host.visual, color)

func _walk_and_tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		for surf_idx in mi.get_surface_override_material_count():
			var base_mat := mi.mesh.surface_get_material(surf_idx) if mi.mesh != null else null
			if base_mat == null:
				continue
			var key := base_mat.resource_path if base_mat.resource_path != "" else str(base_mat.get_instance_id())
			if not _tint_cache.has(key):
				_tint_cache[key] = base_mat.duplicate()
			var mat: BaseMaterial3D = _tint_cache[key]
			if mat is StandardMaterial3D:
				mat.emission_enabled = true
				mat.emission = color
				mat.emission_energy_multiplier = 0.4
			mi.set_surface_override_material(surf_idx, mat)
	for child in node.get_children():
		_walk_and_tint(child, color)


# ── Hit feedback ───────────────────────────────────────────────────────────

func play_hit_squash() -> void:
	if _host.visual == null or not _host._is_alive():
		return
	if _host._hit_tween != null and _host._hit_tween.is_valid():
		_host._hit_tween.kill()
	var squash := Vector3(
		_host._rest_visual_scale.x * PrototypeEnemy.HIT_SQUASH_SCALE.x,
		_host._rest_visual_scale.y * PrototypeEnemy.HIT_SQUASH_SCALE.y,
		_host._rest_visual_scale.z * PrototypeEnemy.HIT_SQUASH_SCALE.z,
	)
	_host.visual.scale = _host._rest_visual_scale
	_host._hit_tween = _host.create_tween()
	_host._hit_tween.tween_property(_host.visual, "scale", squash, PrototypeEnemy.HIT_SQUASH_IN)
	_host._hit_tween.tween_property(_host.visual, "scale", _host._rest_visual_scale, PrototypeEnemy.HIT_SQUASH_OUT)


func update_health_bar() -> void:
	# health_bar is a MeshInstance3D whose mesh uses health_bar.gdshader.
	# Pre-refactor logic used instance shader parameters (`fill_ratio` and
	# `fill_color`) to drive the visual — the post-refactor scale.x +
	# StandardMaterial3D override clobbered the shader and broke the bar
	# entirely. Restored to the shader-param approach.
	if _host.health_bar == null:
		return
	var ratio := clampf(float(_host._health) / float(_host.max_health), 0.0, 1.0)
	_host.health_bar.visible = _host._is_alive() and ratio < 1.0
	_host.health_bar.set_instance_shader_parameter(&"fill_ratio", ratio)
	# Charmed pets fight FOR the player; their bar reads green so the
	# player can scan a knot of bodies and tell allies from hostiles
	# without inspecting each one.
	var color: Color = PrototypeEnemy._HP_BAR_FRIENDLY if _host._afflictions._charmed else PrototypeEnemy._HP_BAR_HOSTILE
	_host.health_bar.set_instance_shader_parameter(&"fill_color", color)
