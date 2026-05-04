class_name OpticsVariant extends Resource

## A single Recon sub-type (Flashlight, Lantern, Scanner, UV, …). One .tres
## per variant lives at res://resources/items/optics/ (directory kept on
## disk for now); ItemRoller loads them from OPTICS_VARIANT_PATHS at
## _ready and rolls one at random when a "Recon" main_type is generated.
## Class is still named OpticsVariant — the script-level rename is a
## separate change with its own .uid migration risk.
##
## Adding a new optic = author a new .tres + add its path to ItemRoller's
## OPTICS_VARIANT_PATHS const. Per-variant fields stay in the editor, not
## hand-typed dicts.

@export var display_name: String = ""
## Categorical type label shown on the tooltip type line (e.g. "Radar",
## "Flashlight"). Falls back to display_name when empty so legacy
## variants without an explicit sub_type still render something sensible.
## Lets the marketing name ("Phased Surveillance Radar") differ from
## the bucket label ("Radar") on the tooltip.
@export var sub_type: String = ""
@export var glyph: String = "?"
@export var light_type: Item.LightType = Item.LightType.DIRECTIONAL
@export var light_range: float = 0.0
@export var light_energy_min: float = 0.0
@export var light_energy_max: float = 0.0
@export var light_color: Color = Color.WHITE
