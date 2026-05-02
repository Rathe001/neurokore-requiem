class_name OpticsVariant extends Resource

## A single Optics sub-type (Flashlight, Lantern, Scanner, UV, …). One .tres
## per variant lives at res://resources/items/optics/; ItemRoller loads them
## from OPTICS_VARIANT_PATHS at _ready and rolls one at random when an
## "Optics" main_type is generated.
##
## Adding a new optic = author a new .tres + add its path to ItemRoller's
## OPTICS_VARIANT_PATHS const. Per-variant fields stay in the editor, not
## hand-typed dicts.

@export var display_name: String = ""
@export var glyph: String = "?"
@export var light_type: Item.LightType = Item.LightType.DIRECTIONAL
@export var light_range: float = 0.0
@export var light_energy_min: float = 0.0
@export var light_energy_max: float = 0.0
@export var light_color: Color = Color.WHITE
