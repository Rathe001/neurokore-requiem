#!/usr/bin/env python3
"""Import a Blenderkit-downloaded material as a Godot StandardMaterial3D.tres.

Workflow:
  1. In Blender's UI, switch Blenderkit's asset-type filter to "Material"
     and download the material you want. Blenderkit caches it under
     `~/blenderkit_data/materials/<slug>_<id>/`.
  2. Run this script with the asset_base_id. It opens the cached .blend
     in headless Blender, unpacks every Image Texture node, copies the
     unpacked PNGs into `game/assets/textures/<target_name>/`, and
     generates a Godot StandardMaterial3D.tres at
     `game/resources/materials/<target_name>.tres` with the textures
     wired into the right slots (albedo / normal / roughness / metallic /
     AO / emission) based on filename role detection.

Usage (from project root):
    python tools/import_blenderkit_material.py <asset_base_id> <target_name>
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEX_OUT = ROOT / "game" / "assets" / "textures"
MAT_OUT = ROOT / "game" / "resources" / "materials"
BKIT_CACHE = Path.home() / "blenderkit_data" / "materials"

DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"

UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")

# Filename → role detection. Case-insensitive substring match in order;
# first hit wins. Roles map to StandardMaterial3D fields in Godot.
# Role detection. The keys are role IDs we map to StandardMaterial3D slots;
# the values are token keywords. Filenames are split on _ and -, and we
# match keywords against tokens (right-most first) so the ROLE suffix wins
# over substring noise from the asset name. Without this, an asset named
# "Sci-Fi_Metal_Panels_BaseColor.png" routes to metallic because "metal"
# appears in the asset name — we want it to route to albedo via the
# "basecolor" suffix token.
ROLE_KEYWORDS = {
    "normal": ["normal", "normals", "nrm", "norm", "nor"],
    "roughness": ["roughness", "rough", "rgh"],
    "metallic": ["metallic", "metal", "mtl"],
    "ao": ["ambientocclusion", "ao", "occl", "occlusion"],
    "height": ["height", "displacement", "disp", "hgt", "bump"],
    "emission": ["emissive", "emission", "emit"],
    "albedo": ["basecolor", "diffuse", "albedo", "color"],
}


def fail(msg: str) -> "NoReturn":
    print(f"[import_material] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def normalize_id(raw: str) -> str:
    m = UUID_RE.search(raw)
    if not m:
        fail(f"could not find a UUID in '{raw}'")
    return m.group(0)


def fetch_metadata(asset_base_id: str) -> dict:
    url = (
        f"https://www.blenderkit.com/api/v1/search/"
        f"?query=asset_base_id:{asset_base_id}+asset_type:material"
    )
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            data = json.load(resp)
    except Exception as exc:
        fail(f"Blenderkit metadata lookup failed: {exc}")
    results = data.get("results", [])
    if not results:
        fail(f"no Blenderkit MATERIAL found with asset_base_id={asset_base_id}")
    return results[0]


def locate_blend(meta: dict) -> Path:
    if not BKIT_CACHE.exists():
        fail(f"Blenderkit cache not found at {BKIT_CACHE} — download the material "
             "in Blender's Blenderkit panel first")
    version_id = meta.get("id")
    if not version_id:
        fail("Blenderkit metadata had no 'id' field")
    candidates = list(BKIT_CACHE.glob(f"*_{version_id}"))
    if not candidates:
        fail(f"no cached folder ending in '_{version_id}' under {BKIT_CACHE}.\n"
             f"  Open Blender, switch Blenderkit to MATERIAL, search "
             f"'{meta.get('name', '?')}', click Download, then re-run.")
    folder = candidates[0]
    blends = list(folder.glob("*.blend"))
    if not blends:
        fail(f"folder {folder} contains no .blend file")
    return max(blends, key=lambda p: p.stat().st_size)


def extract_textures(blend_path: Path, out_dir: Path) -> list[Path]:
    """Drive headless Blender to unpack every image in the material's .blend
    to PNG files under out_dir. Returns the list of written paths."""
    out_dir.mkdir(parents=True, exist_ok=True)
    blender = os.environ.get("BLENDER", DEFAULT_BLENDER)
    if not Path(blender).exists():
        fail(f"Blender not found at {blender} — set $BLENDER to override")
    # Save every image with non-zero size as PNG into out_dir, named after
    # the image datablock (Blenderkit's images carry meaningful names like
    # "sci_fi_vent3_BaseColor"). Pack first so we have data even if the
    # .blend references missing on-disk files.
    out_dir_posix = str(out_dir).replace("\\", "/")
    script = (
        "import bpy, os\n"
        f"bpy.ops.wm.open_mainfile(filepath=r'{blend_path}')\n"
        "try:\n"
        "    bpy.ops.file.unpack_all(method='WRITE_LOCAL')\n"
        "except Exception:\n"
        "    pass\n"
        f"_out = r'{out_dir_posix}'\n"
        "for img in list(bpy.data.images):\n"
        "    if img.size[0] == 0 or img.size[1] == 0:\n"
        "        continue\n"
        "    name = img.name\n"
        "    if '.' in name:\n"
        "        stem, ext = os.path.splitext(name)\n"
        "        if ext.lstrip('.').isdigit():\n"
        "            name = stem\n"
        "    name = ''.join(c if (c.isalnum() or c in '_-.') else '_' for c in name)\n"
        "    if not name.lower().endswith('.png'):\n"
        "        name = name.rsplit('.', 1)[0] + '.png'\n"
        "    out_path = os.path.join(_out, name)\n"
        "    img.filepath_raw = out_path\n"
        "    img.file_format = 'PNG'\n"
        "    try:\n"
        "        img.save()\n"
        "        print('[saved] ' + out_path)\n"
        "    except Exception as e:\n"
        "        print('[skip] ' + name + ': ' + str(e))\n"
    )
    proc = subprocess.run(
        [blender, "--background", "--python-expr", script],
        check=False, capture_output=True, text=True,
    )
    print(proc.stdout)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        fail(f"Blender texture extraction failed for {blend_path}")
    return sorted(out_dir.glob("*.png"))


def detect_role(filename: str) -> str | None:
    """Map filename to a role keyword by tokenizing and matching from the
    last underscore-token backwards. Token-based avoids the asset-name-
    substring trap (e.g. "Sci-Fi_Metal_Panels_BaseColor.png" routes to
    albedo via "basecolor", not metallic via "metal")."""
    stem = filename.rsplit(".", 1)[0].lower()
    # Tokenize on _, -, and digits (so "AO_01" → ["ao", "01"] → ["ao"]).
    raw = stem.replace("-", "_").split("_")
    tokens = [t.rstrip("0123456789") for t in raw if t.rstrip("0123456789")]
    # Walk right-to-left so the trailing role-suffix wins over upstream noise.
    for token in reversed(tokens):
        for role, keywords in ROLE_KEYWORDS.items():
            if token in keywords:
                return role
    return None


def write_material_tres(target_name: str, role_map: dict[str, Path]) -> Path:
    """Generate a StandardMaterial3D.tres referencing the per-role textures."""
    MAT_OUT.mkdir(parents=True, exist_ok=True)
    out_path = MAT_OUT / f"{target_name}.tres"
    # Build a minimal .tres. ext_resource ids are assigned in order they're
    # added below; sub_resource holds the material.
    ext_resources: list[tuple[str, str]] = []  # (id, res_path)
    res_id = 1

    def add_ext(path: Path) -> str:
        nonlocal res_id
        # Godot's project root is `game/` (where project.godot lives), so
        # res:// resolves to game/ — strip that prefix when forming res:// URIs.
        rel = path.relative_to(ROOT).as_posix()
        if rel.startswith("game/"):
            rel = rel[len("game/"):]
        rid = f"tex_{res_id}"
        ext_resources.append((rid, f"res://{rel}"))
        res_id += 1
        return rid

    # Map roles → tres property names + extra flags
    role_to_props: list[tuple[str, str]] = []  # (property, ext_id)
    if "albedo" in role_map:
        role_to_props.append(("albedo_texture", add_ext(role_map["albedo"])))
    if "normal" in role_map:
        nid = add_ext(role_map["normal"])
        role_to_props.append(("normal_enabled", "true"))
        # 2.0 is stronger than Godot's default 1.0 — at iso camera distance
        # the default produces a near-flat read because the lighting angle
        # barely interacts with subtle bump detail. 2.0 makes the surface
        # texture actually visible without looking cartoonish.
        role_to_props.append(("normal_scale", "2.0"))
        role_to_props.append(("normal_texture", nid))
    if "roughness" in role_map:
        role_to_props.append(("roughness_texture", add_ext(role_map["roughness"])))
    if "metallic" in role_map:
        role_to_props.append(("metallic_texture", add_ext(role_map["metallic"])))
        # 0.35 — full metallic (1.0) plus a sub-pixel detail texture flickers
        # hard under our overhead lights at iso. 0.35 keeps surfaces reading
        # as metal without the harsh micro-specular shimmer. Tune up if a
        # specific material needs full metallic punch.
        role_to_props.append(("metallic", "0.35"))
    if "ao" in role_map:
        role_to_props.append(("ao_enabled", "true"))
        role_to_props.append(("ao_texture", add_ext(role_map["ao"])))
    if "emission" in role_map:
        role_to_props.append(("emission_enabled", "true"))
        role_to_props.append(("emission_texture", add_ext(role_map["emission"])))
    if "height" in role_map:
        role_to_props.append(("heightmap_enabled", "true"))
        role_to_props.append(("heightmap_texture", add_ext(role_map["height"])))

    load_steps = len(ext_resources) + 2  # +1 sub_resource, +1 base
    lines = [f"[gd_resource type=\"StandardMaterial3D\" load_steps={load_steps} format=3]\n", ""]
    for rid, path in ext_resources:
        lines.append(f"[ext_resource type=\"Texture2D\" path=\"{path}\" id=\"{rid}\"]")
    lines.append("")
    lines.append("[resource]")
    # NOTE: don't add # or ; comments inside the [resource] block — Godot's
    # .tres parser is finicky and it caused level-build failures last time.
    # texture_filter = 5 is FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC, which
    # kills the iso-camera specular shimmer that bilinear+mipmap can't fix.
    lines.append("texture_filter = 5")
    for prop, val in role_to_props:
        if val in ("true", "false") or "." in str(val):
            lines.append(f"{prop} = {val}")
        else:
            lines.append(f"{prop} = ExtResource(\"{val}\")")
    # Triplanar mapping by default. The room walls in this project are
    # built via SurfaceTool with explicit normals but NO UVs (the prior
    # procedural shader sampled by world position, didn't need them),
    # and the floor is a PlaneMesh whose default 0-1 UVs stretch one
    # texture tile across the whole room. Triplanar sidesteps both —
    # samples from world position weighted by face normal, tiles
    # consistently at uv1_scale per meter regardless of mesh.
    lines.append("uv1_triplanar = true")
    # 0.2 = 5m tile, tuned for our iso camera distance. At 0.5 (2m tile) the
    # texture detail was sub-pixel from iso and read as flat noise; 5m tiles
    # keep the panel/grate pattern readable from above. FPS view trades off
    # — close-up tiles feel large — but iso is the primary camera so that's
    # the right side of the tradeoff.
    lines.append("uv1_scale = Vector3(0.2, 0.2, 0.2)")
    out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    # If a height map was extracted, also produce a sibling
    # <target>_displaced.tres that wraps displacement_floor.gdshader with
    # all five textures + tuned defaults. The theme can use it as a
    # floor_material_override when real geometric displacement is wanted
    # (paired with subdivided PlaneMesh floors — see floor_builder.gd).
    if "height" in role_map and "albedo" in role_map and "normal" in role_map \
            and "roughness" in role_map and "metallic" in role_map:
        _write_displaced_variant(target_name, role_map, out_path.parent)
    return out_path


def _write_displaced_variant(target_name: str, role_map: dict[str, Path], mat_dir: Path) -> Path:
    """Sibling ShaderMaterial.tres that uses displacement_floor.gdshader.
    Generated alongside the StandardMaterial3D when a height map is present."""
    out_path = mat_dir / f"{target_name}_displaced.tres"

    def rel_res(path: Path) -> str:
        r = path.relative_to(ROOT).as_posix()
        if r.startswith("game/"):
            r = r[len("game/"):]
        return f"res://{r}"

    paths = {
        "albedo": rel_res(role_map["albedo"]),
        "normal": rel_res(role_map["normal"]),
        "roughness": rel_res(role_map["roughness"]),
        "metallic": rel_res(role_map["metallic"]),
        "height": rel_res(role_map["height"]),
    }
    shader_path = "res://scripts/prototype/displacement_floor.gdshader"
    lines = [
        '[gd_resource type="ShaderMaterial" load_steps=7 format=3]',
        "",
        f'[ext_resource type="Shader" path="{shader_path}" id="shader"]',
        f'[ext_resource type="Texture2D" path="{paths["albedo"]}" id="tex_albedo"]',
        f'[ext_resource type="Texture2D" path="{paths["normal"]}" id="tex_normal"]',
        f'[ext_resource type="Texture2D" path="{paths["roughness"]}" id="tex_roughness"]',
        f'[ext_resource type="Texture2D" path="{paths["metallic"]}" id="tex_metallic"]',
        f'[ext_resource type="Texture2D" path="{paths["height"]}" id="tex_height"]',
        "",
        "[resource]",
        'shader = ExtResource("shader")',
        "shader_parameter/uv_scale = 0.2",
        "shader_parameter/normal_strength = 3.0",
        "shader_parameter/displacement_strength = 0.3",
        "shader_parameter/displacement_bias = 0.5",
        "shader_parameter/metallic_factor = 0.35",
        "shader_parameter/roughness_floor = 0.4",
        'shader_parameter/albedo_texture = ExtResource("tex_albedo")',
        'shader_parameter/normal_texture = ExtResource("tex_normal")',
        'shader_parameter/roughness_texture = ExtResource("tex_roughness")',
        'shader_parameter/metallic_texture = ExtResource("tex_metallic")',
        'shader_parameter/height_texture = ExtResource("tex_height")',
        "",
    ]
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"[import_material] also wrote {out_path.relative_to(ROOT)} (displacement variant)")
    return out_path


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("asset_id")
    p.add_argument("target_name", help="Slug for output folder + .tres filename")
    p.add_argument("--license", default="Blenderkit — listed Free")
    args = p.parse_args()

    abi = normalize_id(args.asset_id)
    print(f"[import_material] asset_base_id: {abi}")
    meta = fetch_metadata(abi)
    print(f"[import_material] asset: {meta.get('name', '?')} (free: {meta.get('isFree')})")
    blend = locate_blend(meta)
    print(f"[import_material] cached source: {blend}")

    tex_dir = TEX_OUT / args.target_name
    files = extract_textures(blend, tex_dir)
    print(f"[import_material] extracted {len(files)} texture(s) to {tex_dir.relative_to(ROOT)}")

    role_map: dict[str, Path] = {}
    for f in files:
        role = detect_role(f.name)
        if role and role not in role_map:
            role_map[role] = f
        print(f"  {f.name} -> {role or '(unmapped)'}")

    if not role_map:
        fail("no recognizable textures found — can't generate material")

    tres = write_material_tres(args.target_name, role_map)
    print(f"[import_material] wrote {tres.relative_to(ROOT)}")
    print(f"[import_material] done. Material roles: {sorted(role_map.keys())}")


if __name__ == "__main__":
    main()
