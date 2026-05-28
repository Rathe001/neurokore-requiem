"""Merge a Mixamo "with skin" base character + N anim-only FBXs into
one .glb with all actions bound to the base armature.

Mixamo's per-anim FBXs all share the same `mixamorig:*` bone names, so
the actions retarget onto the base armature just by string-matching
bone references in the FCurves.

Each action gets pushed to its own muted NLA strip on the base armature
so the glTF exporter includes them as separate animation clips. Our
render pipeline (`01_render_sprite_sheet.py`) then assigns whichever
action it needs per frame.

Run:
    blender -b -P tools/pilot/merge_mixamo_anims.py

Output:
    ~/Desktop/crimson_vein_titan_mixamo.glb
"""
import sys
from pathlib import Path

import bpy  # type: ignore
import mathutils  # type: ignore

# ── Config ──────────────────────────────────────────────────────────────────

# Edit these constants per character; the rest of the script is
# character-agnostic.
#
# BASE_FBX is the "With Skin" Mixamo download — has the mesh + Mixamo
# armature + 1 baked action. ANIM_DIR is a folder of "Without Skin"
# Mixamo FBXs. For players, ANIM_DIR usually points to a shared
# directory so new player classes can reuse the same anim set.

# Repo-relative paths. SOURCE/ holds raw Meshy/Mixamo FBX downloads
# (gitignored — large binaries). BUILD/ holds the merged GLBs we feed
# into the renderer (also gitignored — regenerable).
PILOT_ROOT = Path(__file__).parent
SOURCE = PILOT_ROOT / "source"
BUILD  = PILOT_ROOT / "build"

PLAYER_DIR = SOURCE / "player"
SHARED_MALE_ANIMS: list[tuple[str, str]] = [
    ("Walking.fbx",                       "walk"),
    ("Running.fbx",                       "run"),
    ("Stable Sword Outward Slash.fbx",    "attack"),
    ("Side Kick.fbx",                     "attack2"),
    ("Standing Dodge Right.fbx",          "dodge"),
    ("Jump.fbx",                          "jump"),
    ("Head Hit.fbx",                      "hit"),
    ("Standing React Death Backward.fbx", "death"),
]
# Female lineup uses slightly different Mixamo clip names than male
# but the same set of actions. The Two Handed Sword Death clip is an
# extra death variant; for now we use Standing React Death Backward
# to keep parity with male's `death` slot.
SHARED_FEMALE_ANIMS: list[tuple[str, str]] = [
    ("Walking.fbx",                       "walk"),
    ("Running.fbx",                       "run"),
    ("Stable Sword Outward Slash.fbx",    "attack"),
    ("Mma Kick.fbx",                      "attack2"),
    ("Standing Dodge Right.fbx",          "dodge"),
    ("Standing Jump.fbx",                 "jump"),
    ("Head Hit.fbx",                      "hit"),
    ("Standing React Death Backward.fbx", "death"),
]

# --- Cyborg female player (Biomechanical Grace) ---------------------
BASE_FBX = PLAYER_DIR / "female" / "cyborg" / "Idle.fbx"
BASE_ACTION_SLUG = "idle"
ANIM_DIR = PLAYER_DIR / "female"
ANIMATIONS = SHARED_FEMALE_ANIMS
OUTPUT_GLB = BUILD / "cyborg_female.glb"

# --- Analog female player (Bandaged Gladiator) ----------------------
# BASE_FBX = PLAYER_DIR / "female" / "analog" / "Idle.fbx"
# BASE_ACTION_SLUG = "idle"
# ANIM_DIR = PLAYER_DIR / "female"
# ANIMATIONS = SHARED_FEMALE_ANIMS
# OUTPUT_GLB = BUILD / "analog_female.glb"

# --- Analog male player (Bandaged Gladiator) ------------------------
# BASE_FBX = PLAYER_DIR / "male" / "analog" / "Idle.fbx"
# BASE_ACTION_SLUG = "idle"
# ANIM_DIR = PLAYER_DIR / "male"
# ANIMATIONS = SHARED_MALE_ANIMS
# OUTPUT_GLB = BUILD / "analog_male.glb"

# --- Cyborg male player (Cyborg Gladiator) --------------------------
# BASE_FBX = PLAYER_DIR / "male" / "cyborg" / "Idle.fbx"
# BASE_ACTION_SLUG = "idle"
# ANIM_DIR = PLAYER_DIR / "male"
# ANIMATIONS = SHARED_MALE_ANIMS
# OUTPUT_GLB = BUILD / "cyborg_male.glb"

