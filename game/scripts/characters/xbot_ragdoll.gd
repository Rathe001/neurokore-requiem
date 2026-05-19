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


## Adds PhysicalBone3D children to `skeleton` for each major Mixamo bone.
## Idempotent — sets a meta flag so a second call (e.g. enemy re-acquired
## from EntityPool) skips re-creating the bones.
static func setup(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	if skeleton.has_meta(_META_KEY):
		return
	for entry in _BONES:
		var bone_name: StringName = entry[0]
		var mass: float = entry[1]
		var radius: float = entry[2]
		var joint_type: int = entry[3]
		var bone_idx: int = skeleton.find_bone(bone_name)
		if bone_idx < 0:
			continue
		var pb := PhysicalBone3D.new()
		pb.bone_name = String(bone_name)
		pb.mass = mass
		pb.joint_type = joint_type
		# Layer 6 (Corpses) so the ragdoll collides with World only — live
		# enemies / the player walk through it, matching the existing
		# PrototypeRagdollCorpse policy.
		pb.collision_layer = 32  # 1 << 5
		pb.collision_mask = 1    # World layer
		var caps := CapsuleShape3D.new()
		caps.radius = radius
		caps.height = _bone_length(skeleton, bone_idx, radius)
		var col := CollisionShape3D.new()
		col.shape = caps
		pb.add_child(col)
		skeleton.add_child(pb)
	skeleton.set_meta(_META_KEY, true)


## Flips the skeleton into physics-driven mode. Every PhysicalBone3D
## previously added by setup() becomes a falling rigid body; the
## Skeleton3D writes their world transforms back to its bones each
## frame, so the visual mesh deforms with the ragdoll.
static func activate(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	skeleton.physical_bones_start_simulation()


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
