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

# ── Config ──────────────────────────────────────────────────────────────────

SOURCE_DIR = Path.home() / "Desktop" / "models" / "crimson vein titan"

# The "with skin" download — has mesh + textures + Mixamo armature.
# Whatever anim was selected when this was downloaded becomes the base
# character's first action; we rename it to BASE_ACTION_SLUG.
BASE_CHARACTER_FBX = "Crouching Idle.fbx"
BASE_ACTION_SLUG   = "idle"

# Each entry: (anim FBX filename in SOURCE_DIR, output action slug).
# The script render_sprite_sheet.py uses these slugs to look up actions.
ANIMATIONS = [
    ("Crouch Walk Forward.fbx",            "walk"),
    ("Standing 2H Magic Attack 01.fbx",    "cast"),
    ("Standing React Small From Left.fbx", "hit"),
    ("Zombie Death.fbx",                   "death"),
]

OUTPUT_GLB = Path.home() / "Desktop" / "crimson_vein_titan_mixamo.glb"


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


def import_anim_only(fbx_path: Path, slug: str, base_armature):
    """Import an anim-only Mixamo FBX, snag its action, rename it, then
    delete the auxiliary armature the importer brought in."""
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
    base_path = SOURCE_DIR / BASE_CHARACTER_FBX
    if not base_path.exists():
        print(f"[merge] ERROR: missing base character {base_path}")
        sys.exit(1)
    for fbx_name, _ in ANIMATIONS:
        p = SOURCE_DIR / fbx_name
        if not p.exists():
            print(f"[merge] ERROR: missing anim {p}")
            sys.exit(1)

    bpy.ops.wm.read_factory_settings(use_empty=True)

    armature, _ = import_base_character(base_path)

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
        action = import_anim_only(SOURCE_DIR / fbx_name, slug, armature)
        push_to_nla(armature, action, slug)

    print(f"[merge] final actions: {[a.name for a in bpy.data.actions]}")
    print(f"[merge] final nla tracks: {[t.name for t in armature.animation_data.nla_tracks]}")

    export_glb(OUTPUT_GLB)


if __name__ == "__main__":
    main()
