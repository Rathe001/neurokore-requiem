class_name LiquidLayer
extends Node3D

## Persistent render-to-texture liquid renderer. Stores a 2D coverage
## mask in a SubViewport (clear_mode = NEVER, so stamps accumulate
## across frames). A floor MeshInstance3D samples that mask via the
## liquid_surface shader to render the visible PBR liquid surface.
##
## One LiquidLayer per fluid type — blood, oil, water, etc. each get
## their own SubViewport + floor mesh. Per-fluid look is driven by the
## shader uniforms set in setup().
##
## API: call stamp(world_pos, stamp_texture, world_radius, intensity)
## from gameplay code whenever a new bit of liquid lands somewhere.
## The stamp lives for one frame, gets drawn into the SubViewport,
## then queue_frees. The mask retains the result.
##
## Coordinate space: the SubViewport's 2D world uses 1 unit = 1 meter
## (PIXELS_PER_METER controls SubViewport resolution per world meter).
## Camera2D is centered at (0, 0), covering WORLD_EXTENT_METERS² area
## with the floor mesh sized + positioned to match. Stamps outside the
## extent are clamped to the edge (not lost — they'll just compress).

# How much world area one LiquidLayer covers. 40m × 40m is large enough
# for typical procgen rooms while keeping the SubViewport memory cost
# modest (16 MB per fluid type at 2048² RGBA).
# Was 40 — too small for procgen levels. Once the player walked into
# a room more than ~20m from world origin, stamps landed outside the
# mask and pools silently dropped. 100m covers the bulk of typical
# 25-40 room procgen layouts. Precision drops from ~51 px/m to
# ~20 px/m, which is still crisp for blood pools (a 1.5m pool is
# ~60 pixels diameter).
const WORLD_EXTENT_METERS: float = 100.0
# Was 2048 — at the 100m extent that's ~20 px/m which shows pixel
# grid distinctly under the current iso zoom (~5cm per mask pixel,
# ~10 screen pixels per mask pixel). 4096 doubles linear resolution
# to ~40 px/m (~2.4cm per pixel), making pool edges look smooth
# rather than blocky. Memory cost: 64MB single-channel (was 16MB) —
# fine on the 8GB target.
const SUBVIEWPORT_PX: int = 4096
const PIXELS_PER_METER: float = float(SUBVIEWPORT_PX) / WORLD_EXTENT_METERS

# Vertical offset above floor — high enough that micro Z-fighting with
# the floor mesh doesn't flicker, low enough that the liquid layer
# reads as physically on the ground.
const FLOOR_Y_OFFSET: float = 0.015

# The canonical fluid identifier. Must match the `blood_type` StringName
# on any enemy whose stamps should land here, AND the `fluid_id` arg
# callers pass to spawn_fluid_footprint / find_for. Naming convention:
# short single-token keys (&"human", &"cyborg", &"machine", &"oil",
# &"water"). Don't prefix with "blood_" — those keys are shared between
# blood and non-blood fluids.
@export var fluid_id: StringName = &"human"
# Density-gradient colors (drive the shader's thin→dense ramp).
#   fresh_color  = THIN/edge tint  (pinkish red, translucent perimeter)
#   dried_color  = DENSE/center tint (near-black burgundy, opaque core)
# The shader interpolates between them by mask coverage, so a single
# pool reads pink-stained at the edges and dark-opaque at the core —
# matching reference photos of real pooled blood.
@export var fresh_color: Color = Color(0.14, 0.030, 0.042, 1.0)
@export var dried_color: Color = Color(0.062, 0.013, 0.020, 1.0)
# Wet pools read smooth (very low roughness) and almost flat (very low
# normal perturbation). The visual interest comes from coverage shape
# variation and lighting hitting the slick surface, not from a bumpy
# noise normal — that gave a wrong "raw tissue" look.
@export var roughness: float = 0.22
@export var normal_strength: float = 0.08
# Time from fresh to fully dried. Drives the shader's age uniform via
# a process tick (linear ramp from 0 to 1 over this duration after
# the most recent stamp). Reset whenever a new stamp lands.
@export var dry_duration_sec: float = 120.0

