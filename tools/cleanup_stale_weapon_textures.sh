#!/usr/bin/env bash
# Delete leftover texture files in game/assets/models/weapons/<weapon>/
# that don't match the new Meshy GLB's texture export naming. The
# active set per weapon is:
#   <weapon>.glb / .glb.import
#   <weapon>_Image_*.jpg / .jpg.import     (PBR color + ORM layers Godot
#                                          extracts from the embedded GLB)
#   <weapon>_normal.png / .png.import      (normal map)
#
# Everything else is from prior Blenderkit-sourced weapon models that
# have been replaced. Grenade is skipped — it still uses its original
# (non-Meshy) PBR layout.
#
# Run from repo root:
#   bash tools/cleanup_stale_weapon_textures.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WPN_ROOT="$ROOT/game/assets/models/weapons"

for d in "$WPN_ROOT"/*/; do
    weapon=$(basename "$d")
    if [[ "$weapon" == "grenade" ]]; then
        continue
    fi
    # Files we keep — strict regex to avoid catching arbitrary mid-name matches.
    keep_glb="^${weapon}\.glb(\.import)?$"
    keep_image="^${weapon}_Image_[0-9]+\.jpg(\.import)?$"
    keep_normal="^${weapon}_normal\.png(\.import)?$"
    for f in "$d"*; do
        name=$(basename "$f")
        if [[ "$name" =~ $keep_glb ]] || [[ "$name" =~ $keep_image ]] || [[ "$name" =~ $keep_normal ]]; then
            continue
        fi
        echo "  rm $weapon/$name"
        git rm -f --quiet "$f" 2>/dev/null || rm -f "$f"
    done
done

echo
echo "✓ Cleaned stale weapon textures."
