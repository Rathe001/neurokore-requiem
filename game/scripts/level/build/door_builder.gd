extends RefCounted
class_name DoorBuilder
## Door instantiation + lock/boss-unlock state. Registers each door in
## ctx.doors keyed by "{room_id}_{wall_name}" so LevelBuilder.get_door()
## can look them up later for puzzle wiring.

const DOOR_SCENE: PackedScene = preload("res://scenes/prototype/prototype_door.tscn")
const DOOR_MESH_WIDTH := 4.0  # door scene mesh Z-extent (used for per-opening scale)
const DOOR_MESH_HEIGHT := 4.5  # door scene mesh Y-extent (used for wall-height clamp)
# Stop the door short of the ceiling so a visible lintel sits above it — the
# open door then reads as tucking behind the wall, instead of dematerializing
# into a flush ceiling line.
const DOOR_LINTEL_RATIO := 0.85


static func build_door(ctx: LevelBuildContext, piece_id: StringName, rd: RoomDef, side: RoomDef.Wall, wpos: Vector3) -> void:
	# Idempotency guard. The per-room wall iteration in LevelBuilder
	# already visits each side once, but the procgen layer can occasionally
	# emit redundant connections (same from_room + from_wall pair via
	# different graph paths). Without this check, a downstream re-entry
	# stacks a second door at the exact same wpos — two PrototypeDoor
	# instances overlapping with identical animations, identical lock
	# state, but registered under the same dict key so only one is
	# reachable via get_door(). The visible artifact is two doors clipping
	# through each other at the doorway.
	var door_key := StringName("%s_%s" % [piece_id, ctx.wall_keys[side]])
	if ctx.doors.has(door_key):
		# A door for this (piece, wall) already exists — short-circuit.
		# Caller intent for the second call (locked? boss-unlock? unlock
		# requirement?) is dropped, but the existing door's flags were
		# already set on the first call. If we ever need to merge flags
		# across multiple emissions, do it explicitly here rather than
		# silently letting the second instance physically stack.
		return
	# Position-based dedup. Two DIFFERENT pieces (e.g. neighboring rooms
	# whose connecting walls resolve to the same world position because
	# of a procgen layout quirk) can each emit a door at the same wpos
	# with different door_keys — the key-based check above wouldn't catch
	# that. A 0.5m threshold is well below the smallest authored room
	# size, so legit doors on neighboring walls never collide here, but
	# stacked doors at identical positions get filtered. Logs a warning
	# so procgen issues surface in the editor without breaking the level.
	const _STACK_THRESHOLD_SQ := 0.25  # 0.5m squared
	for existing_var in ctx.doors.values():
		var existing := existing_var as Node3D
		if existing == null or not is_instance_valid(existing):
			continue
		if existing.global_position.distance_squared_to(wpos) < _STACK_THRESHOLD_SQ:
			push_warning("[DoorBuilder] stacked door rejected at %s (piece %s wall %s) — existing door already present" % [wpos, piece_id, ctx.wall_keys[side]])
			return
	var door := DOOR_SCENE.instantiate() as Node3D
	door.transform.origin = wpos
	if side == RoomDef.Wall.NORTH or side == RoomDef.Wall.SOUTH:
		door.rotation_degrees.y = 90.0

	var thick := ctx.theme.wall_thickness
	var perp := rd.size.x - thick if (side == RoomDef.Wall.NORTH or side == RoomDef.Wall.SOUTH) else rd.size.y - thick
	var opening_w := minf(rd.opening_width, perp)
	door.scale.z = opening_w / DOOR_MESH_WIDTH
	# Parent-scale Y so the slide animation (mesh.position.y in local space) compresses with the mesh.
	door.scale.y = (ctx.theme.wall_height * DOOR_LINTEL_RATIO) / DOOR_MESH_HEIGHT

	# Fill the wall opening above the door with a lintel block. Without this,
	# the wall builder cuts a full-wall-height hole for the door but the
	# shortened door only fills the bottom 85% — leaving a visible open gap
	# from door-top up to wall-top that the user can see through.
	#
	# Insets on every axis to avoid coplanar z-fighting:
	#   • TOP: lintel top would otherwise = wall_height = ceiling.y → z-fight
	#     against ceiling's bottom face.
	#   • SIDES: lintel ends would otherwise meet the jamb inner faces flush
	#     → z-fight along the seam.
	# 1 cm inset on each face is invisible at iso but breaks every shared
	# plane.
	const _LINTEL_INSET := 0.01
	var door_world_height := ctx.theme.wall_height * DOOR_LINTEL_RATIO
	var lintel_gap := ctx.theme.wall_height - door_world_height
	if lintel_gap > 0.02:
		var lintel_height := lintel_gap - _LINTEL_INSET * 2.0
		# Center in the gap so the lintel has equal clearance above (to
		# the ceiling) and below (to the door's closed-state top).
		var lintel_y := door_world_height + lintel_gap * 0.5
		var lintel_pos := wpos + Vector3(0.0, lintel_y, 0.0)
		var along_x := side == RoomDef.Wall.EAST or side == RoomDef.Wall.WEST
		var lintel_sx := (thick if along_x else opening_w) - _LINTEL_INSET * 2.0
		var lintel_sz := (opening_w if along_x else thick) - _LINTEL_INSET * 2.0
		WallBuilder.create_trim_box(ctx, lintel_pos, lintel_sx, lintel_height, lintel_sz)

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