var _subviewport: SubViewport
var _floor_mesh: MeshInstance3D
var _shader_material: ShaderMaterial
var _camera2d: Camera2D
var _stamp_root: Node2D
# Tracks time since the last stamp so the shader's `age` uniform can
# ramp 0 → 1 as the most recent splatter dries. Per-stamp aging would
# need a richer mask encoding (Phase 2).
var _time_since_last_stamp: float = 0.0


func _ready() -> void:
	add_to_group(&"liquid_layer")
	add_to_group(StringName("liquid_layer:" + String(fluid_id)))
	_build_subviewport()
	_build_floor_mesh()
	# Re-center the mask + floor mesh over the actual level's centroid
	# after LevelBuilder finishes. The 100m coverage stays the same, but
	# its center moves from world (0,0) to wherever the level is. Without
	# this, levels whose rooms extend past ±50m from origin had stamps
	# silently dropping outside the mask — visible as pools "stop
	# spawning" once the player walked far enough.
	_hook_level_builder()
	set_process(true)


func _hook_level_builder() -> void:
	if get_parent() == null:
		return
	var builder := get_parent().get_node_or_null(^"LevelBuilder")
	if builder == null:
		return
	if builder.has_signal(&"built"):
		builder.built.connect(_on_level_built)


# Compute the centroid of all level structures and re-center the layer
# there. Also forces a one-frame clear so any previous stamps (from a
# prior level) get wiped from the persistent mask.
func _on_level_built() -> void:
	var aabb := AABB()
	var first := true
	for n in get_tree().get_nodes_in_group(&"structures"):
		if not (n is Node3D):
			continue
		var n3 := n as Node3D
		if not n3.is_inside_tree():
			continue
		if first:
			aabb = AABB(n3.global_position, Vector3.ZERO)
			first = false
		else:
			aabb = aabb.expand(n3.global_position)
	if first:
		return  # no structures found — keep default origin
	var center := aabb.position + aabb.size * 0.5
	_world_origin = Vector3(center.x, 0.0, center.z)
	if _floor_mesh != null:
		_floor_mesh.position = Vector3(_world_origin.x, FLOOR_Y_OFFSET, _world_origin.z)
	# Wipe the mask: ONCE clears on the next render then reverts to NEVER
	# so subsequent stamps accumulate as usual. Important on level
	# transitions when the same LiquidLayer instance is reused with a
	# different _world_origin — old stamps would otherwise show up at
	# the wrong world position relative to the new origin.
	# Pair with UPDATE_ONCE so the viewport actually renders (and thus
	# applies the clear) — the baseline is UPDATE_DISABLED.
	if _subviewport != null:
		_subviewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
		_subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE


# Layer's center in world space. Set by _on_level_built; default (0,0,0)
# for test scenes that don't have a LevelBuilder.
var _world_origin: Vector3 = Vector3.ZERO


func _process(delta: float) -> void:
	_time_since_last_stamp += delta
	var age: float = clampf(_time_since_last_stamp / dry_duration_sec, 0.0, 1.0)
	if _shader_material != null:
		_shader_material.set_shader_parameter(&"age", age)


# ── Lookup helpers ──────────────────────────────────────────────────────────


