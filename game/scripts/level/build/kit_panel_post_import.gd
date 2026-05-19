@tool
extends EditorScenePostImport
## Normalizes kit-bash panel .glb assets so the level builders can assume a
## canonical axis convention regardless of how the source was authored. Saves
## per-asset manual orientation fiddling whenever a new panel is dropped in
## from Blenderkit (or any other source).
##
## Type is auto-detected from the source path:
##   - "wall_panel" in path → wall mode
##   - "floor_panel" in path → floor mode
##   - anything else → script no-ops with a warning
##
## Canonical orientations:
##   Wall:  X = length, Y = thickness, Z = height. AABB centered on origin.
##          Matches WallBuilder._add_tiled_wall_segment (height_in_y=false).
##   Floor: X = longer tile dim, Y = shorter tile dim, Z = thickness.
##          AABB centered on origin. Matches FloorBuilder.build_piece_floor_kit
##          (which then applies Basis(RIGHT,-π/2) to lay it flat).
##
## The transform is baked into the mesh vertices (positions + normals +
## tangents), so MultiMesh — which renders against the raw mesh and ignores
## any scene-graph transforms — gets a fully pre-rotated, pre-centered mesh.
## The MeshInstance3D's own transform is reset to identity.
##
## Wire-up: in the .glb.import file, set `import_script/path` to this script's
## res:// path. Re-import to apply.


func _post_import(scene: Node) -> Node:
	var src := get_source_file()
	var kit_type := _detect_kit_type(src)
	if kit_type == "":
		return scene

	var mi := _find_first_mesh_instance(scene)
	if mi == null or mi.mesh == null:
		push_warning("[kit_panel_normalizer] %s: no MeshInstance3D/mesh; skipping." % src)
		return scene

	var aabb: AABB = mi.mesh.get_aabb()
	var size := aabb.size
	var thickness_idx := _argmin_v3(size)
	var remaining := _other_two(thickness_idx)
	# Pick which non-thickness axis is "canonical X" vs "canonical Y/Z".
	# Walls:  canonical Z = the largest (height ≈ wall_height).
	#         canonical X = the remaining (length).
	# Floors: canonical X = the larger of the two non-thickness dims.
	#         canonical Y = the smaller.
	var larger_remaining := remaining[0] if size[remaining[0]] >= size[remaining[1]] else remaining[1]
	var smaller_remaining := remaining[1] if larger_remaining == remaining[0] else remaining[0]

	# Columns of the basis: each column is the canonical-space vector that the
	# source axis with that index maps onto. (Basis(x,y,z) constructor takes the
	# images of source basis vectors as its three args.)
	var cols: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	if kit_type == "wall":
		cols[smaller_remaining] = Vector3.RIGHT       # length     → canonical X
		cols[thickness_idx] = Vector3.UP              # thickness  → canonical Y
		cols[larger_remaining] = Vector3(0.0, 0.0, 1.0)  # height  → canonical Z
	else:  # floor
		cols[larger_remaining] = Vector3.RIGHT        # long tile  → canonical X
		cols[smaller_remaining] = Vector3.UP          # short tile → canonical Y
		cols[thickness_idx] = Vector3(0.0, 0.0, 1.0)  # thickness  → canonical Z

	var b := Basis(cols[0], cols[1], cols[2])
	# Right-handed enforcement: a pure axis swap can land on a reflection
	# (det = -1). Flip canonical X — mirroring along length is visually
	# neutral for symmetric panels and avoids inverting height or thickness.
	if b.determinant() < 0.0:
		b.x = -b.x

	# Translate so the AABB center lands at origin in canonical space.
	var rotated_center: Vector3 = b * (aabb.position + aabb.size * 0.5)
	var xform := Transform3D(b, -rotated_center)

	mi.mesh = _apply_transform_to_mesh(mi.mesh, xform)
	# Walls only: thicken the back half of the mesh so the panel is the
	# full wall_thickness deep in canonical Y. The front-half (decorative
	# relief) is unchanged; the back vertices get pushed out to fill the
	# corner cube when two perpendicular walls meet. Without this the kit
	# panel is ~2.5cm thick at the wall centerline and corner cubes are
	# visibly empty no matter what the build layout does.
	if kit_type == "wall":
		mi.mesh = _thicken_wall_symmetric(mi.mesh, WALL_THICKNESS_TARGET * 0.5)
	# Flatten happens AFTER the transform bake — the new AABB (centered on
	# origin in canonical orientation) is what the shader uses for its
	# half_length / half_thickness clip-plane uniforms.
	var baked_aabb: AABB = mi.mesh.get_aabb()
	_flatten_pbr_for_iso(mi.mesh, baked_aabb)
	mi.transform = Transform3D.IDENTITY
	return scene