# --- Crimson Vein Titan enemy ---------------------------------------
# BASE_FBX = SOURCE / "enemies" / "crimson_vein_titan" / "Crouching Idle.fbx"
# BASE_ACTION_SLUG = "idle"
# ANIM_DIR = SOURCE / "enemies" / "crimson_vein_titan"
# ANIMATIONS = [
#     ("Crouch Walk Forward.fbx",            "walk"),
#     ("Standing 2H Magic Attack 01.fbx",    "cast"),
#     ("Standing React Small From Left.fbx", "hit"),
#     ("Zombie Death.fbx",                   "death"),
# ]
# OUTPUT_GLB = BUILD / "crimson_vein_titan.glb"


# ── Pipeline ────────────────────────────────────────────────────────────────


def import_base_character(fbx_path: Path):
    """Import the with-skin FBX; return (armature, mesh objects)."""
    bpy.ops.import_scene.fbx(filepath=str(fbx_path))
    armature = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if armature is None:
        raise RuntimeError(f"No armature in {fbx_path.name}")
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    print(f"[merge] base: armature={armature.name} bones={len(armature.pose.bones)} "
          f"meshes={len(meshes)}")
    return armature, meshes


def get_rest_local_to_parent(bone):
    """Bone's rest matrix in PARENT-LOCAL space — what the keyframes
    are layered on top of."""
    if bone.parent is None:
        return bone.matrix_local
    return bone.parent.matrix_local.inverted() @ bone.matrix_local


def iter_action_fcurves(action):
    """Yield every FCurve in an Action regardless of legacy / Blender 5.x
    layered API. Blender 5 moved FCurves to action.layers[].strips[]
    .channelbags[].fcurves; older versions had them on action.fcurves."""
    if hasattr(action, "fcurves"):
        yield from action.fcurves
        return
    for layer in action.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                yield from cb.fcurves


def retarget_action_bind_pose(action, base_armature, anim_armature):
    """Bake a per-bone rest-pose delta into `action` so it plays
    correctly on base_armature even if anim_armature has a different
    rest pose.

    Math: for a given bone, we want the final pose-bone matrix to
    match what the action would produce on anim_armature. That is:
        base_rest_local @ new_pose_rot == anim_rest_local @ old_pose_rot
    so:
        new_pose_rot = (base_rest_local^-1 @ anim_rest_local) @ old_pose_rot
    = delta @ old_pose_rot, applied as quaternion prefix to each keyframe.

    Handles both rotation_quaternion and rotation_euler FCurves.
    Translation/scale are left alone (rest-pose deltas there are
    rare for humanoid Mixamo rigs)."""
    fcurves_by_bone: dict[str, list] = {}
    for fc in iter_action_fcurves(action):
        if 'pose.bones["' not in fc.data_path:
            continue
        bone_name = fc.data_path.split('"')[1]
        fcurves_by_bone.setdefault(bone_name, []).append(fc)

    retarget_count = 0
    for bone_name, fcurves in fcurves_by_bone.items():
        base_bone = base_armature.data.bones.get(bone_name)
        anim_bone = anim_armature.data.bones.get(bone_name)
        if base_bone is None or anim_bone is None:
            continue

        base_rest = get_rest_local_to_parent(base_bone)
        anim_rest = get_rest_local_to_parent(anim_bone)
        delta = base_rest.inverted() @ anim_rest
        delta_quat = delta.to_quaternion()

        # Skip bones whose rest poses already match (avoid floating-point churn).
        if abs(delta_quat.angle) < 0.001:
            continue
        retarget_count += 1

        by_path: dict[str, list] = {}
        for fc in fcurves:
            by_path.setdefault(fc.data_path, []).append(fc)

        for data_path, fcs in by_path.items():
            if data_path.endswith("rotation_quaternion") and len(fcs) == 4:
                fcs.sort(key=lambda fc: fc.array_index)
                n_kf = len(fcs[0].keyframe_points)
                for k_idx in range(n_kf):
                    w = fcs[0].keyframe_points[k_idx].co.y
                    x = fcs[1].keyframe_points[k_idx].co.y
                    y = fcs[2].keyframe_points[k_idx].co.y
                    z = fcs[3].keyframe_points[k_idx].co.y
                    old_q = mathutils.Quaternion((w, x, y, z))
                    new_q = delta_quat @ old_q
                    fcs[0].keyframe_points[k_idx].co.y = new_q.w
                    fcs[1].keyframe_points[k_idx].co.y = new_q.x
                    fcs[2].keyframe_points[k_idx].co.y = new_q.y
                    fcs[3].keyframe_points[k_idx].co.y = new_q.z
            elif data_path.endswith("rotation_euler") and len(fcs) == 3:
                fcs.sort(key=lambda fc: fc.array_index)
                n_kf = len(fcs[0].keyframe_points)
                for k_idx in range(n_kf):
                    rx = fcs[0].keyframe_points[k_idx].co.y
                    ry = fcs[1].keyframe_points[k_idx].co.y
                    rz = fcs[2].keyframe_points[k_idx].co.y
                    old_e = mathutils.Euler((rx, ry, rz), "XYZ")
                    new_q = delta_quat @ old_e.to_quaternion()
                    new_e = new_q.to_euler("XYZ")
                    fcs[0].keyframe_points[k_idx].co.y = new_e.x
                    fcs[1].keyframe_points[k_idx].co.y = new_e.y
                    fcs[2].keyframe_points[k_idx].co.y = new_e.z

    return retarget_count


