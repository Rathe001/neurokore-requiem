"""Convert a Meshy .glb (mesh + auto-rig + animations) into a clean FBX
of just the mesh in T-pose, ready for Mixamo's auto-rigger.

Mixamo accepts FBX/OBJ/ZIP — not GLB. It also can't map non-standard
skeletons (Meshy's 24-bone auto-rig isn't humanoid-mappable), so we
strip the armature entirely and let Mixamo lay down its own clean
~52-bone skeleton on the bare mesh.

Run:
    blender -b -P tools/pilot/glb_to_mixamo_fbx.py -- <input.glb> <output.fbx>

Example:
    blender -b -P tools/pilot/glb_to_mixamo_fbx.py -- \
        ~/Desktop/crimson_vein_titan/.../Character_output.glb \
        ~/Desktop/crimson_vein_titan_mesh_for_mixamo.fbx

After conversion:
    1. Upload the FBX to mixamo.com
    2. Place the 6 markers (chin, wrists, elbows, knees, groin) — drag
       each slightly OUTSIDE the silhouette where the joint should be
    3. Auto-rig — should succeed with humanoid skeleton
    4. Download the rigged FBX (T-pose)
    5. Browse Mixamo's Animations tab, download each desired anim
       as FBX (uncheck "In Place" only for the locomotion clips you
       want root motion on — we re-center per frame anyway)
"""
import sys
from pathlib import Path

import bpy  # type: ignore


def main():
    argv = sys.argv
    if "--" not in argv:
        print("usage: blender -b -P glb_to_mixamo_fbx.py -- <input.glb> <output.fbx>")
        sys.exit(1)
    args = argv[argv.index("--") + 1:]
    if len(args) < 2:
        print("need input.glb and output.fbx")
        sys.exit(1)
    src = Path(args[0]).expanduser().resolve()
    dst = Path(args[1]).expanduser().resolve()
    if not src.exists():
        print(f"missing: {src}")
        sys.exit(1)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(src))

    # Find and delete the armature (and unparent its mesh children).
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    for arm in armatures:
        for child in list(arm.children):
            mw = child.matrix_world.copy()
            child.parent = None
            child.matrix_world = mw
        bpy.data.objects.remove(arm, do_unlink=True)

    # Strip Armature modifiers from any remaining meshes so the FBX
    # exports without bone weights (which would confuse Mixamo).
    for obj in bpy.data.objects:
        if obj.type != "MESH":
            continue
        for mod in [m for m in obj.modifiers if m.type == "ARMATURE"]:
            obj.modifiers.remove(mod)
        # Clear vertex groups too (these encoded the old skin weights).
        for vg in list(obj.vertex_groups):
            obj.vertex_groups.remove(vg)

    # Filter out tiny stray meshes (Meshy sometimes exports an empty
    # Icosphere helper with no material — Mixamo doesn't need it).
    for obj in list(bpy.data.objects):
        if obj.type == "MESH" and len(obj.data.vertices) < 200:
            print(f"  removing tiny mesh {obj.name} (verts={len(obj.data.vertices)})")
            bpy.data.objects.remove(obj, do_unlink=True)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if not meshes:
        print("ERROR: no meshes left after stripping")
        sys.exit(1)
    print(f"  exporting {len(meshes)} mesh(es): {[m.name for m in meshes]}")

    # Select all meshes for selected-only export.
    bpy.ops.object.select_all(action="DESELECT")
    for m in meshes:
        m.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]

    dst.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.fbx(
        filepath=str(dst),
        use_selection=True,
        # Mesh only — no armature, no animation, no leaf bones.
        object_types={"MESH"},
        # T-pose / current pose is fine; mesh is already in rest position.
        bake_anim=False,
        # Apply transforms so Mixamo sees the mesh at the same scale
        # and orientation that's visible in Blender.
        apply_unit_scale=True,
        apply_scale_options="FBX_SCALE_NONE",
        # Standard FBX axes that Mixamo expects.
        axis_forward="-Z",
        axis_up="Y",
        # Embed textures so Mixamo can display the character.
        path_mode="COPY",
        embed_textures=True,
    )
    print(f"  wrote {dst} ({dst.stat().st_size / 1024:.1f} KB)")


main()
