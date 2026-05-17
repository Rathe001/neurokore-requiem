#!/usr/bin/env python3
"""Dump the JSON chunk of a .glb so we can see exactly what materials,
alpha modes, doubleSided flags, extensions, etc. are baked into the file
the import script produced. No dependencies — parses the binary glTF
header manually.

Usage:
    python tools/inspect_glb.py game/assets/models/objects/loot_crate/loot_crate.glb
"""

import json
import struct
import sys
from pathlib import Path


def parse_glb(path: Path) -> dict:
    data = path.read_bytes()
    magic, version, total = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:  # 'glTF' little-endian
        raise SystemExit(f"not a glb: magic={magic:x}")
    if version != 2:
        raise SystemExit(f"unexpected glTF version {version}")
    offset = 12
    chunk_len, chunk_type = struct.unpack_from("<II", data, offset)
    offset += 8
    if chunk_type != 0x4E4F534A:  # 'JSON'
        raise SystemExit(f"first chunk is not JSON: type={chunk_type:x}")
    json_bytes = data[offset:offset + chunk_len].rstrip(b"\x00\x20")
    return json.loads(json_bytes)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: inspect_glb.py <path-to-glb>")
    g = parse_glb(Path(sys.argv[1]))

    mats = g.get("materials", [])
    print(f"== materials ({len(mats)}) ==")
    for i, m in enumerate(mats):
        name = m.get("name", "?")
        alpha_mode = m.get("alphaMode", "OPAQUE")
        alpha_cutoff = m.get("alphaCutoff")
        double_sided = m.get("doubleSided", False)
        ext = list((m.get("extensions") or {}).keys())
        pbr = m.get("pbrMetallicRoughness", {})
        base = pbr.get("baseColorFactor")
        metal = pbr.get("metallicFactor")
        rough = pbr.get("roughnessFactor")
        has_tex = "yes" if "baseColorTexture" in pbr else "no"
        emissive = m.get("emissiveFactor")
        print(f"  [{i}] {name!r}")
        print(f"      alphaMode={alpha_mode}  alphaCutoff={alpha_cutoff}  doubleSided={double_sided}")
        print(f"      baseColorFactor={base}  metallic={metal}  roughness={rough}  baseColorTexture={has_tex}")
        if emissive:
            print(f"      emissiveFactor={emissive}")
        if ext:
            print(f"      extensions={ext}")

    print(f"\n== meshes ({len(g.get('meshes', []))}) ==")
    for i, mesh in enumerate(g.get("meshes", [])):
        prims = mesh.get("primitives", [])
        mat_ids = [p.get("material") for p in prims]
        mode = [p.get("mode", 4) for p in prims]
        print(f"  [{i}] {mesh.get('name', '?')!r}  prims={len(prims)}  materials={mat_ids}  modes={mode}")

    print(f"\n== nodes ({len(g.get('nodes', []))}) ==")
    for i, n in enumerate(g.get("nodes", [])):
        print(f"  [{i}] {n.get('name','?')!r}  mesh={n.get('mesh')}  children={n.get('children')}")

    anims = g.get("animations", [])
    print(f"\n== animations ({len(anims)}) ==")
    for i, a in enumerate(anims):
        name = a.get("name", "?")
        channels = a.get("channels", [])
        print(f"  [{i}] {name!r}  channels={len(channels)}")

    print(f"\n== extensionsUsed: {g.get('extensionsUsed')}")
    print(f"== extensionsRequired: {g.get('extensionsRequired')}")


if __name__ == "__main__":
    main()
