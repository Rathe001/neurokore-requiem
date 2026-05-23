class_name WeaponAttachment extends RefCounted

## Attaches a visible weapon model to an X Bot skeleton's right hand.
##
## The Phase 2 stance animations imply a held weapon (rifle-aim pose,
## sword stance, etc.) but the hand was empty. This helper closes the
## loop: `set_weapon(skeleton, weapon_base_id)` mounts the matching glb
## on a BoneAttachment3D parented to the hand bone, so the weapon
## follows the hand through every animation frame.
##
## Shared by player + enemies (both use the X Bot mesh) — same pattern
## as XBotAnimations / XBotRagdoll.
##
## GRIP TUNING: each Blenderkit weapon glb has its own pivot, scale,
## and orientation, so the per-weapon entries in _GRIP below need
## hand-tuning by eye in the editor. The model is auto-scaled to a
## per-class target length first (removes the worst guessing axis),
## then the dict's pos/rot/scale_mult fine-tune. Defaults are rough
## first guesses — expect to iterate.

# The skeleton bone the weapon mounts to. Mixamo's raw name is
# "mixamorig_RightHand"; the BoneMap retarget may rewrite it to the
# SkeletonProfileHumanoid name "RightHand". We try both.
const _HAND_BONE_RAW: StringName = &"mixamorig_RightHand"
const _HAND_BONE_PROFILE: StringName = &"RightHand"

# Node name for the BoneAttachment3D we add to the skeleton. Idempotent
# lookup keys off this.
const _ATTACH_NODE_NAME: StringName = &"WeaponMount"
const _MODEL_NODE_NAME: StringName = &"WeaponModel"

# weapon_base_id → glb path. The 11 weapon archetypes; grenade is an
# offhand and isn't hand-mounted here.
const _WEAPON_MODELS: Dictionary = {
	&"melee_1h":       "res://assets/models/weapons/blade/blade.glb",
	&"melee_2h":       "res://assets/models/weapons/hammer/hammer.glb",
	&"ranged_1h":      "res://assets/models/weapons/laser_pistol/laser_pistol.glb",
	&"ranged_2h":      "res://assets/models/weapons/plasma_rifle/plasma_rifle.glb",
	&"smg_1h":         "res://assets/models/weapons/smg/smg.glb",
	&"lmg_2h":         "res://assets/models/weapons/lmg/lmg.glb",
	&"sniper_2h":      "res://assets/models/weapons/sniper/sniper.glb",
	&"rpg_2h":         "res://assets/models/weapons/rpg/rpg.glb",
	&"shotgun_2h":     "res://assets/models/weapons/shotgun/shotgun.glb",
	&"accelerator_2h": "res://assets/models/weapons/energy_accelerator/energy_accelerator.glb",
	&"taser_2h":       "res://assets/models/weapons/arc_taser/arc_taser.glb",
}

# Per-weapon-class target length (metres) for the model's longest axis.
# The model is auto-scaled so its AABB longest dimension hits this,
# normalising the wildly different source-glb scales (laser_pistol
# ships at ±3 units, plasma_rifle at ±0.5).
const _CLASS_TARGET_LENGTH: Dictionary = {
	&"pistol":   0.32,
	&"rifle":    0.95,
	&"melee_1h": 0.95,
	&"melee_2h": 1.25,
}
const _DEFAULT_TARGET_LENGTH: float = 0.6