## Single source of truth for "find the LiquidLayer that handles a
## given fluid_id". Every blood-spawn call site routes through this —
## hides the group-naming convention and surfaces missing-layer cases
## as a one-time warning instead of silently dropping the stamp.
##
## Falls back to "any LiquidLayer" if the fluid-specific one isn't in
## the scene. The fallback exists so dev scenes that only instance the
## default human-blood layer don't drop cyborg-enemy stamps entirely —
## but a warning fires once per (fluid_id, fallback) pair so the gap
## is visible during development.
static func find_for(tree: SceneTree, fluid_id: StringName) -> LiquidLayer:
	if tree == null:
		return null
	var group: StringName = StringName("liquid_layer:" + String(fluid_id))
	var layer := tree.get_first_node_in_group(group) as LiquidLayer
	if layer != null:
		return layer
	# Fallback: any liquid layer. Used by test scenes that instance only
	# the default human-blood layer.
	layer = tree.get_first_node_in_group(&"liquid_layer") as LiquidLayer
	if layer != null and not _warned_fallback.has(fluid_id):
		push_warning("[LiquidLayer] No layer for fluid_id=%s; falling back to %s. Add a LiquidLayer instance with that fluid_id to remove this warning." % [String(fluid_id), String(layer.fluid_id)])
		_warned_fallback[fluid_id] = true
	return layer


# Tracks which fluid_ids have already logged a fallback warning so we
# don't spam the same message on every kill.
static var _warned_fallback: Dictionary = {}


# ── Public API ──────────────────────────────────────────────────────────────


## Stamp a soft alpha blob onto the coverage mask at world (x, z) with
## the given world radius. The stamp's alpha is its intensity; overlap
## with existing stamps accumulates additively, producing seamless
## merged shapes.
##
## stamp_texture should have soft circular alpha falloff (radial
## gradient). intensity multiplies the stamp's alpha — use <1.0 for
## faint splatters, 1.0 for full pools.
func stamp(world_pos: Vector3, stamp_texture: Texture2D, world_radius: float, intensity: float = 1.0) -> void:
	if _stamp_root == null or stamp_texture == null:
		return
	# Restart the dry timer — the freshest pool drives the global age.
	_time_since_last_stamp = 0.0

	var sprite := Sprite2D.new()
	sprite.texture = stamp_texture
	sprite.modulate = Color(1.0, 1.0, 1.0, intensity)
	# Explicit world → viewport-pixel conversion. Camera2D is at zoom
	# 1.0 (no scaling), so sprite.position is interpreted directly in
	# viewport pixels and the world-space mapping is one we control.
	sprite.position = _world_to_viewport_px(world_pos)
	# Scale the texture so its diameter is (2 * world_radius * PIXELS_PER_METER)
	# pixels in the viewport. Per-axis aspect jitter makes each stamp
	# oblong rather than perfect-circle, hiding the round texture
	# silhouette when multiple stamps overlap.
	var tex_size: Vector2 = stamp_texture.get_size()
	if tex_size.x > 0.0:
		var target_px: float = world_radius * 2.0 * PIXELS_PER_METER
		var base_scale: float = target_px / tex_size.x
		var aspect_x: float = randf_range(0.85, 1.20)
		var aspect_y: float = randf_range(0.85, 1.20)
		sprite.scale = Vector2(base_scale * aspect_x, base_scale * aspect_y)
	# Make sure additive blending is on so overlapping stamps sum.
	sprite.material = _make_additive_canvas_material()
	# Random rotation for organic variation between stamps.
	sprite.rotation = randf() * TAU
	_stamp_root.add_child(sprite)
	_begin_render_window()
	# Sprite must outlive the SubViewport's render pass. process_frame
	# fires BEFORE the render, so a single-frame queue_free was the
	# silent-failure mode footprints hit. ~100ms covers several render
	# frames and matches the stamp_oriented pattern.
	# Memory: [[liquid-layer-stamp-lifecycle]]
	var stamp_id := sprite.get_instance_id()
	var t := get_tree().create_timer(0.1)
	t.timeout.connect(
		func() -> void:
			var s := instance_from_id(stamp_id)
			if s != null and is_instance_valid(s):
				(s as Node).queue_free()
			_end_render_window(),
		CONNECT_ONE_SHOT
	)


