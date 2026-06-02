class_name WallLiquidLayer
extends LiquidLayer

## Sibling to the floor LiquidLayer for vertical surface fluids. Each
## instance owns a SubViewport mask covering one of two world axes:
##   - X_FACING: mask of (z, y) coordinates — sampled by walls whose
##     normal points along ±X (e.g. north/south walls in a level
##     aligned to world axes).
##   - Z_FACING: mask of (x, y) coordinates — sampled by walls whose
##     normal points along ±Z.
##
## The wall shader (procedural_wall.gdshader) tri-planar-samples both
## masks via global shader uniforms (wall_blood_mask_x /
## wall_blood_mask_z) weighted by abs(world_normal.x) vs
## abs(world_normal.z). One mask covers ALL walls on its axis — there's
## no per-wall infrastructure.
##
## Memory: ~4MB per layer at 2048 × 256 RGBA (vs the floor's 16MB at
## 2048²). The vertical axis is short (wall_height ≈ 4m) so the mask
## stays narrow.
##
## stamp_with_drips() emits the main splatter AND 2-3 falling drip
## sprites that paint into the mask each frame as they descend, creating
## trickle streaks via cumulative additive blending. Drip sprites slow
## asymptotically (viscous) and fade out at end of life.

enum SurfaceAxis { X_FACING, Z_FACING }

@export var surface_axis: SurfaceAxis = SurfaceAxis.X_FACING
## Vertical extent of the wall mask in world meters. Drives Y pixels-
## per-meter alongside the horizontal extent inherited from
## WORLD_EXTENT_METERS. 4m matches ctx.theme.wall_height.
@export var wall_height_meters: float = 4.0
## Horizontal pixel resolution (matches the floor mask's 2048 for a
## predictable 51.2 px/m world resolution). Vertical resolution is
## derived from wall_height_meters at the same px/m rate.
const WALL_SUBVIEWPORT_PX_X: int = 2048
const WALL_SUBVIEWPORT_PX_Y: int = 256

## Drip tuning. Per-stamp drip count scales with stamp world_radius so
## big pools shed more streaks than tiny per-hit specks. Fall speed is
## viscous-blood slow; lifetime caps total streak length around 1-1.5m.
const DRIP_MIN_COUNT: int = 0
const DRIP_MAX_COUNT: int = 3
## Stamp radius (m) below which no drips spawn. Tiny hit-spray droplets
## look wrong with streaks coming off them.
const DRIP_RADIUS_THRESHOLD: float = 0.08
const DRIP_FALL_SPEED_MIN: float = 0.18
const DRIP_FALL_SPEED_MAX: float = 0.38
const DRIP_LIFETIME_MIN: float = 2.0
const DRIP_LIFETIME_MAX: float = 3.8
## Per-frame intensity multiplier on each drip sprite. Cumulative over
## the drip lifetime; tuned so a single drip produces a faintly-visible
## trail that doesn't oversaturate where consecutive frames overlap.
const DRIP_PER_FRAME_INTENSITY: float = 0.085
## Drip sprite world radius (m). Small and round; the streak emerges
## from translation across the mask, not from sprite shape.
const DRIP_RADIUS_M: float = 0.022

# Cached white-circle texture for drip sprites — radial alpha falloff
# so additive overlap blends cleanly between consecutive frames.
static var _drip_texture: ImageTexture = null


# Class-level so both X_FACING and Z_FACING instances agree on the
# shared `wall_blood_age` global. Reset to 0 on any stamp; ticked once
# per frame by whichever layer wins the "first to register" race.
# Avoids double-incrementing when both layers run their _process.
static var _shared_wall_dry_timer: float = 999.0
static var _shared_ticker_id: int = 0


func _ready() -> void:
	add_to_group(&"wall_liquid_layer")
	add_to_group(StringName("wall_liquid_layer:" + String(fluid_id)))
	_build_subviewport()
	_publish_global_uniform()
	if _shared_ticker_id == 0:
		_shared_ticker_id = get_instance_id()
		_publish_constant_globals()
	set_process(true)


# Author the static globals (colors + world extents) once. The X-facing
# layer wins the race in practice since it's instanced first in the
# level shell; both layers would otherwise write identical values.
func _publish_constant_globals() -> void:
	RenderingServer.global_shader_parameter_set(&"wall_blood_fresh_color", fresh_color)
	RenderingServer.global_shader_parameter_set(&"wall_blood_dried_color", dried_color)
	RenderingServer.global_shader_parameter_set(&"wall_blood_extent_xz", WORLD_EXTENT_METERS)
	RenderingServer.global_shader_parameter_set(&"wall_blood_extent_y", wall_height_meters)


