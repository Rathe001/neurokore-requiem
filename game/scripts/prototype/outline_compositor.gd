extends Node

## Autoload that paints a highlight outline around any MeshInstance3D
## registered via attach(). Uses the inverted-hull material_overlay
## technique — per-mesh ShaderMaterial extrudes vertices along their
## normals and renders only the back-faces (cull_front), producing a
## visible silhouette ring at the mesh boundary.
##
## Replaces a prior SubViewport-based compositor (broke for skinned
## meshes whose parent was a Skeleton3D — duplicated MeshInstance3D's
## skin/skeleton routing didn't survive being re-parented under the
## skeleton, and the copies rendered invisibly).
##
## Public API (unchanged from prior implementation):
##   OutlineCompositor.attach(mesh, color = Color.WHITE)
##   OutlineCompositor.detach(mesh)
##   OutlineCompositor.set_color(mesh, color)
##
## Trade-offs vs the SubViewport approach:
##   + Works for skinned meshes under Skeleton3D (the failure mode that
##     broke the previous version)
##   + Far simpler — no camera mirroring, no World3D inheritance, no
##     screen-space shader pass
##   + Per-mesh material override; cost scales with N hovered/proximity
##     meshes, not full-screen
##   - No screen-space soft glow halo; the outline is the hull ring
##     itself. Bloom env can still pick up the emission boost for a
##     glow effect.
##   - Outline obeys depth — meshes behind walls are hidden (the prior
##     version did stylized x-ray hover). If we want x-ray-style
##     "outline through walls", flip the shader's depth_test off.

const OUTLINE_HULL_SHADER: Shader = preload("res://scripts/prototype/outline_hull.gdshader")

# Defaults for new outline materials. set_shader_parameter values
# overridden per-attach can still tweak these per-mesh.
const DEFAULT_OUTLINE_WIDTH: float = 0.025
const DEFAULT_EMISSION_BOOST: float = 1.5

# Source MeshInstance3D.get_instance_id() → ShaderMaterial overlay we
# installed. Used to remove cleanly on detach and to update color in
# place without re-allocating the material.
var _overlays: Dictionary = {}

func _ready() -> void:
	# Run AFTER scene cameras' _process; nothing critical here but
	# keeping the same priority as the previous compositor so callers
	# that ran after us continue to do so.
	process_priority = 100


# ── Public API ──────────────────────────────────────────────────────────────

## Apply an outline overlay to `mesh` in `color`. If `mesh` is already
## outlined, the color is updated in place — so the hover-white →
## tooltip-locked-red transition just needs another attach() call
## rather than callers tracking state.
func attach(mesh: MeshInstance3D, color: Color = Color.WHITE) -> void:
	if mesh == null or mesh.mesh == null:
		return
	var key: int = mesh.get_instance_id()
	# Already outlined → just update the color and bail.
	if _overlays.has(key):
		var existing := _overlays[key] as ShaderMaterial
		if existing != null and is_instance_valid(existing):
			existing.set_shader_parameter(&"outline_color", color)
			return
		# Stale entry — fall through to rebuild.
		_overlays.erase(key)
	var mat := ShaderMaterial.new()
	mat.shader = OUTLINE_HULL_SHADER
	mat.set_shader_parameter(&"outline_color", color)
	mat.set_shader_parameter(&"outline_width", DEFAULT_OUTLINE_WIDTH)
	mat.set_shader_parameter(&"emission_boost", DEFAULT_EMISSION_BOOST)
	mesh.material_overlay = mat
	_overlays[key] = mat


## Remove `mesh`'s outline overlay. Safe to call when `mesh` is null,
## freed, or never attached.
func detach(mesh: MeshInstance3D) -> void:
	if mesh == null:
		return
	var key: int = mesh.get_instance_id()
	if not _overlays.has(key):
		return
	_overlays.erase(key)
	if is_instance_valid(mesh):
		mesh.material_overlay = null


## Update the outline color (e.g. white → red when a tooltip is
## locked) without rebuilding the overlay. No-op if `mesh` isn't
## currently attached.
func set_color(mesh: MeshInstance3D, color: Color) -> void:
	if mesh == null:
		return
	var key: int = mesh.get_instance_id()
	if not _overlays.has(key):
		return
	var mat := _overlays[key] as ShaderMaterial
	if mat == null or not is_instance_valid(mat):
		_overlays.erase(key)
		return
	mat.set_shader_parameter(&"outline_color", color)
