extends Node

## Hides enemies from rendering when the player has no line of sight to them.
## Each physics frame, raycasts player → enemy at chest height against the
## World physics layer (walls). When the ray hits a wall, the enemy's `visible`
## is set to false; otherwise true.
##
## Cheap at prototype horde sizes (raycasts against a small World layer). If
## this shows up in the profiler at end-game density, stagger the checks
## across frames or add a max-distance early-out.

const WORLD_LAYER_MASK := 1  # physics layer 1 ("World") — walls + floors
const RAY_HEIGHT := 1.0      # chest-height sample so the ray clears floor/ceiling colliders

var _query := PhysicsRayQueryParameters3D.new()
var _visible_to_player: Dictionary = {}

func _ready() -> void:
	_query.collision_mask = WORLD_LAYER_MASK
	_query.collide_with_areas = false
	_query.collide_with_bodies = true

func _physics_process(_delta: float) -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var player := players[0] as Node3D
	if player == null:
		return
	var space := player.get_world_3d().direct_space_state
	if space == null:
		return
	var from := player.global_position + Vector3(0, RAY_HEIGHT, 0)
	for e in get_tree().get_nodes_in_group(&"enemies"):
		var node := e as Node3D
		if node == null:
			continue
		_query.from = from
		_query.to = node.global_position + Vector3(0, RAY_HEIGHT, 0)
		var has_los := space.intersect_ray(_query).is_empty()
		node.visible = has_los
		_visible_to_player[node] = has_los

## True if `node` had line of sight to the player as of the most recent physics
## tick. Returns false for nodes that haven't been tested yet — callers should
## treat "unknown" as occluded, which is the safe default for AI gates.
func has_los_to_player(node: Node) -> bool:
	return _visible_to_player.get(node, false)
