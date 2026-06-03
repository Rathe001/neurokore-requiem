class_name WallLiquidLayer
extends Node3D

## Wall blood overlay system — Phase 3 (wall enumeration + quad spawning).
##
## Architecture: overlay quads as children of THIS node, sampling a
## persistent SubViewport mask that's also a child of THIS node. Same
## subtree → ViewportTexture references resolve reliably.
##
## Phase 7: gravity-drip streaks below splatters. Each splatter over a
## minimum radius spawns 1-3 drip sprites that fall in viewport-Y space
## (= world-down) over 1.8-3.0 seconds with ease-out, painting the mask
## additively each frame. Cumulative per-frame paints form streaks from
## the impact point downward — the kind of trail blood actually leaves
## on a vertical surface. Mist drops (below the threshold) skip drips
## so per-hit specks don't all sprout streaks.

# Mask resolution — rectangular because the world Y range (wall_height,
# ~3-4m) is much shorter than the X/Z range (~40m). Same px/m density
# on both axes (~51 px/m at 40m horizontal extent, ~64 px/m at 4m
# vertical) without wasting memory on a square viewport.
const MASK_PX_X: int = 2048
const MASK_PX_Y: int = 256
# World extents covered by the mask. Stamps outside this range clamp
# to the edge of the mask (won't be lost — just compressed).
# Was 40 — same procgen-coverage bug as the floor LiquidLayer. 100m
# matches the floor extent so wall splatters and pool footprints stay
# in sync across the full level area.
const WORLD_EXTENT_XZ: float = 100.0
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

# ── Drip streak tuning ────────────────────────────────────────────
const DRIP_RADIUS_THRESHOLD: float = 0.12  # main stamp radius below this skips drips
# Cap drip vertical reach so a streak stays visually attached to its
# splatter. Previously fall_speed * lifetime could produce ~1.7m of
# fall — with the new vertical scatter on splatter positions, streaks
# ended up far below their parent splatter, reading as disconnected
# floating drips. Capping fall_distance at ~0.6m keeps the streak
# anchored to the splatter that spawned it.
# Streaks should read as LONG thin ribbons reaching well below the
# splatter (cf. reference photos — drips travel half a meter or more
# down the wall). Anchoring is preserved by the small start-offset
# (drip starts INSIDE the splatter core) + tight horizontal scatter,
# so longer fall distance doesn't break the visual connection.
const DRIP_MAX_FALL_DISTANCE_M: float = 1.8
const DRIP_LIFETIME_MIN: float = 3.0
const DRIP_LIFETIME_MAX: float = 5.5
const DRIP_FALL_SPEED_MIN: float = 0.22  # m/sec — viscous but visibly moving
const DRIP_FALL_SPEED_MAX: float = 0.42
# Thinner drip — 2.5cm radius (5cm physical width) reads more as a
# narrow ribbon than a wide tube. Per-frame intensity bumped to
# compensate so the streak still saturates.
const DRIP_RADIUS_M: float = 0.025
# Stronger vertical stretch — long ribbons rather than a stack of
# circles. Combined with the extended fall distance this gives the
# trailing-tail look from the references.
const DRIP_VERTICAL_STRETCH: float = 5.5
# Drips start at the splatter's lower edge (50% of radius below
# center). Far enough that the streak emerges from the splatter
# silhouette rather than getting buried inside it, close enough that
# the streak still visually connects to its parent splatter rather
# than floating disconnected.
const DRIP_START_OFFSET_RATIO: float = 0.1
const DRIP_PER_FRAME_INTENSITY: float = 0.18
const DRIP_COUNT_MIN: int = 2
const DRIP_COUNT_MAX: int = 4
const DRIP_FADE_TAIL_SEC: float = 0.8  # drip fades out over last N seconds

# Active drip sprites driven by _process. Each entry tracks the sprite
# plus its motion parameters so we can update position + alpha per frame.
# Cleared as drips finish their lifetime.
var _active_drips: Array[Dictionary] = []


