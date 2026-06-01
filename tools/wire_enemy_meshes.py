"""
Repoint every enemy class .tres at the new shared crimson_vein_titan mesh,
adding the char_mesh ext_resource + character_mesh + mesh_yaw_offset + a
per-class mesh_tint Color so variants read as distinct archetypes via
color alone. Idempotent — safe to re-run.

Tint assignments are intentionally restrained: only flavored archetypes
(healers, snipers, sledgehammer, RPG, buffer) get a color. Generic
weapon variants stay untinted (Color(1,1,1,1)) so the unmodified mesh
reads as "default enemy."

Run:
    python3 tools/wire_enemy_meshes.py
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRES_DIR = ROOT / "game" / "resources" / "enemies" / "classes"

# Per-archetype mesh assignment. Melee classes use the chunkier
# Molten_Sentinel silhouette; ranged classes use Crimson_Vein_Titan's
# leaner outline. Read at runtime via EnemyClass.character_mesh.
TITAN_PATH    = "res://assets/characters/crimson_vein_titan/crimson_vein_titan.fbx"
SENTINEL_PATH = "res://assets/characters/molten_sentinel/molten_sentinel.fbx"

# class_id prefix that triggers sentinel mesh. Anything in the table
# below overrides this. Default → titan (ranged + utility archetypes).
SENTINEL_PREFIX = "melee_"
SENTINEL_OVERRIDES = {"basic_melee"}

# class_id → Color(r, g, b, a). Missing entries default to white (no tint).
TINTS = {
    "melee_healer":       (0.55, 1.0,  0.55, 1.0),
    "melee_sledgehammer": (1.0,  0.55, 0.2,  1.0),
    "ranged_buffer":      (0.5,  0.75, 1.0,  1.0),
    "ranged_healer":      (0.55, 1.0,  0.55, 1.0),
    "ranged_lmg":         (1.0,  0.9,  0.3,  1.0),
    "ranged_rpg":         (1.0,  0.3,  0.2,  1.0),
    "ranged_sniper":      (0.75, 0.45, 0.95, 1.0),
}


def patch_tres(path: Path) -> None:
    text = path.read_text()
    cls_id_match = re.search(r'^id\s*=\s*&"([^"]+)"', text, re.MULTILINE)
    if not cls_id_match:
        print(f"  SKIP (no id): {path.name}")
        return
    class_id = cls_id_match.group(1)
    tint = TINTS.get(class_id, (1.0, 1.0, 1.0, 1.0))
    use_sentinel = (
        class_id.startswith(SENTINEL_PREFIX) or class_id in SENTINEL_OVERRIDES
    )
    mesh_path = SENTINEL_PATH if use_sentinel else TITAN_PATH

    # ── 1) Ensure char_mesh ext_resource entry exists + points at the new path.
    if 'id="char_mesh"' in text:
        text = re.sub(
            r'(\[ext_resource\s+type="PackedScene"\s+path=")[^"]+("\s+id="char_mesh"\])',
            rf'\g<1>{mesh_path}\g<2>',
            text,
        )
    else:
        # Insert a new ext_resource line at the end of the [ext_resource] block
        # (right before the empty line that precedes the next [section]).
        insertion = (
            f'[ext_resource type="PackedScene" '
            f'path="{mesh_path}" id="char_mesh"]\n'
        )
        # Find the last [ext_resource ...] line; append after it.
        ext_blocks = list(re.finditer(r'^\[ext_resource[^\]]*\]\n', text, re.MULTILINE))
        if ext_blocks:
            end = ext_blocks[-1].end()
            text = text[:end] + insertion + text[end:]
        # load_steps in the header rises by 1.
        text = re.sub(
            r'(\[gd_resource[^\]]*load_steps=)(\d+)',
            lambda m: f'{m.group(1)}{int(m.group(2)) + 1}',
            text,
            count=1,
        )

    # ── 2) Ensure character_mesh = ExtResource("char_mesh") is present.
    if 'character_mesh = ExtResource("char_mesh")' not in text:
        # Insert right after the weapon_id line (a stable anchor every class has).
        text = re.sub(
            r'(weapon_id\s*=\s*&"[^"]+"\n)',
            r'\1character_mesh = ExtResource("char_mesh")\n'
            r'mesh_yaw_offset = 3.14159\n',
            text,
            count=1,
        )

    # ── 3) Ensure mesh_tint = Color(...) is present + correct.
    color_line = f'mesh_tint = Color({tint[0]}, {tint[1]}, {tint[2]}, {tint[3]})'
    if re.search(r'^mesh_tint\s*=\s*Color\(', text, re.MULTILINE):
        text = re.sub(r'^mesh_tint\s*=\s*Color\([^)]*\)', color_line, text, flags=re.MULTILINE)
    else:
        text = re.sub(
            r'(mesh_yaw_offset\s*=\s*[0-9.]+\n)',
            rf'\g<1>{color_line}\n',
            text,
            count=1,
        )

    mesh_label = "sentinel" if use_sentinel else "titan"
    path.write_text(text)
    print(f"  ✓ {path.name}  →  {class_id}  mesh={mesh_label}  tint={tint}")


def main() -> int:
    if not TRES_DIR.is_dir():
        print(f"missing: {TRES_DIR}", file=sys.stderr)
        return 1
    for tres in sorted(TRES_DIR.glob("*.tres")):
        patch_tres(tres)
    print("\n✓ All enemy class .tres files patched.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