## Stamp an oriented (non-rotation-jittered) shape — for things that
## need to point along a specific direction like footprints, scuff
## trails, drag marks. world_size is (width, length) in metres,
## because directional stamps aren't circular. rotation_y is the
## world-space yaw the texture should be oriented to (atan2(x, z)
## from a forward vector).
##
## Backwards compatibility note: the existing stamp() does a random
## rotation + radius-only sizing for organic pool blobs. Keep using
## that for splatters; this one is for shapes whose silhouette has
## an intentional orientation.
func stamp_oriented(world_pos: Vector3, stamp_texture: Texture2D,
		world_size: Vector2, rotation_y: float, intensity: float = 1.0) -> void:
	if _stamp_root == null or stamp_texture == null:
		return
	_time_since_last_stamp = 0.0
	var sprite := Sprite2D.new()
	sprite.texture = stamp_texture
	sprite.modulate = Color(1.0, 1.0, 1.0, intensity)
	sprite.position = _world_to_viewport_px(world_pos)
	var tex_size: Vector2 = stamp_texture.get_size()
	if tex_size.x > 0.0 and tex_size.y > 0.0 \
			and world_size.x > 0.0 and world_size.y > 0.0:
		sprite.scale = Vector2(
			(world_size.x * PIXELS_PER_METER) / tex_size.x,
			(world_size.y * PIXELS_PER_METER) / tex_size.y,
		)
	sprite.material = _make_additive_canvas_material()
	# Negate so a +Y world-rotation (counter-clockwise looking down)
	# matches a CCW 2D rotation in the viewport's pixel space.
	sprite.rotation = -rotation_y
	_stamp_root.add_child(sprite)
	_begin_render_window()
	# Keep the sprite alive long enough for the SubViewport to render
	# at least one full frame with it in the tree. process_frame fires
	# BEFORE rendering, so a single-frame queue_free could discard the
	# sprite before its render pass — that was the silent failure mode
	# that made footprints invisible. ~100ms covers a few render frames
	# without leaving sprites accumulating in the tree.
	var stamp_id := sprite.get_instance_id()
	var t := get_tree().create_timer(0.1)
	t.timeout.connect(
		func() -> void:
			var s := instance_from_id(stamp_id)
			if s != null and is_instance_valid(s):
				(s as Node).queue_free()
			_end_render_window(),
		CONNECT_ONE_SHOT,
	)


## Smoothly-expanding stamp. Spawns ONE Sprite2D that tweens its scale
## from start_radius → end_radius over `duration` seconds. Because the
## SubViewport uses CLEAR_MODE_NEVER + additive blend, every frame
## paints the current size on top of the previous frame's content —
## cumulative footprint grows organically without the step-jumps a
## series of discrete stamps would produce.
func stamp_growing(world_pos: Vector3, stamp_texture: Texture2D, start_radius: float, end_radius: float, duration: float, intensity: float = 1.0) -> void:
	if _stamp_root == null or stamp_texture == null:
		return
	_time_since_last_stamp = 0.0
	var sprite := Sprite2D.new()
	sprite.texture = stamp_texture
	# Per-frame alpha is low — cumulative draws across the duration
	# build up to a saturated value at the center, with newer outer
	# pixels (only touched in later frames) ending lighter. Matches
	# the natural look of blood seeping outward.
	# Per-frame alpha + a per-stamp variance multiplier so different
	# pools accumulate to different darkness — some heavy/dark, some
	# thinner/lighter. Breaks the "every pool looks identical" read.
	var intensity_jitter: float = randf_range(0.65, 1.35)
	sprite.modulate = Color(1.0, 1.0, 1.0, intensity * 0.11 * intensity_jitter)
	sprite.position = _world_to_viewport_px(world_pos)
	sprite.material = _make_additive_canvas_material()
	sprite.rotation = randf() * TAU
	var tex_size: Vector2 = stamp_texture.get_size()
	if tex_size.x <= 0.0:
		sprite.queue_free()
		return
	var start_scale: float = (start_radius * 2.0 * PIXELS_PER_METER) / tex_size.x
	var end_scale: float = (end_radius * 2.0 * PIXELS_PER_METER) / tex_size.x
	# Per-stamp aspect-ratio jitter so pools aren't all perfectly
	# round. One axis stretched (1.0-1.55×) while the perpendicular
	# axis stays at base scale — combined with the random rotation
	# above, produces elongated oval pools at random angles. Mimics
	# how real spilled blood takes elongated shapes from body
	# position / surface tilt rather than ideal circles.
	var stretch_axis_long: float = randf_range(1.0, 1.55)
	var stretch_axis_short: float = randf_range(0.75, 1.0)
	sprite.scale = Vector2(start_scale * stretch_axis_long, start_scale * stretch_axis_short)
	_stamp_root.add_child(sprite)
	_begin_render_window()
	# Ease-out so the pool grows fast at first, then slows — matches
	# the viscous bleed-out curve of the old Decal3D tween system.
	var tween := sprite.create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, ^"scale",
		Vector2(end_scale * stretch_axis_long, end_scale * stretch_axis_short),
		duration)
	tween.tween_callback(sprite.queue_free)
	tween.tween_callback(_end_render_window)


