extends Node

## Autoload that draws a clean screen-space silhouette outline around any
## MeshInstance3D registered via attach(). Replaces the grow-and-cull-front
## trick used previously (which showed every internal hard-normal seam on
## Mixamo character meshes as a wireframe-y mess).
##
## How it works:
##  1. A SubViewport hosts a Camera3D whose transform mirrors the main
##     viewport's 3D camera each frame.
##  2. Highlighted meshes get a runtime-spawned `OutlineCopy` sibling that
##     shares the source mesh + skin + skeleton path but renders only on
##     layer 20 (`HIGHLIGHT_LAYER_MASK`) with a flat unshaded material in
##     the highlight color. The main camera ignores layer 20; the
##     compositor camera renders ONLY layer 20.
##  3. The SubViewport's color texture (highlight colors against
##     transparent black) feeds a fullscreen TextureRect with a Sobel-ish
##     edge-detect shader. Edge pixels paint over the main viewport;
##     interior pixels stay transparent so the original mesh shows
##     through.
##
## Public API:
##   OutlineCompositor.attach(mesh, color = Color.WHITE)
##   OutlineCompositor.detach(mesh)
##   OutlineCompositor.set_color(mesh, color)
##
## The outline always renders on top of the world, even when the source
## mesh is behind a wall — the SubViewport doesn't render world
## geometry, so there's nothing to occlude with. This is the
## "stylized x-ray hover" behavior most ARPGs use (you can find a
## hovered target even when briefly obscured by cover). If we ever want
## strict z-occluded outlines, the SubViewport's camera cull_mask can
## widen to include WORLD_LAYER and the world meshes can render in
## "background" color via a per-camera material override.

const HIGHLIGHT_LAYER_BIT: int = 1 << 19  # layer 20 (0-indexed bit position)
const HIGHLIGHT_LAYER_MASK: int = HIGHLIGHT_LAYER_BIT

const OUTLINE_THICKNESS: float = 1.5
# Tune this to skip building the compositor on platforms / scenarios where
# the extra render pass isn't worth it — currently always on. The outline
# is one full-screen pass + one extra render of (typically) 1-3 small
# meshes, so cost stays well under 1ms at 1080p on average hardware.

var _subviewport: SubViewport
var _outline_cam: Camera3D
var _overlay_layer: CanvasLayer
var _overlay_rect: TextureRect

# source MeshInstance3D.get_instance_id() → MeshInstance3D outline copy
var _copies: Dictionary = {}


func _ready() -> void:
	# Run AFTER scene cameras' _process so we mirror the latest transform.
	process_priority = 100

	_subviewport = SubViewport.new()
	_subviewport.name = &"OutlineViewport"
	_subviewport.transparent_bg = true
	_subviewport.handle_input_locally = false
	_subviewport.size = Vector2i(64, 64)  # bootstrap; resized to window in _on_viewport_size_changed
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# Disable everything the highlight pass doesn't need — saves a few %.
	_subviewport.snap_2d_transforms_to_pixel = false
	_subviewport.snap_2d_vertices_to_pixel = false
	_subviewport.positional_shadow_atlas_size = 0
	# Share the main world so our outline camera can actually see the
	# scene's nodes — a separate World3D would be empty (no nodes from
	# the main scene reachable). The transparent background + flat color
	# come from the camera's environment override below, not from a
	# private World3D environment.
	#
	# `set_use_own_world_3d(false)` is the explicit default but stating
	# it makes the intent obvious: we WANT to inherit the parent
	# viewport's world.
	_subviewport.own_world_3d = false
	add_child(_subviewport)

	_outline_cam = Camera3D.new()
	_outline_cam.name = &"OutlineCamera"
	_outline_cam.current = true
	# cull_mask = layer 20 only → ONLY the outline copies render here.
	# Source meshes are on layer 2 and the world is on layer 1; both
	# stay invisible to this camera.
	_outline_cam.cull_mask = HIGHLIGHT_LAYER_MASK
	# Per-camera environment override — transparent background, no
	# ambient / fog / GI. Without this the camera would use the level's
	# Environment (the color-graded one) and tint our flat highlight
	# colors. Camera.environment overrides World3D.environment.
	var cam_env := Environment.new()
	cam_env.background_mode = Environment.BG_COLOR
	cam_env.background_color = Color(0, 0, 0, 0)
	cam_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_outline_cam.environment = cam_env
	_subviewport.add_child(_outline_cam)

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = &"OutlineOverlay"
	# Below modal UI (which sits at higher layers) but above the 3D
	# viewport's compositing.
	_overlay_layer.layer = 50
	add_child(_overlay_layer)

	_overlay_rect = TextureRect.new()
	_overlay_rect.name = &"OutlineRect"
	_overlay_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_rect.texture = _subviewport.get_texture()
	_overlay_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scripts/prototype/outline_compositor.gdshader")
	mat.set_shader_parameter(&"outline_thickness", OUTLINE_THICKNESS)
	_overlay_rect.material = mat
	_overlay_layer.add_child(_overlay_rect)

	get_tree().root.size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()


