class_name WallLiquidLayer
extends Node3D

## Wall blood overlay system — Phase 3 (wall enumeration + quad spawning).
##
## Architecture: overlay quads as children of THIS node, sampling a
## persistent SubViewport mask that's also a child of THIS node. Same
## subtree → ViewportTexture references resolve reliably.
##
## Phase 5: world-position UV mapping. Two SubViewport masks now — one
## for ±X-facing walls (indexed by world (z, y)), one for ±Z-facing
## walls (indexed by world (x, y)). The shader picks the appropriate
## mask based on the wall's world normal. A stamp at world (x, y, z)
## thus shows on exactly the wall at that position with a fixed world-
## size shape — long walls don't stretch the stamp anymore.
##
## Phase 6 will wire spawn_blood_wall_splatter / _spawn_mist_drop_wall
## to route through this layer instead of the legacy Decal3D path.
## Drips / multiply-stain come after.

# Mask resolution — rectangular because the world Y range (wall_height,
# ~3-4m) is much shorter than the X/Z range (~40m). Same px/m density
# on both axes (~51 px/m at 40m horizontal extent, ~64 px/m at 4m
# vertical) without wasting memory on a square viewport.
const MASK_PX_X: int = 2048
const MASK_PX_Y: int = 256
# World extents covered by the mask. Stamps outside this range clamp
# to the edge of the mask (won't be lost — just compressed).
const WORLD_EXTENT_XZ: float = 40.0
const WALL_HEIGHT_M: float = 4.0
# Distance from wall surface to overlay quad — small enough to read
# as "on" the wall, big enough to avoid z-fighting with the wall mesh.
const SURFACE_OFFSET: float = 0.005

# Two SubViewports — one for ±X-facing walls, one for ±Z-facing.
# Stamp routing picks one based on impact normal; shader sampling picks
# one based on wall's world normal.
var _mask_x_viewport: SubViewport
var _mask_z_viewport: SubViewport
var _mask_x_stamp_root: Node2D
var _mask_z_stamp_root: Node2D
# Shared ShaderMaterial bound to every overlay quad. Both mask textures
# are bound here; the shader picks at sample time.
var _overlay_material: ShaderMaterial


func _ready() -> void:
	add_to_group(&"wall_liquid_layer")
	_mask_x_viewport = _build_mask_viewport()
	_mask_z_viewport = _build_mask_viewport()
	_mask_x_stamp_root = _mask_x_viewport.get_node(^"StampRoot")
	_mask_z_stamp_root = _mask_z_viewport.get_node(^"StampRoot")
	_build_overlay_material()
	_draw_test_stamps()
	_hook_level_builder()


# Builds one rectangular SubViewport configured for persistent (never-
# clear) accumulation. Used twice — one for each axis mask.
func _build_mask_viewport() -> SubViewport:
	var sv := SubViewport.new()
	sv.size = Vector2i(MASK_PX_X, MASK_PX_Y)
	sv.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.transparent_bg = true
	sv.disable_3d = true
	sv.audio_listener_enable_2d = false
	add_child(sv)
	var cam := Camera2D.new()
	cam.position = Vector2(float(MASK_PX_X) * 0.5, float(MASK_PX_Y) * 0.5)
	cam.zoom = Vector2.ONE
	cam.enabled = true
	sv.add_child(cam)
	var root := Node2D.new()
	root.name = &"StampRoot"
	sv.add_child(root)
	return sv


# Shared material samples BOTH masks; the shader picks based on the
# wall's world normal. Constants for world extents + wall height are
# pushed once at startup — they don't change at runtime.
func _build_overlay_material() -> void:
	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = preload("res://shaders/wall_blood_overlay.gdshader")
	_overlay_material.set_shader_parameter(&"mask_x", _mask_x_viewport.get_texture())
	_overlay_material.set_shader_parameter(&"mask_z", _mask_z_viewport.get_texture())
	_overlay_material.set_shader_parameter(&"world_extent_xz", WORLD_EXTENT_XZ)
	_overlay_material.set_shader_parameter(&"wall_height", WALL_HEIGHT_M)


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


# Draws one static stamp into EACH mask at world (0, wall_height/2)
# — i.e. at the center of the level horizontally and mid-height
# vertically. Only walls passing through world x=0 or z=0 at mid-
# height should show the stamp, and at a fixed ~1m physical size.
# (Walls elsewhere should stay blood-free.) Phase 6 replaces these
# debug stamps with real gameplay routing.
func _draw_test_stamps() -> void:
	var tex := _make_test_stamp_texture()
	for root in [_mask_x_stamp_root, _mask_z_stamp_root]:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		# World (0, wall_height/2) → pixel (MASK_PX_X/2, MASK_PX_Y/2).
		sprite.position = Vector2(float(MASK_PX_X) * 0.5, float(MASK_PX_Y) * 0.5)
		# Scale so the stamp's physical size is ~0.5m diameter on the
		# mask's world resolution. tex is 64px wide; 0.5m * (MASK_PX_X /
		# WORLD_EXTENT_XZ) = 0.5 * 51.2 = 25.6 px diameter target;
		# scale = 25.6 / 64 = 0.4. Both axes scaled the same so the
		# stamp stays circular in world units.
		sprite.scale = Vector2(0.4, 0.4)
		root.add_child(sprite)


# Soft-edged white circle, 64px. Reused for both mask debug stamps.
func _make_test_stamp_texture() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := float(x - 32)
			var dy := float(y - 32)
			var d := sqrt(dx * dx + dy * dy) / 28.0
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	return ImageTexture.create_from_image(img)
