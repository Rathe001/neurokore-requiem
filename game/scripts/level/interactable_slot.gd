extends Resource
class_name InteractableSlot
## A spawn point for a world interactable inside a room — switch, loot crate,
## exit pad, etc. The id is local to the parent RoomDef (designer reusable
## across rooms); the level builder qualifies it as "{room_id}.{slot_id}"
## when registering the spawned node, so puzzles and runtime lookups have a
## level-global name without the designer having to mint unique strings.

@export var id: StringName = &""
@export var scene: PackedScene
## Position relative to the room's centre.
@export var offset: Vector3 = Vector3.ZERO
## Yaw in degrees applied to the spawned instance.
@export var rotation_y: float = 0.0
## Can the player land on top of this interactable? Switches and loot crates
## are platform-able by default (their flat-topped collision shapes already
## allow landing). Set false on tall/fragile interactables (lab consoles,
## glass cases) so we know to give them a sloped/curved collision top — the
## flag is a design contract, not a runtime behaviour by itself.
@export var jumpable: bool = true