def import_anim_only(fbx_path: Path, slug: str, base_armature):
    """Import an anim-only Mixamo FBX, snag its action, retarget the
    keyframes to base_armature's rest pose, then delete the auxiliary
    armature the importer brought in."""
    existing_action_names = {a.name for a in bpy.data.actions}
    existing_object_names = {o.name for o in bpy.data.objects}

    bpy.ops.import_scene.fbx(filepath=str(fbx_path))

    new_actions = [a for a in bpy.data.actions if a.name not in existing_action_names]
    if not new_actions:
        raise RuntimeError(f"No new action from {fbx_path.name}")
    if len(new_actions) > 1:
        print(f"[merge] WARN: {len(new_actions)} new actions from {fbx_path.name}, "
              f"using first ({new_actions[0].name})")

    action = new_actions[0]
    action.name = slug
    action.use_fake_user = True  # survive cleanup of aux armature

    new_objects = [o for o in bpy.data.objects if o.name not in existing_object_names]
    aux_armatures = [o for o in new_objects if o.type == "ARMATURE"]

    if aux_armatures:
        n_retarget = retarget_action_bind_pose(action, base_armature, aux_armatures[0])
        if n_retarget:
            print(f"[merge]   retargeted {n_retarget} bones to base rest pose")

    for obj in new_objects:
        bpy.data.objects.remove(obj, do_unlink=True)

    fr = action.frame_range
    print(f"[merge] imported {fbx_path.name} → action {slug!r} "
          f"frames {int(fr[0])}..{int(fr[1])}")
    return action


def push_to_nla(armature, action, track_name: str) -> None:
    """Push an action onto a dedicated muted NLA track. glTF export
    walks NLA tracks to emit animation clips."""
    if armature.animation_data is None:
        armature.animation_data_create()
    track = armature.animation_data.nla_tracks.new()
    track.name = track_name
    track.mute = True
    start = int(action.frame_range[0])
    track.strips.new(track_name, start, action)


def export_glb(out_path: Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(out_path),
        export_format="GLB",
        use_selection=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_nla_strips=True,
    )
    print(f"[merge] wrote {out_path} ({out_path.stat().st_size / 1024:.1f} KB)")


def main() -> None:
    if not BASE_FBX.exists():
        print(f"[merge] ERROR: missing base character {BASE_FBX}")
        sys.exit(1)
    for fbx_name, _ in ANIMATIONS:
        p = ANIM_DIR / fbx_name
        if not p.exists():
            print(f"[merge] ERROR: missing anim {p}")
            sys.exit(1)

    bpy.ops.wm.read_factory_settings(use_empty=True)

    armature, _ = import_base_character(BASE_FBX)

    # Detach the base armature's currently-active action and rename it,
    # then bind it to its own NLA strip so it's exported alongside the
    # others (active action + NLA both export under ACTIONS mode).
    if armature.animation_data and armature.animation_data.action:
        base_action = armature.animation_data.action
        base_action.name = BASE_ACTION_SLUG
        base_action.use_fake_user = True
        armature.animation_data.action = None
        push_to_nla(armature, base_action, BASE_ACTION_SLUG)
        fr = base_action.frame_range
        print(f"[merge] base action → {BASE_ACTION_SLUG!r} "
              f"frames {int(fr[0])}..{int(fr[1])}")

    for fbx_name, slug in ANIMATIONS:
        action = import_anim_only(ANIM_DIR / fbx_name, slug, armature)
        push_to_nla(armature, action, slug)

    print(f"[merge] final actions: {[a.name for a in bpy.data.actions]}")
    print(f"[merge] final nla tracks: {[t.name for t in armature.animation_data.nla_tracks]}")

    export_glb(OUTPUT_GLB)


if __name__ == "__main__":
    main()