# Converts each surface's StandardMaterial3D into a ShaderMaterial using
# kit_panel.gdshader. The shader does standard PBR via the engine's slots
# AND applies a per-instance 45° mitre clip plane (driven by
# INSTANCE_CUSTOM). Textures and tuned PBR parameters carry over.
#
# Why a custom shader and not just BaseMaterial3D's existing settings: the
# discard/clip behavior can't be expressed in BaseMaterial3D — it needs a
# fragment-stage discard tied to a per-instance flag, which only a custom
# shader provides. We keep the shader minimal (no full PBR re-implementation;
# just set the PBR slots the engine already understands).
#
# PBR tuning rationale (flattened from material defaults):
#   normal_strength  → 0.3  (relief still visible, specular glint suppressed)
#   metallic_factor  → 0.1  (no chrome highlights)
#   roughness_factor → 0.85 (broad scatter, no sharp speculars)
# Per the "tech-shader specular shimmer" memory: keep metallic/bump low +
# roughness high to suppress iso-angle Moiré on high-frequency textures.
const _KIT_PANEL_SHADER: Shader = preload("res://scripts/level/build/kit_panel.gdshader")

# 1x1 fallback textures for kit panels whose source BaseMaterial3D is
# missing a channel. The albedo_color uniform handles the colored case;
# these fallbacks just keep the sampler slots populated with a sensible
# constant so the shader can sample them unconditionally without producing
# weird normals / roughness from random data.
#
# `flat_normal` is critical: a normal map encodes the geometric normal as
# RGB(0.5, 0.5, 1.0) — sampling pure white *as a normal map* decodes to
# an extreme bogus normal direction (effectively (1, 1, undefined)) that
# manifests as a blob-shaped shading artifact on every face. A real flat
# normal sample decodes to (0, 0, 1) which is "no bump, use the geometric
# normal" — what an untextured asset actually wants.
static var _FALLBACK_WHITE: Texture2D = null
static var _FALLBACK_FLAT_NORMAL: Texture2D = null


static func _fallback_white() -> Texture2D:
	if _FALLBACK_WHITE == null:
		# Image.create() returns uninitialized memory; fill() writes every
		# pixel so the buffer is reliably white. set_pixel-only-one-pixel
		# left the rest as random GPU bytes — visible as blob noise.
		var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
		img.fill(Color.WHITE)
		_FALLBACK_WHITE = ImageTexture.create_from_image(img)
	return _FALLBACK_WHITE


static func _fallback_flat_normal() -> Texture2D:
	if _FALLBACK_FLAT_NORMAL == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
		img.fill(Color(0.5, 0.5, 1.0))
		_FALLBACK_FLAT_NORMAL = ImageTexture.create_from_image(img)
	return _FALLBACK_FLAT_NORMAL

# Target thickness (full, not half) every wall kit panel gets stretched out
# to in the canonical Y direction. Must match the active level theme's
# `wall_thickness` field — if you change wall_thickness in a theme, update
# this and re-import the kit panels. Keeping these in sync via a constant
# beats reading the theme at editor time (which would require parsing
# .tres resources from the post-import context).
const WALL_THICKNESS_TARGET: float = 0.4

