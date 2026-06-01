#!/usr/bin/env bash
# Extract the 4 Riot Guard enemy variants from ~/Desktop/models/enemies/
# into game/assets/characters/riot_guard_*/. Mixamo "Standing Idle.fbx"
# is the rigged mesh; the Meshy zip provides texture PNGs that
# meshy_character_import.gd wires into a StandardMaterial3D.

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ROOT="$HOME/Desktop/models/enemies"
DST="$ROOT/game/assets/characters"

ROWS="
Riot guard female 1|riot_guard_female_1
Riot guard female 2|riot_guard_female_2
Riot guard male 1|riot_guard_male_1
Riot guard male 2|riot_guard_male_2
"

while IFS='|' read -r src_name dst_name; do
    [[ -z "$src_name" ]] && continue
    src_dir="$SRC_ROOT/$src_name"
    rigged_fbx="$src_dir/Standing Idle.fbx"
    zip=$(find "$src_dir" -maxdepth 1 -name 'Meshy_AI_*.zip' | head -1)
    if [[ ! -f "$rigged_fbx" ]] || [[ -z "$zip" ]]; then
        echo "MISSING in $src_dir" >&2; continue
    fi
    dst_dir="$DST/$dst_name"
    rm -rf "$dst_dir"
    mkdir -p "$dst_dir"
    cp "$rigged_fbx" "$dst_dir/$dst_name.fbx"
    unzip -j -o "$zip" '*.png' -d "$dst_dir" >/dev/null
    echo "wired: $src_name → $dst_dir/"
done <<<"$ROWS"

echo
echo "✓ All 4 riot guards extracted."
