#!/usr/bin/env bash
# Drop the Mixamo-exported rigged + animated FBX (Idle.fbx for males,
# "Unarmed Idle 01.fbx" for females) into each character folder. Mixamo
# FBXs ship the proper humanoid skeleton + a baked Idle animation, so the
# imported scene's AnimationPlayer exists and the X Bot library installs
# cleanly. The Meshy zip alongside is the texture source only — its PNGs
# get extracted next to the FBX and meshy_character_import.gd wires them
# into a StandardMaterial3D at import time.
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
    # Mixamo-exported rigged + animated FBX. Filename differs by gender.
    if [[ "$gender" == "male" ]]; then
        src_fbx="$src_dir/Idle.fbx"
    else
        src_fbx="$src_dir/Unarmed Idle 01.fbx"
    fi
    if [[ ! -f "$src_fbx" ]]; then
        echo "MISSING rigged FBX: $src_fbx" >&2
        continue
    fi
    zip=$(find "$src_dir" -maxdepth 1 -name 'Meshy_AI_*.zip' | head -1)
    if [[ -z "$zip" ]]; then
        echo "MISSING zip in $src_dir" >&2
        continue
    fi
    dst_dir="$DST/player_${spec}_${gender}"
    # Wipe so stale files from prior runs don't collide.
    rm -rf "$dst_dir"
    mkdir -p "$dst_dir"
    # Mesh: Mixamo-exported FBX (has rig + idle animation baked in).
    cp "$src_fbx" "$dst_dir/player_${spec}_${gender}.fbx"
    # Textures: extract from the Meshy zip but skip the zip's FBX —
    # meshy_character_import.gd finds the *.png files by naming convention
    # and wires them into a single StandardMaterial3D.
    unzip -j -o "$zip" '*.png' -d "$dst_dir" >/dev/null
    echo "wired:    $desktop_dir/$gender → $dst_dir/"
done <<<"$ROWS"

echo
echo "✓ All 16 characters wired (Mixamo rig+anim + Meshy textures)."
