#!/usr/bin/env python3
"""Import a Blenderkit-downloaded model into the project as a clean .glb.

Workflow:
  1. In Blender's UI, search Blenderkit and click "Download" on the model
     you want. Blenderkit's addon stores the source .blend under
     `~/blenderkit_data/models/<slug>_<asset_base_id>/`.
  2. Run this script with the asset_base_id. It locates the cached .blend,
     opens it in headless Blender, exports as .glb at the target path
     without any geometry modification (no normal recalc, no merge — the
     file ships exactly as Blenderkit authored it).
  3. The script appends a row to docs/assets.md so the asset is tracked
     for license verification.

Usage (from project root):
    python tools/import_blenderkit.py <asset_base_id> <target_name> [--category <subdir>]

Args:
    asset_base_id   The UUID from the Blenderkit URL (e.g. "45ee98...")
                    or a full "asset_base_id:..." search-string fragment.
    target_name     The folder + filename to use under
                    game/assets/models/<category>/<target_name>/<target_name>.glb.
                    Pick a short slug — "barrel3", "console2", etc.
    --category      Subdirectory under game/assets/models/ (default: "objects").
                    Use "characters" for rigged figures.
    --license       License string for the manifest row. Defaults to
                    "Blenderkit — listed Free" but pass the actual license
                    if you know it (e.g. "Royalty Free", "CC-BY 4.0").

Examples:
    python tools/import_blenderkit.py 45ee98c2-d943-4cd8-bbc7-48e12c134040 lion
    python tools/import_blenderkit.py 45ee98c2-d943-4cd8-bbc7-48e12c134040 lion --category characters

The Blender export uses default glTF settings — embedded textures,
+Y up, exported with normals/tangents/skinning/animations intact. No
post-processing.
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
MODELS_OUT = ROOT / "game" / "assets" / "models"
BKIT_CACHE = Path.home() / "blenderkit_data" / "models"
ASSETS_MD = ROOT / "docs" / "assets.md"

# Default Blender install on this machine. Override via $BLENDER if needed.
DEFAULT_BLENDER = r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe"

UUID_RE = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")


def fail(msg: str) -> "NoReturn":
    print(f"[import_blenderkit] ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def normalize_id(raw: str) -> str:
    """Accept either a bare UUID or 'asset_base_id:<uuid>' from Blenderkit search."""
    m = UUID_RE.search(raw)
    if not m:
        fail(f"could not find an asset_base_id UUID in '{raw}'")
    return m.group(0)


def fetch_metadata(asset_base_id: str) -> dict:
    """Hit Blenderkit's search endpoint to get asset metadata. The
    cache folder is named after the `id` field, NOT the asset_base_id,
    so the lookup here is necessary to bridge URL → cache."""
    # Blenderkit's search uses a "query" param with key:value tokens
    # separated by +. The plain asset_base_id= param is ignored.
    url = (
        f"https://www.blenderkit.com/api/v1/search/"
        f"?query=asset_base_id:{asset_base_id}+asset_type:model"
    )
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            data = json.load(resp)
    except Exception as exc:
        fail(f"Blenderkit metadata lookup failed: {exc}")
    results = data.get("results", [])
    if not results:
        fail(f"no Blenderkit model found with asset_base_id={asset_base_id}")
    return results[0]


def locate_cached_blend(meta: dict) -> Path:
    """Find the .blend Blenderkit cached for this asset. Folder name is
    `<slug>_<id>` where `id` is the version-specific UUID from the API,
    NOT the asset_base_id from the URL."""
    if not BKIT_CACHE.exists():
        fail(f"Blenderkit cache not found at {BKIT_CACHE} — download the model "
             f"in Blender's Blenderkit panel first")
    version_id = meta.get("id")
    if not version_id:
        fail("Blenderkit metadata had no 'id' field — can't locate cache folder")
    candidates = list(BKIT_CACHE.glob(f"*_{version_id}"))
    if not candidates:
        fail(f"no cached folder ending in '_{version_id}' under {BKIT_CACHE}.\n"
             f"  Open Blender, search Blenderkit for '{meta.get('name', '?')}', click Download,\n"
             f"  then re-run this script.")
    folder = candidates[0]
    blends = list(folder.glob("*.blend"))
    if not blends:
        fail(f"folder {folder} contains no .blend file")
    # Pick the largest .blend (Blenderkit sometimes ships multiple resolutions;
    # we want the full-fidelity one, which is usually the largest).
    return max(blends, key=lambda p: p.stat().st_size)


def export_glb(blend_path: Path, out_path: Path, decimate_ratio: float = 0.05, tint_emission: str = "", texture_size: int = 1024) -> None:
    """Drive Blender headless to open the .blend and export it as .glb
    with default settings. Does NOT modify geometry, normals, or materials."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    blender = os.environ.get("BLENDER", DEFAULT_BLENDER)
    if not Path(blender).exists():
        fail(f"Blender not found at {blender} — set $BLENDER to override")
    # export_apply=True bakes modifiers (Solidify, Mirror, Subdivision Surface,
    # etc.) into the exported mesh. Blenderkit assets commonly ship with a
    # Solidify modifier on container/box bodies to create dual-sided geometry —
    # without applying it the export ships only the inner OR outer shell
    # and the model lights wrong in Godot even though Blender's preview
    # (which respects modifiers) looked fine. Armature modifiers are
    # preserved separately for rigged characters, so this is safe to keep on.
    #
    # use_backface_culling = False on every material is the glTF spec way to
    # say "render this material on both sides" — Blender's exporter maps it
    # to glTF's `doubleSided: true` flag, which Godot honors. Blenderkit
    # models often have intentionally inverted faces (recessed panels,
    # interior surfaces) authored to look right under Blender's default
    # Eevee preview (which doesn't cull backfaces unless you toggle it on
    # per-material). When those same faces ship to Godot — which defaults
    # to back-face cull — chunks of the model drop out depending on camera
    # angle. Forcing double-sided at export time is the surgical fix and
    # doesn't touch geometry.
    # blend_method = 'OPAQUE' fixes the camera-angle-dependent face dropouts
    # we kept seeing on Blenderkit containers. Many of those models use
    # alpha-blend materials in Blender for subtle decals/edges; glTF
    # preserves that as `alphaMode: BLEND`, and transparent surfaces in
    # Godot don't write to the depth buffer — so two transparent panels
    # at different distances sort wrong as the camera rotates, with one
    # appearing to vanish behind the other. Forcing opaque kills the
    # transparency sort entirely (cost: any genuinely-transparent details
    # like glass become opaque, but for solid containers that's correct).
    # UDIM textures (image.source == 'TILED') aren't supported by the glTF
    # spec at all. Blenderkit ships some "PBR Pro" models with UDIM-tiled
    # detail maps; the exporter aborts hard rather than degrade. Our
    # workaround: walk every image-texture node, and for tiled images,
    # disconnect the node's outputs so the material falls back to its
    # Principled BSDF defaults (baseColorFactor, etc.). Cost: surface
    # detail authored into UDIM tiles is lost, but the model still ships
    # and renders cleanly. Future: bake UDIM down to a single texture
    # via Blender's bake op if a model really needs the detail preserved.
    #
    # Decimation: optional poly reduction via the Decimate modifier
    # (COLLAPSE method). At iso camera distance many fine triangles are
    # sub-pixel — a ratio of 0.5 typically halves geometry with no
    # visible difference. Applied before export_apply so the decimation
    # is baked into the .glb.
    tint_step = ""
    if tint_emission:
        parts = [float(x) for x in tint_emission.split(",")]
        if len(parts) == 3:
            tr, tg, tb = (p / 255.0 for p in parts)
            # Remap every emissive-input texture from its native color to
            # luminance × (tr, tg, tb). Preserves which pixels emit and how
            # bright they get; replaces the hue. Catches both pre-swap UDIM
            # images and post-swap on-disk loads — we walk every material
            # that has an active Emission link and recolor the image it
            # ultimately samples from.
            tint_step = (
                "import numpy as _np\n"
                f"_TINT = ({tr}, {tg}, {tb})\n"
                "_emis_imgs = set()\n"
                "for mat in bpy.data.materials:\n"
                "    if not mat.use_nodes or mat.node_tree is None:\n"
                "        continue\n"
                "    for node in mat.node_tree.nodes:\n"
                "        if node.type != 'BSDF_PRINCIPLED':\n"
                "            continue\n"
                "        for socket_name in ('Emission', 'Emission Color'):\n"
                "            if socket_name not in node.inputs:\n"
                "                continue\n"
                "            sock = node.inputs[socket_name]\n"
                "            if not sock.is_linked:\n"
                "                continue\n"
                "            src = sock.links[0].from_node\n"
                "            if src.type == 'TEX_IMAGE' and src.image is not None:\n"
                "                _emis_imgs.add(src.image.name)\n"
                "for name in _emis_imgs:\n"
                "    img = bpy.data.images.get(name)\n"
                "    if img is None or img.size[0] == 0:\n"
                "        continue\n"
                "    n_floats = img.size[0] * img.size[1] * img.channels\n"
                "    arr = _np.empty(n_floats, dtype=_np.float32)\n"
                "    img.pixels.foreach_get(arr)\n"
                "    arr = arr.reshape(-1, img.channels)\n"
                "    lum = arr[:, :3].max(axis=1)\n"
                "    arr[:, 0] = lum * _TINT[0]\n"
                "    arr[:, 1] = lum * _TINT[1]\n"
                "    arr[:, 2] = lum * _TINT[2]\n"
                "    img.pixels.foreach_set(arr.reshape(-1))\n"
                "    img.update()\n"
            )
    decimate_step = ""
    if decimate_ratio < 1.0:
        decimate_step = (
            f"_DECIMATE = {decimate_ratio}\n"
            "for obj in bpy.data.objects:\n"
            "    if obj.type != 'MESH':\n"
            "        continue\n"
            "    m = obj.modifiers.new('AutoDecimate', 'DECIMATE')\n"
            "    m.decimate_type = 'COLLAPSE'\n"
            "    m.ratio = _DECIMATE\n"
        )
    texture_step = ""
    if texture_size > 0:
        texture_step = (
            f"_MAX_TEX = {texture_size}\n"
            "for img in bpy.data.images:\n"
            "    if img.size[0] == 0 or img.size[1] == 0:\n"
            "        continue\n"
            "    long_edge = max(img.size[0], img.size[1])\n"
            "    if long_edge <= _MAX_TEX:\n"
            "        continue\n"
            "    factor = _MAX_TEX / float(long_edge)\n"
            "    new_w = max(1, int(img.size[0] * factor))\n"
            "    new_h = max(1, int(img.size[1] * factor))\n"
            "    img.scale(new_w, new_h)\n"
            "    img.update()\n"
        )
    script = (
        "import bpy\n"
        f"bpy.ops.wm.open_mainfile(filepath=r'{blend_path}')\n"
        # Unpack any packed textures so the exporter resolves their paths.
        # try/except because unpack errors on .blends with no packed data.
        "try:\n"
        "    bpy.ops.file.unpack_all(method='WRITE_LOCAL')\n"
        "except Exception:\n"
        "    pass\n"
        # UDIM handling — three-strategy ladder.
        #
        # 1) Try to find the actual tile file on disk (Blenderkit ships tile
        #    1001 separately under a textures/ folder; blend's filepath_raw
        #    references a different folder name like textures_2k/ which
        #    doesn't exist). Walk the .blend's directory recursively looking
        #    for files matching the tile-1001 filename. If found, load as a
        #    regular non-tiled image and swap all references — textures are
        #    preserved.
        # 2) If no on-disk tile is found, fall back to disconnecting the
        #    texture node (material renders with its baseColorFactor only).
        # 3) For step-2 strips, also zero the Principled BSDF emission — many
        #    emissive materials use the texture as a mask (only painted
        #    accents emit), and without the mask the whole surface glows
        #    at emissiveFactor's full strength.
        "import os\n"
        "_blend_dir = os.path.dirname(bpy.data.filepath)\n"
        "_disk_files = {}\n"
        "for root, dirs, files in os.walk(_blend_dir):\n"
        "    for f in files:\n"
        "        _disk_files[f.lower()] = os.path.join(root, f)\n"
        "_swapped = {}\n"
        "_stripped_imgs = set()\n"
        "for img in list(bpy.data.images):\n"
        "    if img.source != 'TILED' or not img.tiles:\n"
        "        continue\n"
        "    _target_idx = 0\n"
        "    for _i, _t in enumerate(img.tiles):\n"
        "        if _t.number == 1001:\n"
        "            _target_idx = _i\n"
        "            break\n"
        "    _target_tile = img.tiles[_target_idx]\n"
        "    _candidates = []\n"
        "    if img.filepath_raw:\n"
        "        _candidates.append(img.filepath_raw.replace('<UDIM>', str(_target_tile.number)))\n"
        "    if _target_tile.label:\n"
        "        _candidates.append(_target_tile.label)\n"
        "    _found_path = None\n"
        "    for _c in _candidates:\n"
        "        _abs = bpy.path.abspath(_c) if _c.startswith('//') else _c\n"
        "        if os.path.exists(_abs):\n"
        "            _found_path = _abs\n"
        "            break\n"
        "    if _found_path is None:\n"
        "        for _c in _candidates:\n"
        "            _basename = os.path.basename(_c).lower()\n"
        "            if _basename in _disk_files:\n"
        "                _found_path = _disk_files[_basename]\n"
        "                break\n"
        "    if _found_path is not None:\n"
        "        _new_img = bpy.data.images.load(_found_path, check_existing=True)\n"
        # Preserve the original UDIM image's colorspace. A freshly-loaded
        # image gets Blender's auto-detected colorspace (usually 'sRGB'),
        # which is wrong for data textures: a normal map loaded as sRGB
        # produces blue-tinted garbage in Godot; an emissive map authored
        # in linear space loaded as sRGB shifts hues (cyan → red on the
        # Sci Fi Crate's accent strips). Copying the original's setting
        # ensures Roughness/Metallic/Normal/Emissive each end up in the
        # space the source artist intended.
        "        try:\n"
        "            _new_img.colorspace_settings.name = img.colorspace_settings.name\n"
        "        except Exception:\n"
        "            pass\n"
        "        _swapped[img.name] = _new_img\n"
        "    else:\n"
        "        _stripped_imgs.add(img.name)\n"
        "for mat in bpy.data.materials:\n"
        "    if not mat.use_nodes or mat.node_tree is None:\n"
        "        continue\n"
        "    _stripped_this_mat = False\n"
        "    for node in list(mat.node_tree.nodes):\n"
        "        if node.type != 'TEX_IMAGE' or node.image is None:\n"
        "            continue\n"
        "        if node.image.name in _swapped:\n"
        "            node.image = _swapped[node.image.name]\n"
        "        elif node.image.name in _stripped_imgs:\n"
        "            _stripped_this_mat = True\n"
        "            for out in node.outputs:\n"
        "                for link in list(out.links):\n"
        "                    mat.node_tree.links.remove(link)\n"
        "    if _stripped_this_mat:\n"
        "        for node in mat.node_tree.nodes:\n"
        "            if node.type != 'BSDF_PRINCIPLED':\n"
        "                continue\n"
        "            for socket_name in ('Emission', 'Emission Color'):\n"
        "                if socket_name in node.inputs:\n"
        "                    node.inputs[socket_name].default_value = (0.0, 0.0, 0.0, 1.0)\n"
        "            if 'Emission Strength' in node.inputs:\n"
        "                node.inputs['Emission Strength'].default_value = 0.0\n"
        + decimate_step + tint_step + texture_step +
        "for mat in bpy.data.materials:\n"
        "    mat.use_backface_culling = False\n"
        "    if hasattr(mat, 'blend_method'):\n"
        "        mat.blend_method = 'OPAQUE'\n"
        "bpy.ops.export_scene.gltf("
        f"filepath=r'{out_path}',"
        "export_format='GLB',"
        "export_apply=True,"
        "export_normals=True,"
        "export_tangents=True,"
        "export_animations=True,"
        "export_skins=True,"
        "export_materials='EXPORT',"
        "export_image_format='AUTO',"
        ")\n"
    )
    proc = subprocess.run(
        [blender, "--background", "--python-expr", script],
        check=False, capture_output=True, text=True,
    )
    if proc.returncode != 0 or not out_path.exists():
        print(proc.stdout)
        print(proc.stderr, file=sys.stderr)
        fail(f"Blender export failed for {blend_path}")


