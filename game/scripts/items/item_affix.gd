class_name ItemAffix extends Resource

## A single prefix or suffix that can be applied to an item at generation time.
##
## stat_modifiers maps stat names to flat integer values, e.g.:
##   { "orthodoxy": 8, "ingenuity": 3 }
## All 6 rollable attributes (orthodoxy, deviation, optimization,
## ingenuity, clarity, ambition) plus combat stats are valid keys.

enum Kind { PREFIX, SUFFIX }

@export var id: StringName
@export var label: String = ""        # Display string, e.g. "Searing" or "of the Leech"
@export var kind: Kind = Kind.PREFIX
## Item main_types this affix can appear on. Empty = any type.
@export var item_types: Array[String] = []
## Base stat changes applied to the item.
@export var stat_modifiers: Dictionary = {}
## Min item level required for this affix to roll.
@export var min_item_level: int = 1
## Relative weight in the roll pool — higher = more common.
@export var weight: int = 100
