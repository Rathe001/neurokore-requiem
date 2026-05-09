extends RefCounted
class_name DoorBuilder
## Door instantiation + lock/boss-unlock state. Registers each door in
## ctx.doors keyed by "{room_id}_{wall_name}" so LevelBuilder.get_door()
## can look them up later for puzzle wiring.

const DOOR_SCENE: PackedScene = preload("res://scenes/prototype/prototype_door.tscn")
const DOOR_MESH_WIDTH := 4.0  # door scene mesh Z-extent (used for per-opening scale)


static func build_door(ctx: LevelBuildContext, piece_id: StringName, rd: RoomDef, side: RoomDef.Wall, wpos: Vector3) -> void:
	var door := DOOR_SCENE.instantiate() as Node3D
	door.transform.origin = wpos
	if side == RoomDef.Wall.NORTH or side == RoomDef.Wall.SOUTH:
		door.rotation_degrees.y = 90.0

	var thick := ctx.theme.wall_thickness
	var perp := rd.size.x - thick if (side == RoomDef.Wall.NORTH or side == RoomDef.Wall.SOUTH) else rd.size.y - thick
	door.scale.z = minf(rd.opening_width, perp) / DOOR_MESH_WIDTH

	if door is PrototypeDoor:
		var pdoor := door as PrototypeDoor
		if side in rd.locked_doors:
			pdoor.locked = true
		if rd.unlock_required_doors.has(side):
			pdoor.unlocks_required = int(rd.unlock_required_doors[side])
		if side in rd.boss_unlock_doors:
			pdoor.unlock_on_boss = true

	# Deterministic name keyed on (piece_id, wall) so the door lives at the
	# same NodePath on host AND client — the door's @rpc methods route by
	# path, and Godot's auto-@N suffix rename can drift between peers if
	# iteration order isn't byte-identical.
	door.name = _door_node_name(piece_id, ctx.wall_keys[side])
	ctx.root.add_child(door)
	# Keyed by per-instance piece_id so generator-reused RoomDef templates
	# don't collide on the doors registry. PuzzleBuilder maps this back from
	# Connection.from_room (which is also a per-instance id).
	ctx.doors[StringName("%s_%s" % [piece_id, ctx.wall_keys[side]])] = door


# Build a Godot-safe deterministic node name from the door key. Same
# stripping pattern as InteractableBuilder._slot_node_name.
static func _door_node_name(piece_id: StringName, wall_name: String) -> String:
	var raw := "Door_%s_%s" % [piece_id, wall_name]
	return raw.replace("/", "_").replace(":", "_").replace("@", "_").replace(".", "_")