static func _flatten_pbr_for_iso(mesh: Mesh, aabb: AABB) -> void:
	var half_length: float = aabb.size.x * 0.5
	var half_thickness: float = aabb.size.y * 0.5
	for surface_idx in range(mesh.get_surface_count()):
		var mat := mesh.surface_get_material(surface_idx)
		if not (mat is BaseMaterial3D):
			continue
		var bm: BaseMaterial3D = mat as BaseMaterial3D
		var sm := ShaderMaterial.new()
		sm.shader = _KIT_PANEL_SHADER
		# Copy textures off the standard material. Missing channels fall
		# through to the shader's default-white samplers — see
		# kit_panel.gdshader for the rationale. The albedo_color uniform
		# below picks up the BaseMaterial3D's color so untextured assets
		# (stylized models that only use albedo_color + mesh geometry)
		# still read the right tint.
		# Always bind every sampler. Albedo + roughness fall back to white
		# (multiplied by albedo_color / roughness_factor in the shader).
		# Normal falls back to FLAT-NORMAL (0.5, 0.5, 1.0) so it decodes
		# to "no bump" rather than an extreme bogus direction.
		var albedo_tex: Texture2D = bm.albedo_texture
		var normal_tex: Texture2D = bm.normal_texture
		var roughness_tex: Texture2D = bm.roughness_texture
		var fallback_w := _fallback_white()
		var fallback_n := _fallback_flat_normal()
		sm.set_shader_parameter(&"albedo_tex", albedo_tex if albedo_tex != null else fallback_w)
		sm.set_shader_parameter(&"normal_tex", normal_tex if normal_tex != null else fallback_n)
		sm.set_shader_parameter(&"roughness_tex", roughness_tex if roughness_tex != null else fallback_w)
		# Albedo color: source material's albedo_color. For textured assets
		# this should usually stay near (1,1,1) so the texture wins; for
		# textureless assets it's the only color signal the shader has.
		#
		# Untextured asset dark tint: stylized Blenderkit assets often ship
		# with `albedo_color = (1,1,1)` and rely on the renderer's gentle
		# default lighting to look readable. Under our ceiling fluorescents
		# (energy 4-11) that blows out to flat white. When there's no
		# texture variation to break up the light, multiply by ~0.45 so
		# the geometry's bevels and depressions read as shadow detail
		# instead of every face going to ALBEDO clamp.
		# Pass as Color, not Vector3 — Godot 4 ShaderMaterial.set_shader_parameter
		# on a `source_color`-hinted vec3 uniform appears to drop Vector3
		# values during .scn serialization (the saved parameter reads back as
		# <null>, falling through to the shader default of vec3(1.0)). A Color
		# value with the source_color hint round-trips correctly.
		var albedo := bm.albedo_color
		if albedo_tex == null:
			albedo = Color(albedo.r * 0.45, albedo.g * 0.45, albedo.b * 0.45, albedo.a)
		sm.set_shader_parameter(&"albedo_color", albedo)
		# (No has_normal_tex gate — the flat-normal fallback above does
		# the right thing without any conditional in the shader, which
		# avoids hitting the same float-uniform serialization issue we hit
		# with albedo_color.)
		sm.set_shader_parameter(&"normal_strength", 0.3)
		sm.set_shader_parameter(&"metallic_factor", 0.1)
		sm.set_shader_parameter(&"roughness_factor", 0.85)
		sm.set_shader_parameter(&"half_length", half_length)
		sm.set_shader_parameter(&"half_thickness", half_thickness)
		mesh.surface_set_material(surface_idx, sm)


# ── Helpers ───────────────────────────────────────────────────────────────

static func _detect_kit_type(path: String) -> String:
	if "wall_panel" in path:
		return "wall"
	if "floor_panel" in path:
		return "floor"
	return ""


static func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var r := _find_first_mesh_instance(child)
		if r != null:
			return r
	return null


static func _argmin_v3(v: Vector3) -> int:
	if v.x <= v.y and v.x <= v.z:
		return 0
	if v.y <= v.z:
		return 1
	return 2


static func _other_two(excluded: int) -> Array[int]:
	var out: Array[int] = []
	for i in range(3):
		if i != excluded:
			out.append(i)
	return out