func _ready() -> void:
	add_to_group(&"wall_liquid_layer")
	_mask_x_viewport = _build_mask_viewport()
	_mask_z_viewport = _build_mask_viewport()
	_mask_x_stamp_root = _mask_x_viewport.get_node(^"StampRoot")
	_mask_z_stamp_root = _mask_z_viewport.get_node(^"StampRoot")
	_build_overlay_material()
	_hook_level_builder()
	set_process(true)


func _process(delta: float) -> void:
	_process_drips(delta)
	_advance_age(delta)


# Drying tracker — increments while no new splatters land. Resets on
# every stamp() call so combat keeps blood looking fresh; quiet
# periods let pools dry to matte brown.
@export var dry_duration_sec: float = 120.0
var _time_since_last_stamp: float = 0.0


func _advance_age(delta: float) -> void:
	_time_since_last_stamp += delta
	var age: float = clampf(_time_since_last_stamp / dry_duration_sec, 0.0, 1.0)
	if _overlay_material != null:
		_overlay_material.set_shader_parameter(&"age", age)


# Per-frame motion + alpha-fade for every live drip. Each drip's
# position.y advances toward its end-of-life target along an ease-out
# curve (1 - (1-t)^2), so it slows as it falls — the cumulative draws
# leave a streak that tapers naturally. Alpha fades out over the last
# DRIP_FADE_TAIL_SEC so the streak tip pales rather than just stopping.
func _process_drips(delta: float) -> void:
	if _active_drips.is_empty():
		return
	var i := 0
	while i < _active_drips.size():
		var drip: Dictionary = _active_drips[i]
		var sprite: Sprite2D = drip[&"sprite"] as Sprite2D
		if sprite == null or not is_instance_valid(sprite):
			_active_drips.remove_at(i)
			continue
		var elapsed: float = drip[&"elapsed"] + delta
		var lifetime: float = drip[&"lifetime"]
		if elapsed >= lifetime:
			sprite.queue_free()
			_active_drips.remove_at(i)
			continue
		drip[&"elapsed"] = elapsed
		var t: float = elapsed / lifetime
		var eased: float = 1.0 - (1.0 - t) * (1.0 - t)
		var start_y: float = drip[&"start_y"]
		var fall_px: float = drip[&"fall_px"]
		sprite.position.y = start_y + eased * fall_px
		var fade: float = clampf((lifetime - elapsed) / DRIP_FADE_TAIL_SEC, 0.0, 1.0)
		sprite.modulate = Color(1.0, 1.0, 1.0, DRIP_PER_FRAME_INTENSITY * fade)
		i += 1