# world (x, z) → viewport pixel (px, py). The viewport's pixel-(0, 0)
# is the top-left, so we offset by half the viewport size to put the
# layer's `_world_origin` at the viewport center. Subtracting
# `_world_origin` first means levels whose centroids aren't at world
# (0, 0) still have their full coverage area inside the mask — they
# don't lose stamps to clipping just because the level builder placed
# the rooms far from origin.
func _world_to_viewport_px(world_pos: Vector3) -> Vector2:
	var half: float = float(SUBVIEWPORT_PX) * 0.5
	return Vector2(
		(world_pos.x - _world_origin.x) * PIXELS_PER_METER + half,
		(world_pos.z - _world_origin.z) * PIXELS_PER_METER + half,
	)


# ── Internals ───────────────────────────────────────────────────────────────


# Count of stamps currently alive in the StampRoot. When > 0 we keep
# the SubViewport rendering; when 0 we let it idle. Every stamp call
# bumps this on entry and decrements on cleanup. Counter (not bool)
# because stamps overlap freely — a tween-driven stamp_growing pool
# can be live while per-hit droplets land on top of it.
var _active_stamp_count: int = 0


# Pair with _end_render_window — must call exactly once per stamp.
# Idempotent in the sense that if multiple stamps are alive, only the
# first flip to UPDATE_ALWAYS matters; the rest just bump the counter.
func _begin_render_window() -> void:
	if _subviewport == null:
		return
	_active_stamp_count += 1
	if _active_stamp_count == 1:
		_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS


# Pair with _begin_render_window. When the last stamp finishes the
# viewport stops rendering — the mask is persistent (CLEAR_MODE_NEVER)
# so the accumulated coverage stays visible.
func _end_render_window() -> void:
	if _subviewport == null:
		return
	_active_stamp_count = maxi(_active_stamp_count - 1, 0)
	if _active_stamp_count == 0:
		_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _build_subviewport() -> void:
	_subviewport = SubViewport.new()
	_subviewport.size = Vector2i(SUBVIEWPORT_PX, SUBVIEWPORT_PX)
	# NEVER = persistent across frames; stamps accumulate. ONCE would
	# clear after first draw — wrong for our use case. ALWAYS would
	# wipe every frame — also wrong.
	_subviewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	# UPDATE_DISABLED baseline — every frame of UPDATE_ALWAYS on a 4096²
	# render target burned ~1 GB/s fillrate even with zero active
	# stamps. _begin/_end_render_window flip UPDATE_ALWAYS on only
	# while stamps are alive in the tree.
	_subviewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Transparent BG = alpha 0 where nothing has been drawn.
	_subviewport.transparent_bg = true
	# No 3D, no audio listener — pure 2D compositor.
	_subviewport.disable_3d = true
	_subviewport.audio_listener_enable_2d = false
	add_child(_subviewport)

	_camera2d = Camera2D.new()
	# Camera centered on the viewport center (= world origin after
	# _world_to_viewport_px offset). zoom = 1.0 so sprite.position
	# values flow through unscaled — we do the world→pixel math
	# ourselves in _world_to_viewport_px for predictability.
	_camera2d.position = Vector2(float(SUBVIEWPORT_PX) * 0.5, float(SUBVIEWPORT_PX) * 0.5)
	_camera2d.zoom = Vector2.ONE
	_camera2d.enabled = true
	_subviewport.add_child(_camera2d)

	_stamp_root = Node2D.new()
	_stamp_root.name = "StampRoot"
	_subviewport.add_child(_stamp_root)


