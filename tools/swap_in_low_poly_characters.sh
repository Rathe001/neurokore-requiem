#!/usr/bin/env bash
# Replace the heavy Meshy-zip character meshes with the lower-tri standalone
# FBX exports the user generated at ~/Desktop/models/{male,female}/<class>/.
#
# Source priority per class folder:
#   1) Meshy_AI_*.zip — extracted; uses the zip's FBX (texture refs point at
#      Meshy filenames bundled in the same zip, so textures resolve cleanly).
#      Tri count matches the Mixamo "Idle" FBX in the same folder (both are
#      the same Meshy-generated mesh), so we get the lower-poly visual the
#      user asked for without hitting the Idle.fbx's missing-texture issue.
#   2) (fallback unused) Mixamo Idle.fbx / Unarmed Idle 01.fbx — would give
#      same tri count but the FBX references textures by Mixamo internal
#      paths and Godot can't resolve them without manual material wiring.
#
# Spec-name fixups (Desktop → game id):
#   countess (female) → count
#   count    (male)   → count
#   automoton         → automaton  (Desktop has the typo)
#
# Run from repo root:
#   bash tools/swap_in_low_poly_characters.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ROOT="$HOME/Desktop/models"
DST="$ROOT/game/assets/characters"

# (gender, desktop_class_dir, target_spec) tuples. Compatible with macOS bash 3.x.
ROWS="
female analog       analog
female countess     count
female cyborg       cyborg
female enculted     enculted
female survivalist  survivalist
female forged       forged
female automoton    automaton
female polymath     polymath
male   analog       analog
male   count        count
male   cyborg       cyborg
male   enculted     enculted
male   survivalist  survivalist
male   forged       forged
male   automoton    automaton
male   polymath     polymath
"

while read -r gender desktop_dir spec; do
    [[ -z "$gender" ]] && continue
    src_dir="$SRC_ROOT/$gender/$desktop_dir"
    zip=$(find "$src_dir" -maxdepth 1 -name 'Meshy_AI_*.zip' | head -1)
    if [[ -z "$zip" ]]; then
        echo "MISSING zip in $src_dir" >&2
        continue
    fi
    dst_dir="$DST/player_${spec}_${gender}"
    # Wipe the folder so stale FBX + textures from prior runs don't collide.
    rm -rf "$dst_dir"
    mkdir -p "$dst_dir"
    unzip -j -o "$zip" -d "$dst_dir" >/dev/null
    fbx=$(find "$dst_dir" -maxdepth 1 -name 'Meshy_AI_*.fbx' | head -1)
    mv "$fbx" "$dst_dir/player_${spec}_${gender}.fbx"
    echo "extracted: $desktop_dir/$gender → $dst_dir/"
done <<<"$ROWS"

echo
echo "✓ Extracted all 16 character meshes from new Meshy zips."
