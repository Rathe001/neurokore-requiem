class_name XBotRagdoll
extends RefCounted

## Per-bone physics ragdoll for X Bot. setup() attaches a PhysicalBone3D
## (with capsule collision shape) to each major Mixamo skeleton bone so
## activate() can flip the whole rig into physics mode via
## Skeleton3D.physical_bones_start_simulation().
##
## Skipped bones: fingers (too small to read at iso distance, would just
## inflate the per-corpse rigid-body count for no visible payoff).
##
## Bone parent hierarchy in the Skeleton3D itself drives the joint chain
## — we just set joint_type so each bone is constrained to its parent in
## the simulator. JOINT_TYPE_CONE works well for limbs without explicit
## limit configuration (uses sensible defaults).

# (bone_name, mass_kg, capsule_radius_m, joint_type)
# Mass distribution roughly anatomical: torso ~30kg, legs ~12kg each,
# arms ~5kg each, head 4kg. Total ~68kg matches a 1.78m mannequin.
const _BONES: Array[Array] = [
	[&"mixamorig_Hips",         12.0, 0.18, PhysicalBone3D.JOINT_TYPE_NONE],
	[&"mixamorig_Spine",         8.0, 0.15, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_Spine1",        8.0, 0.15, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_Spine2",        6.0, 0.14, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_Neck",          1.5, 0.06, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_Head",          4.0, 0.10, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_LeftShoulder",  1.5, 0.08, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_LeftArm",       2.5, 0.07, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_LeftForeArm",   1.8, 0.06, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_LeftHand",      0.8, 0.05, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_RightShoulder", 1.5, 0.08, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_RightArm",      2.5, 0.07, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_RightForeArm",  1.8, 0.06, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_RightHand",     0.8, 0.05, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_LeftUpLeg",     7.0, 0.10, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_LeftLeg",       4.5, 0.09, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_LeftFoot",      1.5, 0.07, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_RightUpLeg",    7.0, 0.10, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_RightLeg",      4.5, 0.09, PhysicalBone3D.JOINT_TYPE_CONE],
	[&"mixamorig_RightFoot",     1.5, 0.07, PhysicalBone3D.JOINT_TYPE_CONE],
]

const _META_KEY: StringName = &"xbot_ragdoll_setup"


## Walks the MeshInstance3D subtree under `root` and assigns a default
## StandardMaterial3D to any surface whose active material resolves to
## null. RenderingServer fires `material_casts_shadows: Parameter
## "material" is null` (and friends) at startup when even a single mesh
## surface ships without a material — typical of FBX imports where the
## DCC tool didn't bake a material slot for every sub-mesh.
##
## The default material is intentionally bland (mid-grey, low metallic);
## anything important should have its own material assigned in the FBX.
## This is a safety net to silence the renderer warnings, not a
## replacement for proper material authoring.
static func ensure_surface_materials(root: Node) -> void:
	if root == null:
		return
	# Two different code paths because the surface-material API differs
	# between subtypes:
	#   - MeshInstance3D: per-MI surface override via
	#     get_active_material / set_surface_override_material
	#   - MultiMeshInstance3D: no per-surface override on the MMI; the
	#     fallback has to land on the shared source mesh (ArrayMesh)
	#     via surface_set_material, OR on material_override for non-
	#     ArrayMesh sources.
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				if mi.get_active_material(i) == null:
					mi.set_surface_override_material(i, _make_fallback_material())
			_backfill_mesh_materials(mi.mesh)
	elif root is MultiMeshInstance3D:
		var mmi := root as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			var mesh: Mesh = mmi.multimesh.mesh
			if mesh is ArrayMesh:
				var arr_mesh := mesh as ArrayMesh
				for i in range(arr_mesh.get_surface_count()):
					if arr_mesh.surface_get_material(i) == null:
						arr_mesh.surface_set_material(i, _make_fallback_material())
			elif mmi.material_override == null:
				# PrimitiveMesh / other Mesh subtypes — surface_set_material
				# isn't available, so fall back to material_override on the
				# MMI itself. Skipped when an override already exists.
				var has_null_surface: bool = false
				for i in range(mesh.get_surface_count()):
					if mesh.surface_get_material(i) == null:
						has_null_surface = true
						break
				if has_null_surface:
					mmi.material_override = _make_fallback_material()
			# Mesh-level backfill regardless of override — the server's
			# dependency/shadow passes query the SOURCE mesh's surface
			# material even when an override resolves the draw.
			_backfill_mesh_materials(mesh)
	for child in root.get_children():
		ensure_surface_materials(child)


# MESH-level backfill — the RenderingServer's shadow / dependency /
# animated-uniform passes query the MESH surface material DIRECTLY;
# material_override and surface overrides do not suppress those queries
# (documented independently in VfxWarmup + WallBuilder's shadow-stub
# notes). Any mesh resource with a null surface material spams 4
# "Parameter 'material' is null" errors per instance per build/frame
# even when an override resolves the visible draw. Assigning the shared
# fallback at the MESH level satisfies the queries; overrides still win
# the visible render, so this never changes how anything looks.
# Shared/cached meshes (unit boxes, primitive pools) are safe to mutate
# — the fallback is a single shared instance, assignment idempotent.
static func _backfill_mesh_materials(mesh: Mesh) -> void:
	if mesh is PrimitiveMesh:
		var pm := mesh as PrimitiveMesh
		if pm.material == null:
			pm.material = _make_fallback_material()
	elif mesh is ArrayMesh:
		var am := mesh as ArrayMesh
		for i in range(am.get_surface_count()):
			if am.surface_get_material(i) == null:
				am.surface_set_material(i, _make_fallback_material())


# Bland default — matte mid-grey, 0% metallic. Used as the fallback
# whenever ensure_surface_materials finds a null-material surface.
static var _fallback_material: StandardMaterial3D = null

# SHARED single instance — this runs from material_guard's node_added
# hook on every null-surface node entering the tree, and material
# creation mid-frame is a render-thread sync (laser-hitch class). The
# fallback is assignment-only, never mutated, so one instance is safe.
static func _make_fallback_material() -> StandardMaterial3D:
	if _fallback_material == null:
		_fallback_material = StandardMaterial3D.new()
		_fallback_material.albedo_color = Color(0.6, 0.6, 0.6)
		_fallback_material.roughness = 0.85
		_fallback_material.metallic = 0.0
	return _fallback_material


# Single-node, non-recursive variant of ensure_surface_materials —
# checks just the surfaces on `node` itself. Designed for the
# scene_tree.node_added signal: when each individual node fires the
# signal, processing just that node avoids the double-work of also
# recursing into its descendants (which will themselves fire
# node_added separately as the tree-add propagates).
static func ensure_surface_materials_single(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in range(mi.mesh.get_surface_count()):
				if mi.get_active_material(i) == null:
					mi.set_surface_override_material(i, _make_fallback_material())
			_backfill_mesh_materials(mi.mesh)
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.mesh != null:
			var mesh: Mesh = mmi.multimesh.mesh
			if mesh is ArrayMesh:
				var arr_mesh := mesh as ArrayMesh
				for i in range(arr_mesh.get_surface_count()):
					if arr_mesh.surface_get_material(i) == null:
						arr_mesh.surface_set_material(i, _make_fallback_material())
			elif mmi.material_override == null:
				var has_null_surface: bool = false
				for i in range(mesh.get_surface_count()):
					if mesh.surface_get_material(i) == null:
						has_null_surface = true
						break
				if has_null_surface:
					mmi.material_override = _make_fallback_material()
			# Mesh-level backfill regardless of override — the server's
			# dependency/shadow passes query the SOURCE mesh's surface
			# material even when an override resolves the draw.
			_backfill_mesh_materials(mesh)


## Walks from `skeleton` UP through its Node3D ancestors (stopping at
## `stop_at` exclusive), replacing any non-uniform basis with an
## orthonormalized basis carrying the average of the three axis scales.
## After this runs, the entire chain from `skeleton` to just below
## `stop_at` is guaranteed uniform-scaled.
##
## Why: Mixamo FBXs imported with apply_root_scale carry small per-axis
## scale residue (~0.99/1.01) on intermediate Armature/Skeleton nodes.
## The per-PhysicalBone3D `pb.scale = 1/gs` compensation in setup() and
## activate() only fully cancels parent scale when the parent basis is
## axis-aligned. With rotation mixed in (which Mixamo's bone orientations
## always have), the component-wise inverse leaves a residual non-uniform
## global scale that Jolt re-evaluates and warns about every physics
## frame during ragdoll simulation — historically tens of thousands of
## _try_build_shape warnings per session.
##
## Doing it once at spawn permanently sanitises the chain. The visual
## cost is the averaged scale (~0.998 vs 1.0) — imperceptible at iso.
## Idempotent via `_PARENT_CHAIN_META`.
const _PARENT_CHAIN_META: StringName = &"xbot_ragdoll_chain_normalized"
static func normalize_parent_chain_scale(skeleton: Skeleton3D, stop_at: Node) -> void:
	if skeleton == null:
		return
	if skeleton.has_meta(_PARENT_CHAIN_META):
		return
	skeleton.set_meta(_PARENT_CHAIN_META, true)
	var node: Node = skeleton
	while node != null and node != stop_at and node is Node3D:
		var nx := node as Node3D
		var s: Vector3 = nx.transform.basis.get_scale()
		if not (is_equal_approx(s.x, s.y) and is_equal_approx(s.y, s.z)):
			var avg: float = (s.x + s.y + s.z) / 3.0
			nx.transform.basis = nx.transform.basis.orthonormalized().scaled(Vector3.ONE * avg)
		node = nx.get_parent()




## Adds PhysicalBone3D children to `skeleton` for each major bone.
## Idempotent — sets a meta flag so a second call (e.g. enemy re-acquired
## from EntityPool) skips re-creating the bones.
##
## Tolerates two skeleton naming conventions:
##   - Raw Mixamo:           "mixamorig_Hips", "mixamorig_LeftArm", ...
##   - Humanoid profile:     "Hips", "LeftUpperArm", ...
## The BoneMap retargeter sometimes rewrites the skeleton's bone names to
## the SkeletonProfileHumanoid set, so we look up each entry under both
## possible names.
static func setup(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	if skeleton.has_meta(_META_KEY):
		return
	for entry in _BONES:
		var preferred: StringName = entry[0]
		var mass: float = entry[1]
		var radius: float = entry[2]
		var joint_type: int = entry[3]
		var bone_idx: int = _find_bone_either(skeleton, preferred)
		if bone_idx < 0:
			continue
		var actual_name := skeleton.get_bone_name(bone_idx)
		var pb := PhysicalBone3D.new()
		pb.bone_name = actual_name
		pb.mass = mass
		pb.joint_type = joint_type
		# Layer 6 (Corpses) so the ragdoll collides with World only — live
		# enemies / the player walk through it, matching the existing
		# PrototypeRagdollCorpse policy.
		pb.collision_layer = 32  # 1 << 5
		pb.collision_mask = 1    # World layer
		# Damping bleeds energy out of the simulation so corpses settle
		# instead of flopping forever. Tuned to read as "limp but
		# coherent" rather than "rag in a hurricane".
		pb.linear_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
		pb.linear_damp = 1.8
		pb.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
		pb.angular_damp = 4.0
		var caps := CapsuleShape3D.new()
		caps.radius = radius
		caps.height = _bone_length(skeleton, bone_idx, radius)
		var col := CollisionShape3D.new()
		col.shape = caps
		pb.add_child(col)
		skeleton.add_child(pb)
		# Jolt rejects non-uniform global scale on bodies. New character
		# meshes (vanguard / alien / military_man / crypto) import with
		# small non-uniform scale baked into the visual ancestor chain
		# (typical FBX import residue), which every PhysicalBone3D
		# inherits — spamming `_try_build_shape: Failed to correctly
		# scale body` once per limb per spawn. Counter-scale locally so
		# the body lands at uniform global scale.
		var gs := pb.global_transform.basis.get_scale()
		if not (is_equal_approx(gs.x, gs.y) and is_equal_approx(gs.y, gs.z)):
			pb.scale = Vector3(1.0 / gs.x, 1.0 / gs.y, 1.0 / gs.z)
		# Cone constraint shape. The cone is CENTERED on the bone's rest
		# orientation (Mixamo bind pose = T-pose for X Bot), so its
		# swing_span dictates how far each limb can deviate from
		# T-pose before the constraint clamps. At 40° the cone was
		# locking shoulders / hips before limbs could fully fall to
		# natural rest positions, so corpses froze splayed flat on the
		# floor.
		#
		# At 90° swing the cone is wide enough that gravity actually
		# pulls arms/legs to natural fallen angles before they clamp.
		# bias=0 makes the cone purely a LIMIT (no active restoring
		# pull toward T-pose); softness=1 disables the spring-back.
		if joint_type == PhysicalBone3D.JOINT_TYPE_CONE:
			pb.set("joint_constraints/swing_span", deg_to_rad(90.0))
			pb.set("joint_constraints/twist_span", deg_to_rad(60.0))
			# bias / softness / relaxation are Bullet-physics-era params.
			# Jolt Physics ignores them and warns each time you set one
			# ("Cone twist joint softness is not supported when using Jolt
			# Physics"). 500+ warnings in a single playtest. Skip setting
			# them at all — defaults from Godot are fine for Jolt.
	skeleton.set_meta(_META_KEY, true)


# Looks for `preferred` on the skeleton; if missing, tries the equivalent
# SkeletonProfileHumanoid name (LeftArm → LeftUpperArm, LeftLeg →
# LeftLowerLeg, etc.) and the bare name with the "mixamorig_" prefix
# stripped. Returns the matched bone index or -1.
static func _find_bone_either(skeleton: Skeleton3D, preferred: StringName) -> int:
	var idx := skeleton.find_bone(preferred)
	if idx >= 0:
		return idx
	var stripped := String(preferred).replace("mixamorig_", "")
	idx = skeleton.find_bone(stripped)
	if idx >= 0:
		return idx
	# Mixamo → humanoid profile name translations.
	const _MAP: Dictionary = {
		"mixamorig_Spine1": "Chest",
		"mixamorig_Spine2": "UpperChest",
		"mixamorig_LeftArm": "LeftUpperArm",
		"mixamorig_LeftForeArm": "LeftLowerArm",
		"mixamorig_RightArm": "RightUpperArm",
		"mixamorig_RightForeArm": "RightLowerArm",
		"mixamorig_LeftUpLeg": "LeftUpperLeg",
		"mixamorig_LeftLeg": "LeftLowerLeg",
		"mixamorig_LeftFoot": "LeftFoot",
		"mixamorig_RightUpLeg": "RightUpperLeg",
		"mixamorig_RightLeg": "RightLowerLeg",
		"mixamorig_RightFoot": "RightFoot",
	}
	var profile_name: String = _MAP.get(String(preferred), "")
	if profile_name != "":
		idx = skeleton.find_bone(profile_name)
		if idx >= 0:
			return idx
	return -1


## Marks a random subset of "tip" bones (hands, feet, forearms) for
## dismemberment by setting joint_type = JOINT_TYPE_NONE — so when
## physical_bones_start_simulation runs next, no joint is created and
## the bone becomes a free rigid body. Return the picked PhysicalBone3D
## list so the caller can apply extra impulse to send them flying.
##
## MUST be called AFTER `setup(skel)` and BEFORE `activate(skel, ...)`
## — the joint_type read happens at simulation start.
static func dismember_random_tips(skeleton: Skeleton3D, max_count: int = 2) -> Array[PhysicalBone3D]:
	var pool: Array[PhysicalBone3D] = []
	for child in skeleton.get_children():
		if not (child is PhysicalBone3D):
			continue
		var pb := child as PhysicalBone3D
		var n := String(pb.bone_name)
		# Tip bones — limbs that read cleanly when separated. ForeArms
		# detach below the elbow ("forearm fly-off"), Hands at the wrist,
		# Feet at the ankle. Head is intentionally excluded — decapitation
		# is a step further than what most crits should produce.
		if n.ends_with("Hand") or n.ends_with("Foot") or n.ends_with("ForeArm"):
			pool.append(pb)
	if pool.is_empty():
		return []
	pool.shuffle()
	var count: int = mini(max_count, pool.size())
	# Randomise count in [1, max_count] so not every crit kill produces
	# the same number of flying parts.
	count = randi_range(1, count)
	var picked: Array[PhysicalBone3D] = []
	for i in count:
		var pb := pool[i]
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
		picked.append(pb)
	return picked


## Flips the skeleton into physics-driven mode. Every PhysicalBone3D
## previously added by setup() becomes a falling rigid body; the
## Skeleton3D writes their world transforms back to its bones each
## frame, so the visual mesh deforms with the ragdoll.
##
## kill_from / kill_force apply an outward impulse along the (target -
## source) direction with a small upward lift — equivalent to the
## kick the old PrototypeRagdollCorpse capsule got on spawn. Pass
## Vector3.ZERO + 0.0 to skip the kick (e.g. ambient death).
static func activate(skeleton: Skeleton3D, kill_from: Vector3 = Vector3.ZERO, kill_force: float = 0.0) -> void:
	if skeleton == null:
		return
	# Align each PhysicalBone3D with the bone's current animated pose
	# before flipping on simulation, so the ragdoll inherits whatever
	# the running / idle / attack animation had it doing rather than the
	# bind pose. Orthonormalizing the basis is a side benefit — Mixamo
	# bind matrices carry tiny non-uniform scale residue that Jolt
	# rejects on collision shapes.
	#
	# Caveat (Godot 4.6.2): PhysicalBoneSimulator still initializes each
	# rigid body from the bone's REST pose regardless of pre-start
	# transforms, so a body activated cold snaps to T-pose for a frame.
	# Death no longer uses cold ragdoll — see prototype_enemy._die: the
	# death animation plays first and ragdoll only kicks in when an
	# explosion shoves the corpse. See memory `project_xbot_ragdoll`.
	for child in skeleton.get_children():
		if not (child is PhysicalBone3D):
			continue
		var pb := child as PhysicalBone3D
		var bone_idx: int = skeleton.find_bone(pb.bone_name)
		if bone_idx >= 0:
			var pose := skeleton.get_bone_global_pose(bone_idx)
			pose.basis = pose.basis.orthonormalized()
			pb.transform = pose
		else:
			pb.transform.basis = pb.transform.basis.orthonormalized()
		# Same Jolt non-uniform-scale guard as setup(): if the skeleton's
		# ancestor chain has non-uniform scale, counter it locally so the
		# body's global scale stays uniform at simulation start.
		var gs := pb.global_transform.basis.get_scale()
		if not (is_equal_approx(gs.x, gs.y) and is_equal_approx(gs.y, gs.z)):
			pb.scale = Vector3(1.0 / gs.x, 1.0 / gs.y, 1.0 / gs.z)
	skeleton.physical_bones_start_simulation()
	if kill_force <= 0.0:
		return
	# Direction from the hit source to the skeleton: pushes the corpse
	# away from the player / projectile.
	var dir: Vector3 = skeleton.global_position - kill_from
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3(0.0, 0.0, 1.0)
	dir = dir.normalized()
	# A bit of vertical lift makes the body kick off the ground rather
	# than scoot — matches the visceral feel of the old capsule tumble.
	dir.y = 0.5
	dir = dir.normalized()
	# apply_central_impulse takes impulse in N·s = mass × Δv. Scaling
	# by the bone's own mass gives a uniform Δv across hips + spine
	# regardless of the per-bone mass split. The 6× multiplier turns
	# typical knockback_strength values (5–25) into noticeable corpse
	# trajectories (~30–150 N·s on the hip's 12 kg gives a 2.5–12 m/s
	# launch); below that, the impulse was a gentle nudge.
	const IMPULSE_SCALE := 6.0
	# Hip + chest absorb the main impulse (they drag the rest along via
	# joints). Distributing to every bone over-spins limbs since each
	# bone is independently kicked.
	for child in skeleton.get_children():
		if not (child is PhysicalBone3D):
			continue
		var pb := child as PhysicalBone3D
		var bone_name_str: String = pb.bone_name
		if bone_name_str.contains("Hips") or bone_name_str.contains("Spine"):
			pb.apply_central_impulse(dir * kill_force * pb.mass * IMPULSE_SCALE)


# Returns a sensible capsule height for the bone based on its rest-pose
# distance to its first child bone. Falls back to a small default for
# end bones (hands, feet) that have no skeletal child.
static func _bone_length(skeleton: Skeleton3D, bone_idx: int, radius: float) -> float:
	var rest := skeleton.get_bone_global_rest(bone_idx)
	for i in range(skeleton.get_bone_count()):
		if skeleton.get_bone_parent(i) == bone_idx:
			var child_rest := skeleton.get_bone_global_rest(i)
			var dist: float = (child_rest.origin - rest.origin).length()
			return maxf(dist, radius * 2.0 + 0.02)
	# End bone — give a modest stub so the capsule has any height at all.
	return radius * 2.5