func _process(delta: float) -> void:
	# Skip the parent's _process — its dry-timer pushes to a per-instance
	# ShaderMaterial we don't have. The shared static below handles the
	# global age uniform for both wall layers.
	if get_instance_id() == _shared_ticker_id:
		_shared_wall_dry_timer += delta
		var age: float = clampf(_shared_wall_dry_timer / dry_duration_sec, 0.0, 1.0)
		RenderingServer.global_shader_parameter_set(&"wall_blood_age", age)
	_process_drips(delta)


# Reset the shared dry timer whenever a stamp lands on either axis.
func stamp(world_pos: Vector3, stamp_texture: Texture2D, world_radius: float, intensity: float = 1.0) -> void:
	super.stamp(world_pos, stamp_texture, world_radius, intensity)
	_shared_wall_dry_timer = 0.0


# Override parent's square SubViewport with a rectangular one sized to
# the wall axis. Vertical resolution stays low because wall_height_meters
# is short — no point burning 16MB when 4MB does the job.
func _build_subviewport() -> void:
	_subviewport = SubViewport.new()
	_subviewport.size = Vector2i(WALL_SUBVIEWPORT_PX_X, WALL_SUBVIEWPORT_PX_Y)
	_subviewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.transparent_bg = true
	_subviewport.disable_3d = true
	_subviewport.audio_listener_enable_2d = false
	add_child(_subviewport)

	_camera2d = Camera2D.new()
	_camera2d.position = Vector2(
		float(WALL_SUBVIEWPORT_PX_X) * 0.5,
		float(WALL_SUBVIEWPORT_PX_Y) * 0.5,
	)
	_camera2d.zoom = Vector2.ONE
	_camera2d.enabled = true
	_subviewport.add_child(_camera2d)

	_stamp_root = Node2D.new()
	_stamp_root.name = "StampRoot"
	_subviewport.add_child(_stamp_root)


# The wall shader samples the mask via global uniforms — there's no
# floor-style PBR sample mesh on this layer. Override the parent's
# floor-mesh builder to a no-op so we don't spawn an invisible plane.
func _build_floor_mesh() -> void:
	pass


func _publish_global_uniform() -> void:
	var key: StringName = (
		&"wall_blood_mask_x"
		if surface_axis == SurfaceAxis.X_FACING
		else &"wall_blood_mask_z"
	)
	RenderingServer.global_shader_parameter_set(key, _subviewport.get_texture())


# Maps world (h, y) to viewport pixel space, where (h) is the wall's
# horizontal axis (Z for X_FACING walls, X for Z_FACING walls) and (y)
# is world up. Viewport +Y goes DOWN in Godot's 2D convention, so we
# flip world Y so drip sprites moving toward +pixel_y correspond to
# falling under gravity in world space.
func _world_to_viewport_px(world_pos: Vector3) -> Vector2:
	var horizontal_world: float = (
		world_pos.z if surface_axis == SurfaceAxis.X_FACING
		else world_pos.x
	)
	var px_per_m_x: float = float(WALL_SUBVIEWPORT_PX_X) / WORLD_EXTENT_METERS
	var px_per_m_y: float = float(WALL_SUBVIEWPORT_PX_Y) / wall_height_meters
	# World y=0 (floor) → bottom of mask (viewport_y = WALL_SUBVIEWPORT_PX_Y).
	# World y=wall_height → top of mask (viewport_y = 0).
	# Then drips moving toward +pixel_y descend = correct gravity orientation.
	return Vector2(
		horizontal_world * px_per_m_x + float(WALL_SUBVIEWPORT_PX_X) * 0.5,
		(wall_height_meters - world_pos.y) * px_per_m_y,
	)


## Wall-aware stamp. Drops a splatter at impact then optionally emits
## drip sprites that fall under gravity, painting the mask each frame.
## Drips are skipped for stamps below DRIP_RADIUS_THRESHOLD (tiny
## per-hit specks look wrong with streaks).
func stamp_with_drips(world_pos: Vector3, stamp_texture: Texture2D, world_radius: float, intensity: float = 1.0) -> void:
	# Main splatter — same machinery as the parent class. Uses our
	# overridden _world_to_viewport_px so the stamp lands in the right
	# wall-axis pixel.
	stamp(world_pos, stamp_texture, world_radius, intensity)
	if world_radius < DRIP_RADIUS_THRESHOLD:
		return
	# Drip count scales with stamp size — a 0.9m corpse pool sheds more
	# streaks than a 0.15m hit-spatter speck.
	var radius_norm: float = clampf((world_radius - DRIP_RADIUS_THRESHOLD) / 0.5, 0.0, 1.0)
	var drip_count: int = int(round(lerpf(float(DRIP_MIN_COUNT), float(DRIP_MAX_COUNT), radius_norm)))
	if drip_count <= 0:
		return
	var drip_tex: Texture2D = _get_drip_texture()
	for i in drip_count:
		_spawn_drip(world_pos, world_radius, drip_tex)


