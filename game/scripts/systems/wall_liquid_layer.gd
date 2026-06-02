class_name WallLiquidLayer
extends Node3D

## Wall blood overlay system — Phase 1 (foundation test).
##
## Goal: a thin quad MeshInstance3D for each wall surface, positioned
## slightly in front of the wall along its outward normal, sampling a
## persistent SubViewport mask. Because the overlay quad and the
## SubViewport are both children of THIS node, the ViewportTexture
## reference stays inside one subtree — sidestepping the Godot 4 cross-
## tree-ViewportTexture quirk that defeated the previous attempt.
##
## Phase 1: place ONE magenta debug quad at level origin to confirm we
## can put visible geometry as a child of WallLiquidLayer and have it
## render at all. No SubViewport, no shader, no walls — just the
## foundation. If the magenta quad is visible after reload, we're clear
## to move to Phase 2.

const DEBUG_QUAD_POSITION: Vector3 = Vector3(0.0, 1.5, 0.0)
const DEBUG_QUAD_SIZE: Vector2 = Vector2(2.0, 2.0)


func _ready() -> void:
	add_to_group(&"wall_liquid_layer")
	_build_debug_quad()


# Drops a 2m × 2m magenta plane at the level origin, 1.5m off the floor.
# Unshaded so lighting can't hide it — pure magenta. Both sides render
# so the quad is visible from any camera angle.
func _build_debug_quad() -> void:
	var mi := MeshInstance3D.new()
	mi.name = &"DebugQuad"
	var mesh := QuadMesh.new()
	mesh.size = DEBUG_QUAD_SIZE
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.MAGENTA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.position = DEBUG_QUAD_POSITION
	# Face the iso camera — pitch the quad to be mostly upright + tilted
	# so it's clearly a quad in 3D, not just a flat ground decal.
	mi.rotation_degrees = Vector3(-45.0, 0.0, 0.0)
	add_child(mi)
