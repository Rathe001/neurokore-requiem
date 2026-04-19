class_name IsoGrid
extends RefCounted

# Coordinate conversion between grid space (integer tile coords) and
# world space (pixels). Tiles are diamond-shaped with the standard 2:1
# isometric ratio. Used for placement math and hit-testing.
#
# Grid axes:
#   +X points down-right on screen
#   +Y points down-left on screen
# Origin (0,0) sits at world (0,0).

const TILE_WIDTH := 64
const TILE_HEIGHT := 32
const HALF_WIDTH := TILE_WIDTH / 2.0
const HALF_HEIGHT := TILE_HEIGHT / 2.0

static func grid_to_world(grid: Vector2i) -> Vector2:
	return Vector2(
		(grid.x - grid.y) * HALF_WIDTH,
		(grid.x + grid.y) * HALF_HEIGHT
	)

static func world_to_grid(world: Vector2) -> Vector2i:
	var gx := (world.x / HALF_WIDTH + world.y / HALF_HEIGHT) * 0.5
	var gy := (world.y / HALF_HEIGHT - world.x / HALF_WIDTH) * 0.5
	return Vector2i(int(floor(gx)), int(floor(gy)))
