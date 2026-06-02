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
const WORLD_EXTENT_METERS: float = 40.0
const SUBVIEWPORT_PX: int = 2048
const PIXELS_PER_METER: float = float(SUBVIEWPORT_PX) / WORLD_EXTENT_METERS

# Vertical offset above floor — high enough that micro Z-fighting with
# the floor mesh doesn't flicker, low enough that the liquid layer
# reads as physically on the ground.
const FLOOR_Y_OFFSET: float = 0.015

@export var fluid_id: StringName = &"blood_human"
# Density-gradient colors (drive the shader's thin→dense ramp).
#   fresh_color  = THIN/edge tint  (pinkish red, translucent perimeter)
#   dried_color  = DENSE/center tint (near-black burgundy, opaque core)
# The shader interpolates between them by mask coverage, so a single
# pool reads pink-stained at the edges and dark-opaque at the core —
# matching reference photos of real pooled blood.
@export var fresh_color: Color = Color(0.55, 0.15, 0.16, 1.0)
@export var dried_color: Color = Color(0.08, 0.02, 0.03, 1.0)
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
	set_process(true)


func _process(delta: float) -> void:
	_time_since_last_stamp += delta
	var age: float = clampf(_time_since_last_stamp / dry_duration_sec, 0.0, 1.0)
	if _shader_material != null:
		_shader_material.set_shader_parameter(&"age", age)


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
	# Stamp persists exactly one frame — it draws into the SubViewport's
	# persistent render target, then we free the Sprite2D. The mask
	# keeps the rasterized pixels.
	var stamp_id := sprite.get_instance_id()
	get_tree().process_frame.connect(
		func() -> void:
			var s := instance_from_id(stamp_id)
			if s != null and is_instance_valid(s):
				(s as Node).queue_free(),
		CONNECT_ONE_SHOT
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
	sprite.scale = Vector2(start_scale, start_scale)
	_stamp_root.add_child(sprite)
	# Ease-out so the pool grows fast at first, then slows — matches
	# the viscous bleed-out curve of the old Decal3D tween system.
	var tween := sprite.create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, ^"scale", Vector2(end_scale, end_scale), duration)
	tween.tween_callback(sprite.queue_free)


# world (x, z) → viewport pixel (px, py). The viewport's pixel-(0, 0)
# is the top-left, so we offset by half the viewport size to put world
# (0, 0) at the viewport center.
func _world_to_viewport_px(world_pos: Vector3) -> Vector2:
	var half: float = float(SUBVIEWPORT_PX) * 0.5
	return Vector2(
		world_pos.x * PIXELS_PER_METER + half,
		world_pos.z * PIXELS_PER_METER + half,
	)


# ── Internals ───────────────────────────────────────────────────────────────


func _build_subviewport() -> void:
	_subviewport = SubViewport.new()
	_subviewport.size = Vector2i(SUBVIEWPORT_PX, SUBVIEWPORT_PX)
	# NEVER = persistent across frames; stamps accumulate. ONCE would
	# clear after first draw — wrong for our use case. ALWAYS would
	# wipe every frame — also wrong.
	_subviewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	# Once: render the first frame to clear-init the texture. After
	# that, NEVER + add_child stamps drive subsequent draws.
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
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

	_shader_material = ShaderMaterial.new()
	_shader_material.shader = preload("res://shaders/liquid_surface.gdshader")
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
