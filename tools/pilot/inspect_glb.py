"""Quick inspector — lists meshes, armatures, animations in a .glb or .fbx.

Run via Blender:
  blender -b -P tools/pilot/inspect_glb.py -- <path1> [<path2> ...]
"""
import sys
from pathlib import Path

import bpy


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_file(path: Path) -> None:
    ext = path.suffix.lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=str(path))
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=str(path))
    else:
        raise RuntimeError(f"unsupported extension: {ext}")


def inspect(path: Path) -> None:
    reset_scene()
    print(f"\n=== {path.name} ===")
    import_file(path)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    armatures = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    actions = list(bpy.data.actions)

    print(f"  meshes:    {len(meshes)}")
    for m in meshes:
        print(f"    - {m.name} (verts={len(m.data.vertices)}, mats={[s.material.name if s.material else 'None' for s in m.material_slots]})")

    print(f"  armatures: {len(armatures)}")
    for a in armatures:
        bones = a.data.bones
        print(f"    - {a.name} (bones={len(bones)})")
        print(f"      sample bones: {[b.name for b in list(bones)[:10]]}")

    print(f"  actions:   {len(actions)}")
    for act in actions:
        fr = act.frame_range
        print(f"    - {act.name!r}  frames {int(fr[0])}..{int(fr[1])}  ({int(fr[1] - fr[0])} frames)")


def main():
    argv = sys.argv
    if "--" in argv:
        paths = [Path(p) for p in argv[argv.index("--") + 1:]]
    else:
        paths = []
    if not paths:
        print("usage: blender -b -P inspect_glb.py -- <file> [<file2> ...]")
        return
    for p in paths:
        inspect(p)


main()
