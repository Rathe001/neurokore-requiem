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


static var _logged_bones: bool = false


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
	if not _logged_bones:
		var all_names: Array[String] = []
		for i in range(skeleton.get_bone_count()):
			all_names.append(skeleton.get_bone_name(i))
		print("[XBotRagdoll] Skeleton has %d bones: %s" % [skeleton.get_bone_count(), all_names])
		_logged_bones = true
	var bones_attached := 0
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
		# Tighten the cone constraint so limbs don't hyperextend — Godot's
		# defaults are very permissive (~90° swing). 35° swing + 20°
		# twist reads as "limbs hold roughly natural pose under gravity"
		# without going fully rigid.
		#
		# Critical: bias near zero, softness near one. The cone's REST
		# pose is the skeleton's BIND pose (T-pose for Mixamo) — bias
		# governs how hard the constraint pulls bones BACK to that rest.
		# At bias 0.6 the corpse collapsed into T-pose on the floor
		# because the joints kept dragging limbs toward bind. At 0.05
		# the cone still LIMITS rotation but doesn't actively restore
		# to it — corpses stay in whatever pose they landed in.
		if joint_type == PhysicalBone3D.JOINT_TYPE_CONE:
			pb.set("joint_constraints/swing_span", deg_to_rad(40.0))
			pb.set("joint_constraints/twist_span", deg_to_rad(25.0))
			pb.set("joint_constraints/bias", 0.05)
			pb.set("joint_constraints/softness", 0.95)
			pb.set("joint_constraints/relaxation", 1.0)
		bones_attached += 1
	print("[XBotRagdoll] Attached %d PhysicalBone3D(s)" % bones_attached)
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