func _process(_delta: float) -> void:
	var main_cam: Camera3D = get_viewport().get_camera_3d()
	if main_cam == null:
		return
	# Strip the highlight layer from the main camera's cull_mask so the
	# outline copy meshes render ONLY in our SubViewport. Without this
	# the main camera also sees the flat-white copy and the enemy reads
	# as a fully-filled silhouette in the world view — defeating the
	# "outline only" intent. Bitwise idempotent so we can re-run every
	# frame without flicker.
	if (main_cam.cull_mask & HIGHLIGHT_LAYER_MASK) != 0:
		main_cam.cull_mask &= ~HIGHLIGHT_LAYER_MASK
	_outline_cam.global_transform = main_cam.global_transform
	_outline_cam.fov = main_cam.fov
	_outline_cam.near = main_cam.near
	_outline_cam.far = main_cam.far
	_outline_cam.projection = main_cam.projection
	if main_cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_outline_cam.size = main_cam.size
	# Prune copies whose source was freed (enemy died and pooled out, etc.).
	_prune_stale()


func _on_viewport_size_changed() -> void:
	if _subviewport == null:
		return
	var s: Vector2i = get_tree().root.size
	# Floor at 1 to avoid zero-size viewport on minimized windows.
	_subviewport.size = Vector2i(maxi(1, s.x), maxi(1, s.y))


# ── Public API ──────────────────────────────────────────────────────────────

## Spawn an outline copy sibling for `mesh` that renders on the highlight
## layer in `color`. If `mesh` is already attached, the color is updated
## in place — so the hover-white → tooltip-locked-red transition just
## needs another attach() call rather than callers tracking state.
func attach(mesh: MeshInstance3D, color: Color = Color.WHITE) -> void:
	if mesh == null or mesh.mesh == null:
		return
	var key: int = mesh.get_instance_id()
	if _copies.has(key) and is_instance_valid(_copies[key]):
		set_color(mesh, color)
		return
	var parent: Node = mesh.get_parent()
	if parent == null:
		return
	var copy := MeshInstance3D.new()
	copy.name = &"OutlineCopy"
	copy.mesh = mesh.mesh
	# Skinned-mesh fidelity: share the same Skin resource and the same
	# `skeleton` NodePath so the copy deforms identically to the source
	# each frame. The NodePath is relative to the MeshInstance3D's own
	# position in the tree, so being a sibling of `mesh` keeps it valid.
	copy.skin = mesh.skin
	copy.skeleton = mesh.skeleton
	copy.transform = mesh.transform
	copy.layers = HIGHLIGHT_LAYER_MASK
	copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.albedo_color = color
	flat.cull_mode = BaseMaterial3D.CULL_DISABLED  # see both sides; outline reads the full silhouette
	# material_override > per-surface set_surface_override_material here —
	# the latter doubles `material_*: Parameter "material" is null` renderer
	# warnings because the SHADOW-pass query still touches the underlying
	# Mesh's surface materials (which can be null on FBX imports).
	# material_override short-circuits that path entirely.
	copy.material_override = flat
	parent.add_child(copy)
	_copies[key] = copy


## Remove the outline copy for `mesh`. Safe to call when `mesh` is null,
## freed, or never attached.
func detach(mesh: MeshInstance3D) -> void:
	if mesh == null:
		return
	var key: int = mesh.get_instance_id()
	_drop_key(key)


## Update the highlight color (e.g. white → red when a tooltip is
## locked). No-op if `mesh` isn't currently attached.
func set_color(mesh: MeshInstance3D, color: Color) -> void:
	if mesh == null:
		return
	var key: int = mesh.get_instance_id()
	if not _copies.has(key):
		return
	var copy: Node = _copies[key]
	if not is_instance_valid(copy):
		_copies.erase(key)
		return
	var mi := copy as MeshInstance3D
	if mi == null:
		return
	var m := mi.material_override
	if m is StandardMaterial3D:
		(m as StandardMaterial3D).albedo_color = color


# ── Internals ───────────────────────────────────────────────────────────────

func _drop_key(key: int) -> void:
	if not _copies.has(key):
		return
	var copy: Node = _copies[key]
	_copies.erase(key)
	if is_instance_valid(copy):
		copy.queue_free()


# Per-frame cleanup — sources can vanish without an explicit detach()
# (enemy dies and EntityPool reclaims the body, level reload, etc.). Walk
# the copies dict and prune any whose source `instance_id` no longer
# resolves to a live Object.
func _prune_stale() -> void:
	if _copies.is_empty():
		return
	var dead_keys: Array[int] = []
	for key: int in _copies.keys():
		if instance_from_id(key) == null:
			dead_keys.append(key)
	for key in dead_keys:
		_drop_key(key)
