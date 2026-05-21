class_name EnemyVisuals
extends Node
## Extracted from PrototypeEnemy — hover/outline, tooltip, display,
## floor ring, model tint, hit squash, health bar.

var _host: PrototypeEnemy

# Outline meshes collected from the visual tree.
var _outlined_meshes: Array[MeshInstance3D] = []
var _hovered: bool = false
var _tooltip_locked: bool = false

# Floor ring material instance (per-enemy, owns its emission color).
var _floor_ring_mat: StandardMaterial3D


func setup(host: PrototypeEnemy) -> void:
	_host = host


func reset() -> void:
	# Detach any outline copies the compositor is holding for our meshes
	# before clearing the list — otherwise pool-acquired enemies of a
	# different class would carry over the previous outline.
	for m in _outlined_meshes:
		if is_instance_valid(m):
			OutlineCompositor.detach(m)
	_hovered = false
	_tooltip_locked = false
	_outlined_meshes.clear()


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
	# Outline now routes through OutlineCompositor (screen-space silhouette)
	# instead of the previous grow+cull-front material_overlay trick. The old
	# approach drew every hard-normal seam as an internal line on the new
	# Mixamo character meshes; the screen-space version gives a clean single
	# silhouette regardless of mesh authoring. material_overlay also no longer
	# fights with HitFlash for the same slot.
	#
	# Color hierarchy (lock > rarity > regular):
	#   locked          → red    (OUTLINE_LOCKED_COLOR)   targeting signal
	#   boss / named / affixed → gold (OUTLINE_SPECIAL_COLOR) "this one's special"
	#   regular hover   → white                                  default
	var should_show := _hovered or _tooltip_locked
	var color: Color
	if _tooltip_locked:
		color = PrototypeEnemy.OUTLINE_LOCKED_COLOR
	elif _is_special_enemy():
		color = PrototypeEnemy.OUTLINE_SPECIAL_COLOR
	else:
		color = Color.WHITE
	for mesh in _outlined_meshes:
		if not is_instance_valid(mesh):
			continue
		if should_show:
			OutlineCompositor.attach(mesh, color)
		else:
			OutlineCompositor.detach(mesh)


# True when the enemy warrants the special-rarity outline tint —
# bosses, named encounters, or any affixed (rare-pack) monster.
func _is_special_enemy() -> bool:
	if _host == null:
		return false
	if _host.is_boss:
		return true
	if _host.named_monster != null:
		return true
	if not _host.affixes.is_empty():
		return true
	return false


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

## Color-codes the enemy to signal class / affix / named identity.
## Re-implemented as an ALBEDO blend (not emission) so the tint reads
## at any lighting level without making the enemy self-lit. Pure
## emission lit them up in dark rooms; multiplying albedo just shifts
## the surface color and lets the room's lights still control how
## visible the enemy is.
func apply_model_tint(color: Color) -> void:
	if _host.visual == null:
		return
	_walk_and_tint(_host.visual, color)


func _walk_and_tint(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		var surf_count: int = mi.mesh.get_surface_count() if mi.mesh != null else 0
		for surf_idx in surf_count:
			var base_mat := mi.mesh.surface_get_material(surf_idx)
			if base_mat == null:
				continue
			# Duplicate so we don't mutate the shared resource (every
			# enemy of this archetype would otherwise share the tint).
			var mat: BaseMaterial3D = base_mat.duplicate()
			if mat is StandardMaterial3D:
				# Lerp from white toward the tint at 55% strength —
				# tints the surface clearly while preserving most of
				# the base brightness so the mesh doesn't darken in
				# already-dim rooms. emission stays OFF, so the
				# enemy doesn't self-illuminate.
				var blend: float = 0.55
				mat.albedo_color = Color(
					lerpf(1.0, color.r, blend),
					lerpf(1.0, color.g, blend),
					lerpf(1.0, color.b, blend),
				)
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