# Builds one falling drip Sprite2D. The sprite scrolls toward +viewport_y
# (= world -Y) over its lifetime via process callback, painting the mask
# additively each frame. Slows asymptotically (1 - (1-t)^2 ease-out) so
# drip tails taper rather than abruptly stopping at the bottom.
func _spawn_drip(origin_world: Vector3, source_radius: float, tex: Texture2D) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.material = _make_additive_canvas_material()
	# Random scatter across the source splatter's horizontal extent.
	var scatter_h: float = randf_range(-source_radius * 0.6, source_radius * 0.6)
	var start_world: Vector3 = origin_world
	if surface_axis == SurfaceAxis.X_FACING:
		start_world.z += scatter_h
	else:
		start_world.x += scatter_h
	sprite.position = _world_to_viewport_px(start_world)
	# Scale so drip diameter = 2 * DRIP_RADIUS_M meters in pixel space.
	var px_per_m_x: float = float(WALL_SUBVIEWPORT_PX_X) / WORLD_EXTENT_METERS
	var target_px: float = DRIP_RADIUS_M * 2.0 * px_per_m_x
	var base_scale: float = target_px / float(tex.get_size().x)
	sprite.scale = Vector2(base_scale, base_scale)

	var fall_speed: float = randf_range(DRIP_FALL_SPEED_MIN, DRIP_FALL_SPEED_MAX)
	var lifetime: float = randf_range(DRIP_LIFETIME_MIN, DRIP_LIFETIME_MAX)
	var px_per_m_y: float = float(WALL_SUBVIEWPORT_PX_Y) / wall_height_meters
	var fall_distance_px: float = fall_speed * lifetime * px_per_m_y
	# Store the drip parameters on the sprite so its process callback can
	# drive position + alpha without closures over local state (closures
	# survive node free which can spam errors during scene transitions).
	sprite.set_meta(&"drip_start_y", sprite.position.y)
	sprite.set_meta(&"drip_fall_px", fall_distance_px)
	sprite.set_meta(&"drip_elapsed", 0.0)
	sprite.set_meta(&"drip_lifetime", lifetime)
	sprite.modulate = Color(1.0, 1.0, 1.0, DRIP_PER_FRAME_INTENSITY)
	_stamp_root.add_child(sprite)
	# Drive the drip's per-frame motion from the layer's own _process via
	# the active-drips list. Self-driven _process on the Sprite2D would
	# work but would add 18+ ticking nodes at peak combat.
	_active_drips.append(sprite)


# Active drip sprites currently being driven by _process_drips each frame.
# Cleared as drips finish their lifetime + queue_free.
var _active_drips: Array[Sprite2D] = []


func _process_drips(delta: float) -> void:
	if _active_drips.is_empty():
		return
	var i := 0
	while i < _active_drips.size():
		var drip: Sprite2D = _active_drips[i]
		if drip == null or not is_instance_valid(drip):
			_active_drips.remove_at(i)
			continue
		var elapsed: float = drip.get_meta(&"drip_elapsed", 0.0) + delta
		var lifetime: float = drip.get_meta(&"drip_lifetime", 1.0)
		if elapsed >= lifetime:
			drip.queue_free()
			_active_drips.remove_at(i)
			continue
		drip.set_meta(&"drip_elapsed", elapsed)
		# Ease-out: drip slows toward the bottom, taking longest near the
		# end of its life (matches a viscous streak losing momentum).
		var t: float = elapsed / lifetime
		var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
		var start_y: float = drip.get_meta(&"drip_start_y", 0.0)
		var fall_px: float = drip.get_meta(&"drip_fall_px", 0.0)
		drip.position.y = start_y + eased * fall_px
		# Fade out near end of life so the streak tip tapers off.
		var alpha_falloff: float = clampf((lifetime - elapsed) / 0.6, 0.0, 1.0)
		drip.modulate = Color(1.0, 1.0, 1.0, DRIP_PER_FRAME_INTENSITY * alpha_falloff)
		# Restart the layer's dry timer each frame any drip is active so
		# the fresh→dried gradient doesn't tick forward while blood is
		# still actively falling onto the wall.
		_time_since_last_stamp = 0.0
		i += 1


static func _get_drip_texture() -> ImageTexture:
	if _drip_texture != null:
		return _drip_texture
	# 32×32 radial-gradient circle. Soft alpha edge so consecutive-frame
	# overlaps blend rather than producing hard-edged staircases.
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var dx: float = float(x - 16)
			var dy: float = float(y - 16)
			var dist: float = sqrt(dx * dx + dy * dy) / 14.0
			var a: float = clampf(1.0 - dist, 0.0, 1.0)
			a = a * a  # square the falloff for a tighter bright core
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_drip_texture = ImageTexture.create_from_image(img)
	return _drip_texture
