#!/usr/bin/env bash
# Replace each weapon GLB with the matching Meshy_AI_*.glb the user
# generated at ~/Desktop/models/weapons/. Existing GLB sidecars (PBR
# texture JPGs/PNGs and their .import files) are preserved by name but
# will be re-extracted by Godot's GLB importer from the new file's
# embedded data on next reimport — anything stale gets overwritten.
#
# Naming map (Desktop → game folder):
#   Arc_taser            → arc_taser
#   Blade                → blade
#   Laser_pistol         → laser_pistol
#   LMG                  → lmg
#   Particle_accelerator → energy_accelerator
#   Plasma_Rifle         → plasma_rifle
#   RPG                  → rpg
#   Shotgun              → shotgun
#   Sledgehammer         → hammer
#   SMG                  → smg
#   Sniper_rifle         → sniper
#
# Grenade has no replacement in this batch — left untouched.
#
# Run from repo root:
#   bash tools/swap_in_weapons.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HOME/Desktop/models/weapons"
DST="$ROOT/game/assets/models/weapons"

# (meshy_prefix, game_folder) pairs. Compatible with macOS bash 3.x.
ROWS="
Arc_taser             arc_taser
Blade                 blade
Laser_pistol          laser_pistol
LMG                   lmg
Particle_accelerator  energy_accelerator
Plasma_Rifle          plasma_rifle
RPG                   rpg
Shotgun               shotgun
Sledgehammer          hammer
SMG                   smg
Sniper_rifle          sniper
"

while read -r meshy_prefix game_folder; do
    [[ -z "$meshy_prefix" ]] && continue
    src_glb=$(find "$SRC" -maxdepth 1 -name "Meshy_AI_${meshy_prefix}_*.glb" | head -1)
    if [[ -z "$src_glb" ]]; then
        echo "MISSING: Meshy_AI_${meshy_prefix}_*.glb" >&2
        continue
    fi
    dst_dir="$DST/$game_folder"
    if [[ ! -d "$dst_dir" ]]; then
        echo "MISSING dest dir: $dst_dir" >&2
        continue
    fi
    cp "$src_glb" "$dst_dir/$game_folder.glb"
    echo "swapped: $(basename "$src_glb") → $dst_dir/$game_folder.glb"
done <<<"$ROWS"

echo
echo "✓ Swapped weapon GLBs. Run Godot --headless --import next."
