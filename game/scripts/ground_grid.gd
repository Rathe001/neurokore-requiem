extends Node2D
class_name GroundGrid

# Procedural iso ground built from flat diamond polygons. Stand-in for
# a real TileMapLayer until we have Aseprite tiles to import.
# Checkerboard tint makes tile boundaries visible for debugging motion.

@export var radius: int = 14
@export var tint_a: Color = Color(0.16, 0.16, 0.20, 1)
@export var tint_b: Color = Color(0.12, 0.12, 0.15, 1)

func _ready() -> void:
	_build()

func _build() -> void:
	var diamond := PackedVector2Array([
		Vector2(0, -IsoGrid.HALF_HEIGHT),
		Vector2(IsoGrid.HALF_WIDTH, 0),
		Vector2(0, IsoGrid.HALF_HEIGHT),
		Vector2(-IsoGrid.HALF_WIDTH, 0),
	])
	for gx in range(-radius, radius + 1):
		for gy in range(-radius, radius + 1):
			var tile := Polygon2D.new()
			tile.polygon = diamond
			tile.position = IsoGrid.grid_to_world(Vector2i(gx, gy))
			tile.color = tint_a if ((gx + gy) & 1) == 0 else tint_b
			add_child(tile)