## Public API: stamp blood on a wall at the given world position. The
## wall is the one whose outward normal matches `wall_normal` (which
## axis is dominant decides which mask receives the stamp). `world_radius`
## is the stamp's physical diameter in meters. `intensity` multiplies
## alpha — overlapping stamps accumulate additively in the mask so
## consecutive hits in the same spot pool together cleanly.
func stamp(world_pos: Vector3, wall_normal: Vector3, world_radius: float, intensity: float = 1.0) -> void:
	if wall_normal.length_squared() < 0.0001:
		return
	# Reset the drying timer — fresh splatter keeps the wall blood
	# looking wet until the next quiet period.
	_time_since_last_stamp = 0.0
	var nrm := wall_normal.normalized()
	var use_x_mask: bool = absf(nrm.x) > absf(nrm.z)
	var stamp_root: Node2D = _mask_x_stamp_root if use_x_mask else _mask_z_stamp_root
	# Horizontal world coordinate for the chosen mask. For X-facing walls
	# (normal.x dominant), the wall's surface spans Z and Y → use world.z.
	# For Z-facing walls, use world.x.
	var horizontal_world: float = world_pos.z if use_x_mask else world_pos.x
	var px_per_m_h: float = float(MASK_PX_X) / WORLD_EXTENT_XZ
	var px_per_m_v: float = float(MASK_PX_Y) / WALL_HEIGHT_M
	var px := Vector2(
		horizontal_world * px_per_m_h + float(MASK_PX_X) * 0.5,
		(WALL_HEIGHT_M - world_pos.y) * px_per_m_v,
	)
	# Reuse the floor LiquidLayer's chaotic lobed splatter textures —
	# 12 cached two-octave-noise blobs with irregular perimeters.
	# Wall stamps thus share the same organic silhouette family the
	# floor uses, instead of reading as smooth circles.
	var tex: Texture2D = PrototypeEnemy._get_settle_stamp_texture()
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.position = px
	# Scale so the stamp's diameter matches world_radius * 2 in pixels.
	var diam_px: float = world_radius * 2.0 * px_per_m_h
	var base_scale: float = diam_px / float(tex.get_size().x)
	# Wall stamps get vertical-biased aspect jitter — gravity pulls
	# blood down the wall so a circular splatter reads wrong. Y axis
	# stretches 1.3-2.0× while X compresses slightly. No rotation
	# (otherwise the vertical bias points in random directions and
	# loses the gravity read).
	var aspect_x: float = randf_range(0.85, 1.10)
	var aspect_y: float = randf_range(1.30, 2.00)
	sprite.scale = Vector2(base_scale * aspect_x, base_scale * aspect_y)
	# Per-stamp intensity jitter so different splatters accumulate to
	# different darkness — matches the floor pool variance and breaks
	# the "every splatter looks identical" read.
	var intensity_jitter: float = randf_range(0.6, 1.4)
	sprite.modulate = Color(1.0, 1.0, 1.0, intensity * intensity_jitter)
	sprite.material = _get_cached_additive_material()
	stamp_root.add_child(sprite)
	# Stamps persist ~150ms (~9 frames at 60fps) so additive blending
	# in the CLEAR_MODE_NEVER render target accumulates alpha to a
	# saturated value. A one-frame paint deposits ~0.7 alpha which
	# left small mist-drop stamps reading as invisible after the
	# shader's multiply-stain treatment; persisting across multiple
	# frames builds the alpha up to the full visible range. Net cost
	# is trivial: ~10-20 active sprites at peak combat density, all
	# rendered into the same SubViewport that's already updating each
	# frame.
	var stamp_id := sprite.get_instance_id()
	var timer := get_tree().create_timer(0.15)
	timer.timeout.connect(
		func() -> void:
			var s := instance_from_id(stamp_id) as Node
			if s != null and is_instance_valid(s):
				s.queue_free(),
		CONNECT_ONE_SHOT
	)
	# Spawn gravity-drip streaks below the splatter. Tiny mist drops
	# skip this — would otherwise sprout streaks from every per-hit
	# speck during a fight, reading as constant rain.
	if world_radius >= DRIP_RADIUS_THRESHOLD:
		_spawn_drips(world_pos, use_x_mask, stamp_root, world_radius)