# Per-weapon grip fine-tune, applied AFTER auto-scale. Hand-tune these
# in the editor — each glb's pivot sits in a different place relative
# to where a hand should grip it, and each one's authored forward axis
# varies (Blenderkit uploads don't agree on a convention).
#   pos        — Vector3 local offset from the hand bone
#   rot        — Vector3 euler degrees (applied as model.rotation_degrees)
#   scale_mult — extra multiplier on top of the auto-scale
#
# First-pass rotation: -90° around Y on every weapon, because the
# Blenderkit guns we imported are authored with barrel along their
# local +X or +Y, but the Mixamo right-hand bone's "forward" (palm /
# barrel direction) points along bone-local -Z. The 90° swing puts
# barrels roughly in line with the character's facing direction. Per-
# weapon offsets still need eyeball tuning from there.
# Mutable at runtime so the live grip tuner (PrototypeCamera + GripTuner
# in inspect-mode) can bump rotation/position/scale by key, then dump
# the result to the console for permanent pasting back here. Each entry
# starts at identity / zero — the keys still ride the auto-scale, so
# they read as "neutral grip" until tuned.
static var _GRIP: Dictionary = {
	&"melee_1h":       {"pos": Vector3(0.500, 0.100, 0.050), "rot": Vector3(0.0, 90.0, -75.0), "scale_mult": 1.318},
	&"melee_2h":       {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scale_mult": 1.0},
	&"ranged_1h":      {"pos": Vector3(0.050, 0.100, 0.050), "rot": Vector3(-75.0, 0.0, 0.0), "scale_mult": 1.0},
	&"ranged_2h":      {"pos": Vector3(0.050, 0.350, -0.050), "rot": Vector3(-90.0, -180.0, 0.0), "scale_mult": 1.0},
	&"smg_1h":         {"pos": Vector3(0.050, 0.200, 0.050), "rot": Vector3(-105.0, -180.0, 0.0), "scale_mult": 1.611},
	&"lmg_2h":         {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scale_mult": 1.0},
	&"sniper_2h":      {"pos": Vector3(0.000, 0.350, 0.050), "rot": Vector3(-15.0, 75.0, -90.0), "scale_mult": 1.331},
	&"rpg_2h":         {"pos": Vector3(0.100, 0.350, 0.000), "rot": Vector3(-90.0, 165.0, 0.0), "scale_mult": 1.089},
	&"shotgun_2h":     {"pos": Vector3(-0.150, 0.350, -0.000), "rot": Vector3(-105.0, 90.0, 165.0), "scale_mult": 1.067},
	&"accelerator_2h": {"pos": Vector3(-0.150, 0.350, -0.000), "rot": Vector3(-105.0, 90.0, 165.0), "scale_mult": 1.000},
	&"taser_2h":       {"pos": Vector3(0.000, 0.250, 0.150), "rot": Vector3(-90.0, 0.0, -15.0), "scale_mult": 0.729},
}


## Mounts (or swaps, or clears) the weapon model on `skeleton`'s right
## hand. Pass &"" to clear (bare hands). Idempotent — re-calling with
## the same id rebuilds cleanly. Safe to call on a skeleton that has
## no right-hand bone (no-op).
static func set_weapon(skeleton: Skeleton3D, weapon_base_id: StringName) -> void:
	if skeleton == null:
		return
	var mount := _ensure_mount(skeleton)
	if mount == null:
		return
	# Clear any existing weapon model.
	var existing := mount.get_node_or_null(NodePath(_MODEL_NODE_NAME))
	if existing != null:
		mount.remove_child(existing)
		existing.queue_free()
	# Empty / unknown id → bare hands.
	var model_path: String = _WEAPON_MODELS.get(weapon_base_id, "")
	if model_path == "" or not ResourceLoader.exists(model_path):
		return
	var packed := load(model_path) as PackedScene
	if packed == null:
		return
	var model := packed.instantiate() as Node3D
	if model == null:
		return
	model.name = _MODEL_NODE_NAME
	mount.add_child(model)
	_apply_grip(model, weapon_base_id)


# EnemyClass.weapon_id uses a looser model-name namespace than the
# player's Item.weapon_base_id (&"blade" not &"melee_1h", &"sledgehammer"
# not &"melee_2h", &"sniper_rifle" not &"sniper_2h"). Alias the enemy
# names onto the canonical base ids so both feed the same model table.
const _ENEMY_WEAPON_ID_ALIAS: Dictionary = {
	&"blade":        &"melee_1h",
	&"sledgehammer": &"melee_2h",
	&"laser_pistol": &"ranged_1h",
	&"plasma_rifle": &"ranged_2h",
	&"smg":          &"smg_1h",
	&"lmg":          &"lmg_2h",
	&"sniper_rifle": &"sniper_2h",
	&"rpg":          &"rpg_2h",
	&"shotgun":      &"shotgun_2h",
	&"accelerator":  &"accelerator_2h",
	&"taser":        &"taser_2h",
}


## Enemy-facing variant of set_weapon. EnemyClass.weapon_id carries
## model names (&"blade", &"sledgehammer", &"sniper_rifle") rather than
## the player's canonical weapon_base_id; this resolves the alias and
## mounts the model. Unknown / empty id → bare hands.
static func set_weapon_for_enemy(skeleton: Skeleton3D, enemy_weapon_id: StringName) -> void:
	var base_id: StringName = _ENEMY_WEAPON_ID_ALIAS.get(enemy_weapon_id, &"")
	set_weapon(skeleton, base_id)


## ─── Live grip tuner ────────────────────────────────────────────────────
##
## The following statics let an in-game keyboard tuner adjust the mounted
## weapon's pos / rot / scale_mult on the fly and reapply without rebuilding
## the model. The flow is:
##   1. PrototypeCamera (in inspect mode) reads keypresses and calls
##      bump_grip(base_id, ...) — this mutates the _GRIP entry.
##   2. After mutation, it calls reapply_grip(skeleton, base_id) which
##      re-runs _apply_grip on the live WeaponModel child of the mount.
##   3. When the user is happy, dump_grip_to_console(base_id) prints the
##      final values in a ready-to-paste format so they can be baked back
##      into _GRIP as the new default.

## Returns the current grip dict for `weapon_base_id` (creates a default
## entry if missing). Safe to mutate the returned dict in place.
static func get_grip(weapon_base_id: StringName) -> Dictionary:
	if not _GRIP.has(weapon_base_id):
		_GRIP[weapon_base_id] = {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scale_mult": 1.0}
	return _GRIP[weapon_base_id]


## Adds `delta_deg` degrees to the rotation around `axis` ("x", "y", or
## "z") on this weapon's grip entry. No-op for unknown axis or empty id.
static func bump_rotation(weapon_base_id: StringName, axis: StringName, delta_deg: float) -> void:
	if weapon_base_id == &"":
		return
	var grip := get_grip(weapon_base_id)
	var r: Vector3 = grip.get("rot", Vector3.ZERO)
	match axis:
		&"x": r.x = wrapf(r.x + delta_deg, -180.0, 180.0)
		&"y": r.y = wrapf(r.y + delta_deg, -180.0, 180.0)
		&"z": r.z = wrapf(r.z + delta_deg, -180.0, 180.0)
		_: return
	grip["rot"] = r


## Adds `delta` (world units) to the position offset along `axis` on this
## weapon's grip entry.
static func bump_position(weapon_base_id: StringName, axis: StringName, delta: float) -> void:
	if weapon_base_id == &"":
		return
	var grip := get_grip(weapon_base_id)
	var p: Vector3 = grip.get("pos", Vector3.ZERO)
	match axis:
		&"x": p.x += delta
		&"y": p.y += delta
		&"z": p.z += delta
		_: return
	grip["pos"] = p


## Multiplies the scale_mult on this weapon's grip entry by `factor`.
## Clamped to [0.1, 10.0] so a sticky keypress can't blow it up.
static func bump_scale(weapon_base_id: StringName, factor: float) -> void:
	if weapon_base_id == &"":
		return
	var grip := get_grip(weapon_base_id)
	var s: float = float(grip.get("scale_mult", 1.0)) * factor
	grip["scale_mult"] = clampf(s, 0.1, 10.0)


## Resets this weapon's grip entry to neutral (zero rotation, zero
## position, scale_mult 1.0).
static func reset_grip(weapon_base_id: StringName) -> void:
	if weapon_base_id == &"":
		return
	_GRIP[weapon_base_id] = {"pos": Vector3.ZERO, "rot": Vector3.ZERO, "scale_mult": 1.0}


## Re-applies the current grip values to the weapon model already mounted
## on `skeleton`. Used by the live tuner so each keypress immediately
## shows on screen without rebuilding the model.
static func reapply_grip(skeleton: Skeleton3D, weapon_base_id: StringName) -> void:
	if skeleton == null or weapon_base_id == &"":
		return
	var mount := get_mount(skeleton)
	if mount == null:
		return
	var model := mount.get_node_or_null(NodePath(_MODEL_NODE_NAME)) as Node3D
	if model == null:
		return
	_apply_grip(model, weapon_base_id)


## Prints the current grip entry to the console in a ready-to-paste
## format, so once tuning lands on values that read well in-game, the
## user can copy the line back into _GRIP as the new default.
static func dump_grip_to_console(weapon_base_id: StringName) -> void:
	var grip := get_grip(weapon_base_id)
	var p: Vector3 = grip.get("pos", Vector3.ZERO)
	var r: Vector3 = grip.get("rot", Vector3.ZERO)
	var s: float = float(grip.get("scale_mult", 1.0))
	print('\t&"%s": {"pos": Vector3(%.3f, %.3f, %.3f), "rot": Vector3(%.1f, %.1f, %.1f), "scale_mult": %.3f},' % [
		String(weapon_base_id), p.x, p.y, p.z, r.x, r.y, r.z, s,
	])


## World-space position of the mounted weapon's muzzle, computed as the
## corner of the model's combined AABB that's farthest along the supplied
## aim direction. After per-weapon grip tuning the model's barrel points
## along the character's aim, so this resolves to the actual barrel tip
## for both bullet projectiles and hitscan ray origins. Returns
## Vector3.ZERO when no weapon model is mounted — callers should fall
## back to their legacy "chest + forward" approximation in that case.
static func get_muzzle_position(skeleton: Skeleton3D, aim_world: Vector3) -> Vector3:
	if skeleton == null:
		return Vector3.ZERO
	var mount := get_mount(skeleton)
	if mount == null:
		return Vector3.ZERO
	var model := mount.get_node_or_null(NodePath(_MODEL_NODE_NAME)) as Node3D
	if model == null:
		return Vector3.ZERO
	var aabb := _model_aabb(model)
	var aim := aim_world.normalized()
	# Test the 8 corners of the model AABB in world space; the one with
	# the largest dot product with aim is the most-forward point along
	# the firing line — i.e., the muzzle tip after grip rotation.
	var best := mount.global_position
	var best_score := -INF
	for i in 8:
		var corner_local := aabb.position + Vector3(
			aabb.size.x if (i & 1) != 0 else 0.0,
			aabb.size.y if (i & 2) != 0 else 0.0,
			aabb.size.z if (i & 4) != 0 else 0.0,
		)
		var corner_world := model.to_global(corner_local)
		var s: float = corner_world.dot(aim)
		if s > best_score:
			best_score = s
			best = corner_world
	return best


## Returns the existing weapon mount on `skeleton`, or null if none has
## been created yet (set_weapon was never called). Lets callers re-apply
## render layers / shadow flags to the mounted model after a swap.
static func get_mount(skeleton: Skeleton3D) -> BoneAttachment3D:
	if skeleton == null:
		return null
	return skeleton.get_node_or_null(NodePath(_ATTACH_NODE_NAME)) as BoneAttachment3D


# Finds the BoneAttachment3D mount on `skeleton`, creating it on first
# call. Returns null when the skeleton has no recognisable right-hand
# bone (non-X-Bot mesh).
static func _ensure_mount(skeleton: Skeleton3D) -> BoneAttachment3D:
	var existing := skeleton.get_node_or_null(NodePath(_ATTACH_NODE_NAME)) as BoneAttachment3D
	if existing != null:
		return existing
	var bone_idx := skeleton.find_bone(_HAND_BONE_RAW)
	if bone_idx < 0:
		bone_idx = skeleton.find_bone(_HAND_BONE_PROFILE)
	if bone_idx < 0:
		push_warning("[WeaponAttachment] no right-hand bone on skeleton %s" % skeleton.name)
		return null
	var mount := BoneAttachment3D.new()
	mount.name = _ATTACH_NODE_NAME
	skeleton.add_child(mount)
	mount.bone_idx = bone_idx
	return mount


# Auto-scales `model` so its longest AABB axis matches the per-class
# target length, then applies the per-weapon grip pos/rot/scale_mult.
static func _apply_grip(model: Node3D, weapon_base_id: StringName) -> void:
	var cls: StringName = XBotAnimations.weapon_class_for_id(weapon_base_id)
	var target_len: float = float(_CLASS_TARGET_LENGTH.get(cls, _DEFAULT_TARGET_LENGTH))
	# Measure the model's combined AABB to derive the auto-scale.
	var aabb := _model_aabb(model)
	var longest: float = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	var auto_scale: float = (target_len / longest) if longest > 0.001 else 1.0
	var grip: Dictionary = _GRIP.get(weapon_base_id, {})
	var scale_mult: float = float(grip.get("scale_mult", 1.0))
	model.scale = Vector3.ONE * auto_scale * scale_mult
	model.position = grip.get("pos", Vector3.ZERO)
	model.rotation_degrees = grip.get("rot", Vector3.ZERO)


# Combined local-space AABB of every VisualInstance3D under `root`.
static func _model_aabb(root: Node) -> AABB:
	var out: AABB = AABB()
	var found := false
	for vi in _all_visual_instances(root):
		var box := vi.get_aabb()
		# Transform into the model-root's local space.
		var local := (root as Node3D).global_transform.affine_inverse() * vi.global_transform if root is Node3D else vi.transform
		var world_box := local * box
		if not found:
			out = world_box
			found = true
		else:
			out = out.merge(world_box)
	return out


static func _all_visual_instances(root: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if root is VisualInstance3D:
		out.append(root as VisualInstance3D)
	for child in root.get_children():
		out.append_array(_all_visual_instances(child))
	return out
