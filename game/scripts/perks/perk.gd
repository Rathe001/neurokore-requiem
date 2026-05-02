class_name Perk extends Resource

## One tier perk on a stat ladder. Effects sum into PerkState aggregates;
## label/description drive the unlock banner and tooltip text.

@export var id: StringName = &""
@export var label: String = ""
@export var description: String = ""
@export var effects: Array[PerkEffect] = []
