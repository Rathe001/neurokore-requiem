"""
Generate .fbx.import files for every Meshy-extracted character mesh under
game/assets/characters/player_*_*/ and game/assets/characters/crimson_vein_titan/.

Each import file mirrors the working player_male/player_male_idle.fbx.import
template: scene importer, x_bot_bonemap retarget assigned to the Skeleton3D so
the X Bot animation library can play any clip on the new character.

`uid` and `path` (cache hash) are left as placeholders — Godot rewrites them
on first reimport.

Run:
    python3 tools/scaffold_character_imports.py
"""

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHARS = ROOT / "game" / "assets" / "characters"

TEMPLATE = '''[remap]

importer="scene"
importer_version=1
type="PackedScene"

[deps]

source_file="res://assets/characters/{rel_dir}/{filename}"

[params]

nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=true
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path="res://scripts/tools/meshy_character_import.gd"
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={{
"nodes": {{
"PATH:Skeleton3D": {{
"retarget/bone_map": Resource("res://assets/characters/x_bot/x_bot_bonemap.tres")
}}
}}
}}
fbx/importer=0
fbx/allow_geometry_helper_nodes=false
fbx/embedded_image_handling=1
fbx/naming_version=2
'''


def main() -> int:
    if not CHARS.is_dir():
        print(f"missing characters dir: {CHARS}", file=sys.stderr)
        return 1
    count = 0
    for entry in sorted(CHARS.iterdir()):
        if not entry.is_dir():
            continue
        # Skip directories whose .fbx.import files are already authored or
        # whose mesh is non-Meshy (X Bot stays on its own bonemap setup).
        if entry.name in {"x_bot"}:
            continue
        # Skip the v1 crimson_vein_titan — its .fbx.import was hand-tuned
        # for the rigged Mixamo export and shouldn't be overwritten.
        if entry.name == "crimson_vein_titan":
            continue
        for fbx in sorted(entry.glob("*.fbx")):
            import_path = fbx.with_suffix(".fbx.import")
            rel_dir = entry.name
            filename = fbx.name
            import_path.write_text(TEMPLATE.format(rel_dir=rel_dir, filename=filename))
            print(f"wrote {import_path.relative_to(ROOT)}")
            count += 1
    print(f"\n✓ {count} .fbx.import files written.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