func _build_floor_mesh() -> void:
	_floor_mesh = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WORLD_EXTENT_METERS, WORLD_EXTENT_METERS)
	_floor_mesh.mesh = plane
	_floor_mesh.position = Vector3(0.0, FLOOR_Y_OFFSET, 0.0)
	# Cast no shadows — the liquid layer is decorative and shouldn't
	# affect scene lighting.
	_floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Disable GI participation. With default GI_MODE_STATIC, the red
	# blood albedo can feed back into SDFGI bounces (when SDFGI is on)
	# and brighten the pool through its own indirect contribution.
	# Also keeps the liquid layer out of any future GI baking pass.
	_floor_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED

	_shader_material = ShaderMaterial.new()
	_shader_material.shader = preload("res://shaders/liquid_surface.gdshader")
	# Push the floor liquid behind other transparent geometry. The
	# 40x40m plane was sorting AFTER Label3D item labels because its
	# AABB center is far from camera, but with depth_draw_never the
	# plane then alpha-painted over the already-rendered labels.
	# render_priority -10 forces it to draw FIRST so labels overlay
	# on top.
	_shader_material.render_priority = -10
	_shader_material.set_shader_parameter(&"liquid_mask", _subviewport.get_texture())
	_shader_material.set_shader_parameter(&"surface_noise", _ensure_noise_texture())
	_shader_material.set_shader_parameter(&"shape_noise", _ensure_shape_noise_texture())
	_shader_material.set_shader_parameter(&"fresh_color", fresh_color)
	_shader_material.set_shader_parameter(&"dried_color", dried_color)
	_shader_material.set_shader_parameter(&"roughness", roughness)
	_shader_material.set_shader_parameter(&"normal_strength", normal_strength)
	_shader_material.set_shader_parameter(&"age", 0.0)
	_floor_mesh.material_override = _shader_material
	add_child(_floor_mesh)


# A shared white-noise texture used by every liquid layer's shader.
# Generated once on first request and cached.
static var _noise_texture: Texture2D = null
static func _ensure_noise_texture() -> Texture2D:
	if _noise_texture != null:
		return _noise_texture
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.04
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	noise_tex.as_normal_map = true
	_noise_texture = noise_tex
	return _noise_texture


# Separate raw (non-normalmap) noise used by the shader's density
# modulation. Low frequency + few octaves so the modulation pattern
# reads as large organic patches breaking up the edge silhouette,
# not as a stippled spray of dots inside the pool.
static var _shape_noise_texture: Texture2D = null
static func _ensure_shape_noise_texture() -> Texture2D:
	if _shape_noise_texture != null:
		return _shape_noise_texture
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.03
	noise.fractal_octaves = 2
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.width = 256
	noise_tex.height = 256
	noise_tex.seamless = true
	_shape_noise_texture = noise_tex
	return _shape_noise_texture


# CanvasItemMaterial set to additive blend so overlapping stamps sum
# in the mask rather than over-paint.
static var _additive_canvas_material: CanvasItemMaterial = null
static func _make_additive_canvas_material() -> CanvasItemMaterial:
	if _additive_canvas_material != null:
		return _additive_canvas_material
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_additive_canvas_material = mat
	return _additive_canvas_material
