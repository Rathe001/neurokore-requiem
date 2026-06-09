extends Node

## Catches MeshInstance3D / MultiMeshInstance3D nodes as they enter the
## scene tree and assigns a fallback StandardMaterial3D to any null
## surface. Suppresses the RenderingServer's
## `material_update_dependency / material_casts_shadows /
## material_is_animated / material_get_instance_shader_parameters:
## Parameter "material" is null` log spam that fires once per
## null-material surface per frame.
##
## Lives as an autoload because the main scene's nodes enter the tree
## after autoloads' _ready but BEFORE the main scene's own _ready —
## so connecting node_added from a main-scene script misses the
## level_shell scene's initial children. The autoload _ready fires
## first, the connection is live, every node the main scene adds (and
## every node the level builder streams in afterwards) fires the
## signal at insertion time and my handler patches surfaces in the
## same frame, before the render server processes them.
##
## Implementation lives in XBotRagdoll.ensure_surface_materials_single
## so the same logic that runs for ragdoll bodies also runs everywhere
## else.
func _ready() -> void:
	get_tree().node_added.connect(XBotRagdoll.ensure_surface_materials_single)
