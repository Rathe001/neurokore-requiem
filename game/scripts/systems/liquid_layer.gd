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
@export var fresh_color: Color = Color(0.62, 0.04, 0.04, 1.0)
@export var dried_color: Color = Color(0.28, 0.08, 0.08, 1.0)
@export var roughness: float = 0.32
@export var normal_strength: float = 0.45
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
	# Position in SubViewport 2D space (1 unit = 1 meter). Use world
	# X + Z; Y is the vertical axis and doesn't map to the floor plane.
	sprite.position = Vector2(world_pos.x, world_pos.z)
	# Scale the texture so its diameter renders as `2 * world_radius`
	# meters in the SubViewport. Sprite2D.scale = world_size / texture_pixels.
	var tex_size: Vector2 = stamp_texture.get_size()
	if tex_size.x > 0.0:
		sprite.scale = Vector2.ONE * (world_radius * 2.0 / tex_size.x)
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
	# Camera position (0, 0) in 2D centers the visible area at world
	# origin. zoom = PIXELS_PER_METER means 1 world meter → that many
	# pixels in the SubViewport.
	_camera2d.position = Vector2.ZERO
	_camera2d.zoom = Vector2(PIXELS_PER_METER, PIXELS_PER_METER)
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