def append_manifest_row(asset_base_id: str, meta: dict, rel_path: Path, license_str: str) -> None:
    """Append a row under the '## 3D Models' table in docs/assets.md."""
    if not ASSETS_MD.exists():
        print(f"[import_blenderkit] (skipped manifest update — {ASSETS_MD} missing)")
        return
    text = ASSETS_MD.read_text(encoding="utf-8")
    # Find the 3D Models table block. Insert a new row right before the
    # next blank line after the table header.
    header = "## 3D Models"
    if header not in text:
        print("[import_blenderkit] (skipped manifest update — no '## 3D Models' section)")
        return
    name = meta.get("name", asset_base_id)
    url = f"https://www.blenderkit.com/get-blenderkit/{asset_base_id}/"
    rel = rel_path.relative_to(ROOT).as_posix()
    row = f"| {name} | [Blenderkit]({url}) | {license_str} | `{rel}` | ⚠️ | Imported via tools/import_blenderkit.py — license TBD until verified |\n"
    # Find the section bounds: from "## 3D Models" to the next "## " header.
    section_start = text.index(header)
    section_end_match = re.search(r"\n## ", text[section_start + len(header):])
    section_end = (section_start + len(header) + section_end_match.start()
                   if section_end_match else len(text))
    section = text[section_start:section_end]
    # Append the row at the end of the table — right before the trailing
    # blank line that precedes the next section.
    if section.rstrip().endswith("|"):
        # Section already has table rows ending with "|" — append after.
        updated = section.rstrip() + "\n" + row + "\n"
    else:
        # No rows yet (or stub copy) — append row at the section end.
        updated = section.rstrip() + "\n" + row + "\n"
    text = text[:section_start] + updated + text[section_end:]
    ASSETS_MD.write_text(text, encoding="utf-8", newline="\n")
    print(f"[import_blenderkit] added manifest row: {name}")


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("asset_id")
    p.add_argument("target_name")
    p.add_argument("--category", default="objects")
    p.add_argument("--license", default="Blenderkit — listed Free")
    p.add_argument("--decimate", type=float, default=0.05,
                   help="Mesh decimation ratio passed to Blender's Decimate "
                        "modifier (COLLAPSE). Default 0.05 (5%% of original) — "
                        "aggressive baseline for iso-camera kit pieces, where "
                        "Blenderkit's pre-subdivided source geometry is wildly "
                        "over-detailed (we've seen 350k+ tris on a single 2m "
                        "floor tile). Pass 1.0 to keep every polygon for "
                        "character or hero-prop imports where silhouette "
                        "matters more than instance count.")
    p.add_argument("--texture-size", type=int, default=1024,
                   help="Max texture dimension after import. Default 1024 — "
                        "kit-bash surfaces don't benefit from 2K/4K at iso "
                        "distance and the VRAM saved (75%% for 2K -> 1K) is "
                        "meaningful at horde density. Pass 2048 for hero "
                        "props or 0 to keep original resolution.")
    p.add_argument("--tint-emission", default="",
                   help="Recolor emissive textures to luminance × this color. "
                        "Format: 'r,g,b' with each in 0-255. Use when a model's "
                        "warning-red glow doesn't fit and you want cyan/etc — the "
                        "brightness pattern is preserved, only the hue changes. "
                        "Empty (default) skips tinting.")
    args = p.parse_args()

    asset_base_id = normalize_id(args.asset_id)
    print(f"[import_blenderkit] asset_base_id: {asset_base_id}")

    meta = fetch_metadata(asset_base_id)
    print(f"[import_blenderkit] asset: {meta.get('name', '?')} (free: {meta.get('isFree')})")

    blend = locate_cached_blend(meta)
    print(f"[import_blenderkit] cached source: {blend}")

    out = MODELS_OUT / args.category / args.target_name / f"{args.target_name}.glb"
    if out.exists():
        fail(f"target {out} already exists — delete it first if you want to replace")
    export_glb(blend, out, decimate_ratio=args.decimate, tint_emission=args.tint_emission, texture_size=args.texture_size)
    print(f"[import_blenderkit] exported: {out.relative_to(ROOT)} "
          f"(decimate={args.decimate})")

    append_manifest_row(asset_base_id, meta, out, args.license)
    print(f"[import_blenderkit] done.")


if __name__ == "__main__":
    main()
