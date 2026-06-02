class_name WallLiquidLayer
extends Node3D

## Wall blood overlay system — Phase 3 (wall enumeration + quad spawning).
##
## Architecture: overlay quads as children of THIS node, sampling a
## persistent SubViewport mask that's also a child of THIS node. Same
## subtree → ViewportTexture references resolve reliably.
##
## Phase 4: overlay quads now use wall_blood_overlay.gdshader instead of
## solid cyan. Shader samples the SubViewport mask at the quad's local UV;
## empty mask → discard (wall shows through), stamped → solid red.
## Verifies the SubViewport-to-shader path works on every actual wall
## quad we spawn — visible as the Phase 2 test stamp (a circle of red)
## centered on every overlay quad.
##
## Phase 5 will: switch from local UV to world-position UV so stamps
## land at the correct world location instead of repeating per quad;
## add the multiply-stain + PBR wet shading; wire gameplay stamps.

const SUBVIEWPORT_PX: int = 512
# Distance from wall surface to overlay quad — small enough to read
# as "on" the wall, big enough to avoid z-fighting with the wall mesh.
const SURFACE_OFFSET: float = 0.005

var _subviewport: SubViewport
var _stamp_root: Node2D
var _camera2d: Camera2D
# Shared ShaderMaterial bound to every overlay quad. Sampling the
# SubViewport texture through this single material instance means
# the binding only has to happen once — and stays inside the subtree.
var _overlay_material: ShaderMaterial


func _ready() -> void:
	add_to_group(&"wall_liquid_layer")
	_build_subviewport()
	_build_overlay_material()
	_draw_test_stamp()
	_hook_level_builder()


# One ShaderMaterial shared across all overlay quads. The sampler
# binding lives here — child quads just reference the material.
func _build_overlay_material() -> void:
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = preload("res://shaders/wall_blood_overlay.gdshader")
	_overlay_material.set_shader_parameter(&"mask", _subviewport.get_texture())


func _hook_level_builder() -> void:
	# Hook into LevelBuilder's `built` signal so wall enumeration runs
	# AFTER all wall MMIs + individual walls are committed. LevelBuilder
	# is a sibling under LevelShell.
	var builder := get_parent().get_node_or_null(^"LevelBuilder") if get_parent() != null else null
	if builder == null:
		return
	if builder.has_signal(&"built"):
		builder.built.connect(_on_level_built)


# Walks the scene tree's &"structures" group and spawns one overlay quad
# per wall face. Handles two wall sources:
#   1. MultiMeshInstance3D batched walls (corridor walls + similar)
#   2. StaticBody3D-wrapped individual wall meshes (create_wall paths)
# Room procedural walls (one mesh covering 4 sides) are handled separately.
func _on_level_built() -> void:
	var structures := get_tree().get_nodes_in_group(&"structures")
	var overlay_count := 0
	for node in structures:
		if node is MultiMeshInstance3D and ("CorridorWalls" in node.name or "Wall" in node.name):
			overlay_count += _spawn_overlays_for_mmi(node)
		elif node is StaticBody3D:
			overlay_count += _spawn_overlays_for_static_body(node)
	print("[WallLiquidLayer] Phase 3: spawned ", overlay_count, " overlay quad(s)")


func _spawn_overlays_for_mmi(mmi: MultiMeshInstance3D) -> int:
	var mm := mmi.multimesh
	if mm == null:
		return 0
	var count := 0
	var base_xform := mmi.global_transform
	for i in mm.instance_count:
		var local_xform := mm.get_instance_transform(i)
		var world_xform := base_xform * local_xform
		if _spawn_overlay_for_wall(world_xform):
			count += 1
	return count


func _spawn_overlays_for_static_body(body: StaticBody3D) -> int:
	var count := 0
	for child in body.get_children():
		if not (child is MeshInstance3D):
			continue
		var mi: MeshInstance3D = child
		if not (mi.mesh is BoxMesh):
			continue
		# Wall test: tall + at least one short axis (thickness).
		var bm: BoxMesh = mi.mesh
		if bm.size.y < 1.5:
			continue
		if mini(bm.size.x, bm.size.z) > 1.5:
			continue  # too thick to be a wall — skip pillars / wide blocks
		# Compose the body's global transform with the mesh-instance local,
		# then bake the BoxMesh size into a scale on the basis so the
		# shared math in _spawn_overlay_for_wall doesn't have to special-
		# case BoxMesh-sized vs scaled-unit-box meshes.
		var world_xform := body.global_transform * mi.transform
		world_xform.basis = world_xform.basis.scaled(bm.size)
		if _spawn_overlay_for_wall(world_xform):
			count += 1
	return count


# Given a wall's world Transform3D (basis encodes size_x, wall_height,
# size_z; origin is the wall center), spawn a thin cyan overlay quad
# in front of one of the wall's wide faces. The wider horizontal axis
# (x or z) determines which way the wall runs; the SHORTER axis is the
# thickness, and the quad's outward normal is along that thinner axis.
# Returns true if a quad was spawned.
func _spawn_overlay_for_wall(xform: Transform3D) -> bool:
	var size_x: float = xform.basis.x.length()
	var size_y: float = xform.basis.y.length()
	var size_z: float = xform.basis.z.length()
	if size_y < 1.5:
		return false
	# Wide face axis: whichever horizontal direction has the longer extent.
	# Thickness axis is the shorter horizontal direction. Wide face NORMAL
	# is along the thickness axis (perpendicular to the long axis).
	var face_dir: Vector3
	var face_width: float
	if size_x < size_z:
		face_dir = xform.basis.x.normalized()
		face_width = size_z
	else:
		face_dir = xform.basis.z.normalized()
		face_width = size_x
	# Quad sits the wall's thickness + a small bias out from the wall
	# center. Cull_disabled below covers both faces from one quad.
	var thickness: float = minf(size_x, size_z)
	var offset_dist: float = thickness * 0.5 + SURFACE_OFFSET
	var quad_pos: Vector3 = xform.origin + face_dir * offset_dist
	var quad_inst := MeshInstance3D.new()
	quad_inst.name = &"WallOverlay"
	var quad := QuadMesh.new()
	quad.size = Vector2(face_width, size_y)
	quad_inst.mesh = quad
	# Phase 4: shared shader material samples the SubViewport mask.
	# Where the mask is empty the shader discards, so the wall behind
	# shows through normally. Sample the WHOLE mask via local UV so
	# every overlay quad shows the Phase 2 test stamp (a centered red
	# circle) — proves the shader path works on actual walls. Phase 5
	# will switch to world-position UV so stamps land at the right
	# place.
	quad_inst.material_override = _overlay_material
	add_child(quad_inst)
	quad_inst.global_position = quad_pos
	# Orient the quad so its local +Z points along face_dir. QuadMesh's
	# default mesh sits in the XY plane with normal +Z. look_at makes
	# the node's -Z point at the target, so we look_at a point in the
	# opposite direction of face_dir.
	quad_inst.look_at(quad_pos - face_dir, Vector3.UP)
	return true


# 512² SubViewport with persistent (never-clear) render target. The
# test stamp from Phase 2 still draws into it — Phase 4 will switch
# the overlay quads to use a shader that samples this texture.
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


# Static test stamp from Phase 2 — kept for Phase 4 to sample.
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
