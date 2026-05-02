extends Resource
class_name RoomTemplate
## A weighted, role-tagged wrapper around a reusable RoomDef. Generators pick
## from a pool of these by role + weight to build a level. The template
## itself is small — all the geometry/lighting/decals/slots live on the
## RoomDef, which is shared across every instance the generator places.
##
## Conventional roles for the linear generator: "start" (1 outgoing wall),
## "linear" (2 opposite walls — through-traffic), "end" (1 incoming wall).
## Future generators (branching, BSP, grammar) add their own roles.

@export var room: RoomDef
@export var role: StringName = &"normal"
@export_range(0.01, 100.0) var weight: float = 1.0
