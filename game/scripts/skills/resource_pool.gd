extends Resource
class_name ResourcePool

# Single named resource with a max, a starting value, and a passive regen
# rate. Placeholder for class-specific systems (Adrenaline, Composure, etc).

@export var display_name: String = ""
@export var max_value: int = 100
@export var start_value: int = 100
@export var regen_per_sec: float = 0.0
@export var color: Color = Color(0.4, 0.7, 1, 1)
