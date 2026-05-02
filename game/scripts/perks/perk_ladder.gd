class_name PerkLadder extends Resource

## A stat's three-tier perk ladder. `perks[0]` = Tier I, `perks[1]` = Tier II,
## `perks[2]` = Tier III. PerkState reads `perks[0..get_unlocked_tier-1]` per
## stat each recompute. Empty array means "no perks defined yet for this stat
## tree" — the entry still loads cleanly so consumers can skip it.
##
## Convention: live at `res://resources/perks/{stat_id}.tres` and PerkState
## auto-loads them by stat ID on _ready. Adding the next class's perks is a
## .tres edit, not code.

@export var perks: Array[Perk] = []
