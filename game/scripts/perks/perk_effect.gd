class_name PerkEffect extends Resource

## A single magnitude grant that contributes to a PerkState aggregate.
## See perk_state.gd's effect-kind list for the keys combat / projectile /
## player code reads via PerkState.get_aggregate(kind).

@export var kind: StringName = &""
@export var magnitude: float = 0.0
