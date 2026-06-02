class_name WallLiquidLayer
extends Node3D

## Wall blood overlay system — Phase 2 (SubViewport + shader sampling test).
##
## Architecture: thin quad MeshInstance3D for each wall surface, sampling
## a persistent SubViewport mask. Quad and SubViewport are BOTH children
## of this node — same subtree → ViewportTexture references resolve
## reliably (sidesteps the cross-tree quirk that defeated the previous
## attempt).
##
## Phase 2: introduce the SubViewport + a wall_blood_overlay ShaderMaterial
## on the debug quad. Stamp ONE static white circle into the SubViewport
## at startup. If the quad shows a white circle on a green background
## after reload, the sampling path works in this subtree. If the quad
## is all green, the SubViewport content isn't reaching the shader —
## stop and diagnose before adding more.

const DEBUG_QUAD_POSITION: Vector3 = Vector3(0.0, 1.5, 0.0)
const DEBUG_QUAD_SIZE: Vector2 = Vector2(2.0, 2.0)
const SUBVIEWPORT_PX: int = 512

var _subviewport: SubViewport
var _stamp_root: Node2D
var _camera2d: Camera2D
var _shader_material: ShaderMaterial


func _ready() -> void:
	add_to_group(&"wall_liquid_layer")
	_build_subviewport()
	_build_debug_quad()
	# Drop one static stamp into the SubViewport so the quad has
	# something to display besides the debug green background.
	_draw_test_stamp()


# 512² SubViewport with persistent (never-clear) render target —
# stamps added later will accumulate. Empty for now except for the
# Phase 2 test stamp.
func _build_subviewport() -> void:
	_subviewport = SubViewport.new()
	_subviewport.name = &"Mask"
	_subviewport.size = Vector2i(SUBVIEWPORT_PX, SUBVIEWPORT_PX)
	_subviewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.transparent_bg = true
	_subviewport.disable_3d = true
	_subviewport.audio_listener_enable_2d = false
	add_child(_subviewport)

	_camera2d = Camera2D.new()
	_camera2d.position = Vector2(float(SUBVIEWPORT_PX) * 0.5, float(SUBVIEWPORT_PX) * 0.5)
	_camera2d.zoom = Vector2.ONE
	_camera2d.enabled = true
	_subviewport.add_child(_camera2d)

	_stamp_root = Node2D.new()
	_stamp_root.name = &"StampRoot"
	_subviewport.add_child(_stamp_root)


# Replaces the Phase 1 magenta material with a ShaderMaterial that
# samples the SubViewport's texture. Quad + material + SubViewport
# all live under this WallLiquidLayer node.
func _build_debug_quad() -> void:
	var mi := MeshInstance3D.new()
	mi.name = &"DebugQuad"
	var mesh := QuadMesh.new()
	mesh.size = DEBUG_QUAD_SIZE
	mi.mesh = mesh
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = preload("res://shaders/wall_blood_overlay.gdshader")
	# Same-subtree ViewportTexture assignment — the whole point of this
	# architecture vs the previous cross-tree attempt.
	_shader_material.set_shader_parameter(&"mask", _subviewport.get_texture())
	mi.material_override = _shader_material
	mi.position = DEBUG_QUAD_POSITION
	mi.rotation_degrees = Vector3(-45.0, 0.0, 0.0)
	add_child(mi)


# Static test stamp — one white circle Sprite2D in the middle of the
# SubViewport. Drawn once, kept alive (no queue_free) so we can verify
# the mask retains it across frames + the shader samples it correctly.
func _draw_test_stamp() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := float(x - 32)
			var dy := float(y - 32)
			var d := sqrt(dx * dx + dy * dy) / 28.0
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	var tex := ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.position = Vector2(float(SUBVIEWPORT_PX) * 0.5, float(SUBVIEWPORT_PX) * 0.5)
	sprite.scale = Vector2(2.0, 2.0)
	_stamp_root.add_child(sprite)
