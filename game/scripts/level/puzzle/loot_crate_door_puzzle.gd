extends PuzzleDef
class_name LootCrateDoorPuzzle
## One loot crate → one door. Configures the crate to spit out a starter
## weapon kit (one common 2H, OR one common 1H + offhand) AND wires its
## first interact to unlock the named door connection. Used by
## BranchingGenerator on the spawn room so the player has to grab a
## weapon from the chest before they can leave.

@export var crate_slot_id: StringName = &""           ## level-global slot key, e.g. "r0.starter_chest"
@export var door_connection_id: StringName = &""
## When true (default), force `starter_weapon_kit = true` on the crate so
## it drops the playable starter loadout. Set false if you want a custom
## fixed_items / random loadout but still want the crate to gate a door.
@export var force_starter_kit: bool = true


func apply(_ctx: LevelBuildContext, slots: Dictionary, doors: Dictionary) -> void:
	# NG+ runs already have gear from the previous loop — skip the starter
	# chest setup entirely. The crate node still exists in the room (placed
	# by the level builder) but stays unconfigured: no starter kit, no door
	# wiring. The door it would have gated stays unlocked, so the player
	# walks through unimpeded.
	if PlayerState.new_game_plus > 0:
		return
	if door_connection_id == &"":
		push_error("[LootCrateDoorPuzzle] door_connection_id not set.")
		return
	var door := doors.get(door_connection_id) as PrototypeDoor
	if door == null:
		push_error("[LootCrateDoorPuzzle] No door found for connection '%s'." % door_connection_id)
		return
	if crate_slot_id == &"":
		push_error("[LootCrateDoorPuzzle] crate_slot_id not set.")
		return
	var crate := slots.get(crate_slot_id) as PrototypeLootCrate
	if crate == null:
		push_error("[LootCrateDoorPuzzle] Slot '%s' is not a PrototypeLootCrate (or missing)." % crate_slot_id)
		return
	door.setup_lock(1, true, false)
	crate.target_door = crate.get_path_to(door)
	if force_starter_kit:
		crate.starter_weapon_kit = true