# Stretches BOTH halves of a canonical-orientation wall panel outward so
# the panel spans ±target_half_thick around y = 0 (total thickness =
# wall_thickness). Decorative relief on whichever side has it gets scaled
# along with the structural back — uniform per-side stretch keeps the
# panel centered on the wall centerline.
#
# Why symmetric and not one-sided: the canonical step centers the source
# AABB on origin, so before thickening the panel spans roughly [-t, +t]
# in y. A one-sided stretch (y > 0 only) would leave the panel
# OFF-CENTER (e.g. [-0.0125, +0.2]) — and the build-time translation puts
# the AABB CENTER at the wall centerline. So the panel would only fill
# roughly HALF the wall thickness on the off-axis side, and corner cubes
# (where two perpendicular walls meet) stay empty no matter how far the
# panel extends lengthwise. Stretching both halves symmetrically keeps
# the panel's center at y = 0 AND makes it exactly wall_thickness deep,
# so corner cubes are filled and the kit_panel.gdshader's 45° mitre clip
# splits the overlap diagonally.
#
# Per-side stretch: vertices with y > 0 are scaled so the back face
# (max y) lands at +target_half_thick; vertices with y < 0 are scaled so
# the front face (min y) lands at -target_half_thick. The two factors
# may differ slightly when the source AABB isn't perfectly symmetric.
#
# Normals/tangents stay valid: scaling y axis-aligned doesn't rotate any
# surface tangent direction. The back face still points ±Y, side faces
# still point along ±X/±Z. Lighting on the stretched portion is correct.
static func _thicken_wall_symmetric(mesh: Mesh, target_half_thick: float) -> Mesh:
	var aabb := mesh.get_aabb()
	var native_top: float = aabb.position.y + aabb.size.y
	var native_bot: float = aabb.position.y
	# A vanishingly thin panel can't be stretched meaningfully; skip.
	if native_top <= 0.0001 and native_bot >= -0.0001:
		return mesh
	var stretch_pos: float = target_half_thick / maxf(native_top, 0.0001)
	var stretch_neg: float = target_half_thick / maxf(-native_bot, 0.0001)
	var new_mesh := ArrayMesh.new()
	for surface_idx in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_idx)
		if arrays[Mesh.ARRAY_VERTEX] != null:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in range(verts.size()):
				if verts[i].y > 0.0:
					verts[i].y *= stretch_pos
				elif verts[i].y < 0.0:
					verts[i].y *= stretch_neg
			arrays[Mesh.ARRAY_VERTEX] = verts
		var primitive: Mesh.PrimitiveType = mesh.surface_get_primitive_type(surface_idx)
		var material := mesh.surface_get_material(surface_idx)
		new_mesh.add_surface_from_arrays(primitive, arrays)
		new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, material)
	return new_mesh


# Bakes `xform` into a copy of the mesh: positions get full transform, normals
# and tangent directions get the rotation-only part. Returns a new ArrayMesh
# preserving primitive type and per-surface materials.
static func _apply_transform_to_mesh(mesh: Mesh, xform: Transform3D) -> ArrayMesh:
	var new_mesh := ArrayMesh.new()
	for surface_idx in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_idx)
		if arrays[Mesh.ARRAY_VERTEX] != null:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in range(verts.size()):
				verts[i] = xform * verts[i]
			arrays[Mesh.ARRAY_VERTEX] = verts
		if arrays[Mesh.ARRAY_NORMAL] != null:
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in range(normals.size()):
				normals[i] = (xform.basis * normals[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = normals
		# Tangents are stored as packed float32, 4 per vertex: (x, y, z, sign).
		# Only the xyz direction needs rotating; sign is handedness, preserved.
		if arrays[Mesh.ARRAY_TANGENT] != null:
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
			var i := 0
			while i < tangents.size():
				var t := Vector3(tangents[i], tangents[i + 1], tangents[i + 2])
				t = (xform.basis * t).normalized()
				tangents[i] = t.x
				tangents[i + 1] = t.y
				tangents[i + 2] = t.z
				i += 4
			arrays[Mesh.ARRAY_TANGENT] = tangents
		var primitive: Mesh.PrimitiveType = mesh.surface_get_primitive_type(surface_idx)
		var material := mesh.surface_get_material(surface_idx)
		new_mesh.add_surface_from_arrays(primitive, arrays)
		new_mesh.surface_set_material(new_mesh.get_surface_count() - 1, material)
	return new_mesh
