"""
Decimate every mesh in a .fbx / .glb file via Blender's Decimate modifier
(Collapse mode, which preserves armatures + UVs + vertex groups), then
re-export to the same path.

Run via:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/decimate_meshes.py

The TARGETS dict below maps repo-relative paths to decimation ratios.
Ratio 0.1 means "keep 10% of triangles." Ratio 1.0 (or absent from
TARGETS) means "leave as-is."

Targets were chosen from the audit at 2026-06-01:
  Total before: 1.17M tris across 31 files.
  Target after: ~70K tris (~95% reduction).
"""

import os
import sys
import bpy
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS = REPO_ROOT / "game" / "assets"


# (relative-path, decimation-ratio). Paths relative to game/assets.
# Ratio = fraction of triangles to keep. Smaller = more aggressive.
TARGETS = {
    # ── Static glb assets ────────────────────────────────────────────
    # Sniper is wildly over budget (640K → 5K).
    "models/weapons/sniper/sniper.glb":                       0.008,
    # Crater is a floor decal — shouldn't be 100K tris.
    "models/vfx/crater/crater.glb":                           0.05,
    # Loot crate, drone — way over for static props.
    "models/objects/loot_crate/loot_crate.glb":               0.07,
    "models/objects/automaton_drone/automaton_drone.glb":     0.11,
    "models/objects/floor_panel/floor_panel.glb":             0.05,
    "models/objects/floor_panel_v2/floor_panel_v2.glb":       0.09,
    # Mid-size weapons.
    "models/weapons/laser_pistol/laser_pistol.glb":           0.11,
    "models/weapons/plasma_rifle/plasma_rifle.glb":           0.15,
    # Smaller weapons — modest decimation.
    "models/weapons/lmg/lmg.glb":                             0.17,
    "models/weapons/smg/smg.glb":                             0.18,
    "models/weapons/arc_taser/arc_taser.glb":                 0.19,
    "models/weapons/hammer/hammer.glb":                       0.19,
    "models/weapons/grenade/grenade.glb":                     0.19,
    "models/weapons/energy_accelerator/energy_accelerator.glb": 0.19,
    "models/weapons/rpg/rpg.glb":                             0.30,
    # ── Character meshes (FBX with armature) ─────────────────────────
    # Keep more detail — joint articulation needs the verts. Target ~10K.
    "characters/military_man/Idle.fbx":                       0.22,
    "characters/alien/alien_idle.fbx":                        0.22,
    "characters/x_bot/X Bot.fbx":                             0.20,
    "characters/player_male/player_male_idle.fbx":            0.32,
    "characters/crypto/crypto_idle.fbx":                      0.35,
    "characters/player_female/player_female_idle.fbx":        0.37,
}


def decimate_object(obj, ratio):
    """Apply a Decimate (Collapse) modifier to a mesh object at the given ratio."""
    if obj.type != "MESH":
        return 0
    before = len(obj.data.polygons)
    mod = obj.modifiers.new(name="DecimateAuto", type="DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    # Use weights to keep face groups (vertex groups remain valid).
    mod.use_collapse_triangulate = True
    # Apply via depsgraph evaluation so the modifier is baked into mesh data.
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)
    after = len(obj.data.polygons)
    return before - after


def process_file(rel_path, ratio):
    src = ASSETS / rel_path
    if not src.exists():
        print(f"  MISSING: {src}")
        return
    print(f"\n══ {rel_path}  (ratio {ratio}) ══")
    # Fresh scene
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Import based on extension
    suffix = src.suffix.lower()
    if suffix == ".fbx":
        # Blender 5.x deprecates the old fbx importer; both .fbx_import.fbx and import_scene.fbx may exist
        if hasattr(bpy.ops.wm, "fbx_import"):
            bpy.ops.wm.fbx_import(filepath=str(src))
        else:
            bpy.ops.import_scene.fbx(filepath=str(src))
    elif suffix == ".glb" or suffix == ".gltf":
        bpy.ops.import_scene.gltf(filepath=str(src))
    else:
        print(f"  unsupported: {suffix}")
        return
    # Find every mesh and decimate
    total_before = 0
    total_removed = 0
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            total_before += len(obj.data.polygons)
            total_removed += decimate_object(obj, ratio)
    total_after = total_before - total_removed
    print(f"  {total_before} → {total_after} tris  ({total_removed} removed)")
    # Export back to same path
    if suffix == ".fbx":
        bpy.ops.export_scene.fbx(
            filepath=str(src),
            use_selection=False,
            embed_textures=True,
            path_mode="COPY",
            add_leaf_bones=False,
            armature_nodetype="NULL",
            bake_anim=True,
        )
    else:
        bpy.ops.export_scene.gltf(
            filepath=str(src),
            export_format="GLB",
            use_selection=False,
            export_apply=False,
            export_animations=True,
        )
    print(f"  exported {src}")


def main():
    print(f"REPO_ROOT = {REPO_ROOT}")
    print(f"ASSETS    = {ASSETS}")
    for rel_path, ratio in TARGETS.items():
        try:
            process_file(rel_path, ratio)
        except Exception as e:
            print(f"  ERROR on {rel_path}: {e}")
    print("\nAll done.")


if __name__ == "__main__":
    main()