# Emits N small drip sprites just below the impact point. Each falls
# in mask Y (= world down) over its lifetime, paints additively each
# frame, accumulating a streak. Initial horizontal scatter spreads
# the start points within the splatter footprint so a single splat
# trails multiple ribbons instead of one collinear line.
func _spawn_drips(world_pos: Vector3, use_x_mask: bool, stamp_root: Node2D, source_radius: float) -> void:
	var drip_count: int = randi_range(DRIP_COUNT_MIN, DRIP_COUNT_MAX)
	var px_per_m_h: float = float(MASK_PX_X) / WORLD_EXTENT_XZ
	var px_per_m_v: float = float(MASK_PX_Y) / WALL_HEIGHT_M
	var drip_tex: Texture2D = _get_cached_stamp_texture()  # soft circle fits drip
	for i in drip_count:
		# Tighter horizontal scatter so drips emerge from inside the
		# splatter's core (0.25× radius vs the previous 0.5×) instead
		# of from its perimeter, reading as drainage from the splat
		# rather than separate ribbons.
		var scatter_h: float = randf_range(-source_radius * 0.25, source_radius * 0.25)
		var start_world: Vector3 = world_pos
		# Drop the drip start BELOW the splatter so its trail emerges into
		# clean wall instead of overlapping the splatter's own coverage.
		start_world.y -= source_radius * DRIP_START_OFFSET_RATIO
		if use_x_mask:
			start_world.z += scatter_h
		else:
			start_world.x += scatter_h
		var horizontal_world: float = start_world.z if use_x_mask else start_world.x
		var sprite := Sprite2D.new()
		sprite.texture = drip_tex
		sprite.material = _get_cached_additive_material()
		sprite.position = Vector2(
			horizontal_world * px_per_m_h + float(MASK_PX_X) * 0.5,
			(WALL_HEIGHT_M - start_world.y) * px_per_m_v,
		)
		var diam_px: float = DRIP_RADIUS_M * 2.0 * px_per_m_h
		var base_scale: float = diam_px / float(drip_tex.get_size().x)
		# Stretch vertically so each frame's paint is a short line
		# segment instead of a circle. Cumulative paints across frames
		# overlap as a continuous streak rather than a stack of circles.
		sprite.scale = Vector2(base_scale, base_scale * DRIP_VERTICAL_STRETCH)
		sprite.modulate = Color(1.0, 1.0, 1.0, DRIP_PER_FRAME_INTENSITY)
		stamp_root.add_child(sprite)
		var fall_speed: float = randf_range(DRIP_FALL_SPEED_MIN, DRIP_FALL_SPEED_MAX)
		var lifetime: float = randf_range(DRIP_LIFETIME_MIN, DRIP_LIFETIME_MAX)
		# Cap total fall distance — keeps the streak tail near the
		# splatter regardless of speed/lifetime roll, so streaks read
		# as visually anchored rather than floating off into space.
		var fall_distance_m: float = minf(fall_speed * lifetime, DRIP_MAX_FALL_DISTANCE_M)
		var fall_distance_px: float = fall_distance_m * px_per_m_v
		_active_drips.append({
			&"sprite": sprite,
			&"elapsed": 0.0,
			&"lifetime": lifetime,
			&"start_y": sprite.position.y,
			&"fall_px": fall_distance_px,
		})


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
	# Wet-sheen normal map — small-scale FastNoiseLite as a normal map
	# gives the dense blood its glossy highlight under scene lights
	# instead of reading as flat paint. Strength is gated by density
	# in the shader so only dense areas reflect.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.04
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.as_normal_map = true
	noise_tex.bump_strength = 4.0
	noise_tex.width = 256
	noise_tex.height = 256
	_overlay_material.set_shader_parameter(&"surface_noise", noise_tex)
	# Shape noise for density modulation — low frequency + few octaves
	# so it reads as large organic patches breaking up the edge
	# silhouette, NOT a stippled spray of dots inside the splatter.
	var shape := FastNoiseLite.new()
	shape.noise_type = FastNoiseLite.TYPE_SIMPLEX
	shape.frequency = 0.03
	shape.fractal_octaves = 2
	var shape_tex := NoiseTexture2D.new()
	shape_tex.noise = shape
	shape_tex.width = 256
	shape_tex.height = 256
	shape_tex.seamless = true
	_overlay_material.set_shader_parameter(&"shape_noise", shape_tex)


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


# Cached soft-edged 64px circle reused for every stamp. Phase 7 will
# swap this for chaotic lobed splatters matching the floor LiquidLayer.
static var _cached_stamp_texture: ImageTexture = null

static func _get_cached_stamp_texture() -> ImageTexture:
	if _cached_stamp_texture != null:
		return _cached_stamp_texture
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var dx := float(x - 32)
			var dy := float(y - 32)
			var d := sqrt(dx * dx + dy * dy) / 28.0
			var a: float = clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
	_cached_stamp_texture = ImageTexture.create_from_image(img)
	return _cached_stamp_texture


# Additive blend mode for stamp Sprite2Ds — overlapping stamps in the
# same mask region sum rather than over-paint, so dense fight zones
# build heavier coverage as a natural result of the cumulative draws.
static var _cached_additive_material: CanvasItemMaterial = null

static func _get_cached_additive_material() -> CanvasItemMaterial:
	if _cached_additive_material != null:
		return _cached_additive_material
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_cached_additive_material = mat
	return _cached_additive_material
