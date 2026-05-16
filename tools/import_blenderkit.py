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


def export_glb(blend_path: Path, out_path: Path) -> None:
    """Drive Blender headless to open the .blend and export it as .glb
    with default settings. Does NOT modify geometry, normals, or materials."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    blender = os.environ.get("BLENDER", DEFAULT_BLENDER)
    if not Path(blender).exists():
        fail(f"Blender not found at {blender} — set $BLENDER to override")
    script = (
        "import bpy\n"
        f"bpy.ops.wm.open_mainfile(filepath=r'{blend_path}')\n"
        "bpy.ops.export_scene.gltf("
        f"filepath=r'{out_path}',"
        "export_format='GLB',"
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
    export_glb(blend, out)
    print(f"[import_blenderkit] exported: {out.relative_to(ROOT)}")

    append_manifest_row(asset_base_id, meta, out, args.license)
    print(f"[import_blenderkit] done.")


if __name__ == "__main__":
    main()
