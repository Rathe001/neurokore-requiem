#!/usr/bin/env bash
# Unzip each Meshy character pack from tools/pilot/source/player/<gender>/<class>/
# into game/assets/characters/player_<spec>_<gender>/ and rename the FBX to a
# predictable name. Texture filenames are left as Meshy authored them so the
# FBX's internal texture references still resolve.
#
# Spec mapping per user (2026-06-01):
#   meshy "countess"/"count" → spec "count"
#   meshy "enculted"         → spec "enculted"
#   meshy "survivalist"      → spec "survivalist"
#   meshy "analog"           → origin "analog" (pre-spec fallback)
#   meshy "cyborg"           → origin "cyborg" (also fallback for the 3 cyborg specs)
#
# Run from repo root:
#   bash tools/extract_meshy_characters.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/tools/pilot/source/player"
DST="$ROOT/game/assets/characters"

# (gender, meshy_class_dir, target_spec) tuples. Compatible with macOS bash 3.x.
ROWS="
female analog       analog
female countess     count
female cyborg       cyborg
female enculted     enculted
female survivalist  survivalist
male   analog       analog
male   count        count
male   cyborg       cyborg
male   enculted     enculted
male   survivalist  survivalist
"

while read -r gender meshy_dir spec; do
    [[ -z "$gender" ]] && continue
    src_dir="$SRC/$gender/$meshy_dir"
    zip=$(find "$src_dir" -maxdepth 1 -name 'Meshy_AI_*.zip' | head -1)
    if [[ -z "$zip" ]]; then
        echo "MISSING zip in $src_dir" >&2
        continue
    fi
    dst_dir="$DST/player_${spec}_${gender}"
    mkdir -p "$dst_dir"
    rm -f "$dst_dir"/*.fbx "$dst_dir"/*.png  # idempotent re-runs
    unzip -j -o "$zip" -d "$dst_dir" >/dev/null
    fbx=$(find "$dst_dir" -maxdepth 1 -name '*.fbx' | head -1)
    target_fbx="$dst_dir/player_${spec}_${gender}.fbx"
    mv "$fbx" "$target_fbx"
    echo "extracted: $(basename "$zip") → $dst_dir/"
done <<<"$ROWS"

# ── Enemy: crimson_vein_titan ─────────────────────────────────────────
ENEMY_SRC="$ROOT/tools/pilot/source/enemies/crimson_vein_titan"
ENEMY_DST="$DST/crimson_vein_titan"
mkdir -p "$ENEMY_DST"
rm -f "$ENEMY_DST"/*.fbx
src_fbx=$(find "$ENEMY_SRC" -maxdepth 1 -name 'Meshy_AI_Crimson_Vein_Titan*.fbx' | head -1)
cp "$src_fbx" "$ENEMY_DST/crimson_vein_titan.fbx"
echo "extracted: $(basename "$src_fbx") → $ENEMY_DST/"

echo
echo "✓ Extracted all character meshes."
