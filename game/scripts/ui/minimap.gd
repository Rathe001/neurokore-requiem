extends Control
class_name Minimap

## Baked isometric minimap. On level load the entire map is rendered once into a
## static ImageTexture via a temporary SubViewport. At runtime only cheap 2D
## panning (shader uniforms) and the scanner radar overlay update each frame —
## no second 3D render pass.
##
## Two display modes:
## - Corner: small circle in the upper-right.
## - Fullscreen: large centered circle with dimmed background.
## Tab key toggles between them.

signal mode_changed(is_fullscreen: bool)

enum Mode { CORNER, FULLSCREEN }

const CORNER_SIZE := 170.0
const CORNER_MARGIN := 12.0
const FULLSCREEN_FRACTION := 0.6  # fraction of the shorter screen axis

## Bake settings — the minimap renders an abstract D2-style top-down
## image of walkable area (filled rectangles for each room/corridor
## floor). ortho_size is computed at bake time from the floor AABB;
## the floor floors a min for tiny test levels so the map doesn't
## become a postage stamp, and a margin multiplier so the level isn't
## pressed against the texture edge.
const BAKE_ORTHO_SIZE_MIN := 60.0
const BAKE_ORTHO_MARGIN := 1.4   # multiplier on max(width, depth) of the AABB
const BAKE_VIEWPORT_SIZE := Vector2i(1024, 1024)
## Colours for the rasterized map. Floor is a soft cool grey-blue that
## reads as "passable space" against the void background. Bake background
## is fully transparent so the parent shader's bg_color shows through.
const FLOOR_COLOR := Color(0.42, 0.55, 0.68, 0.95)
## Faded preview tint — pieces directly adjacent to a revealed piece but
## not yet entered. The minimap shader gates state by per-pixel luminance
## (alpha is only used internally for the void_only painter check), so this
## color needs a luminance value between brightness_threshold (0.08) and
## seen_threshold (0.32) for the shader to render it as seen_color. RGB at
## ~0.20 gives a luminance of ~0.20, comfortably inside the seen band.
const FLOOR_COLOR_SEEN := Color(0.20, 0.20, 0.20, 1.0)
const VOID_COLOR := Color(0.0, 0.0, 0.0, 0.0)

## Runtime view sizes control how much of the baked texture is visible.
const CORNER_VIEW_SIZE := 30.0   # world-unit radius visible in corner mode
const FULL_VIEW_SIZE := 80.0     # world-unit radius visible in fullscreen
## Arrow-key pan speed (world units per second) while in fullscreen mode.
## Tuned to traverse a full FULL_VIEW_SIZE in about 1.5s of held input —
## fast enough to scan a large level without being twitchy. Reset to zero
## whenever the player toggles back to corner mode.
const FULLSCREEN_PAN_SPEED := 55.0

## Rotates the displayed map so it aligns with the iso game camera.
## -PI/4 (-45°) makes "screen up" point in the world's (-X, -Z)
## direction — the same direction the player walks when pressing W.
## The bake itself is top-down (axis-aligned room rectangles for fast
## rasterization); the rotation is applied in the shader's UV
## sampling. The radar overlay uses an iso projection basis below
## that mirrors this so blip positions match the rotated map.
const MAP_ROTATION_RADIANS := -PI * 0.25
const ISO_PROJECT_RIGHT := Vector3(0.7071068, 0.0, -0.7071068)  # (1, 0, -1).normalized()
const ISO_PROJECT_UP := Vector3(-0.7071068, 0.0, -0.7071068)    # (-1, 0, -1).normalized()

const CORNER_OPACITY := 0.92
const FULLSCREEN_OPACITY := 0.4

var mode: Mode = Mode.CORNER
var scanner_active: bool = false:
	set(value):
		scanner_active = value
		if _radar != null:
			_radar.visible = value

var _texture_rect: TextureRect
var _mask_material: ShaderMaterial
var _player_dot: MinimapPlayerDot
var _radar: ScannerRadar
var _markers: MinimapMarkerOverlay
var _player: Node3D

## Bake metadata — maps world position to UV coordinates.
var _bake_center: Vector3 = Vector3.ZERO  # world-space centre of the bake
var _bake_ortho: float = BAKE_ORTHO_SIZE_MIN  # ortho size used during bake (computed at bake time)
## Top-down basis vectors used by both the pan transform and the radar
## overlay's world→map projection. Always (RIGHT, FORWARD) post-rewrite,
## but kept as fields so the radar's project_right/project_up assignment
## still works without conditionals.
var _bake_right: Vector3 = Vector3.RIGHT
var _bake_up: Vector3 = Vector3.FORWARD
## Per-floor-rect tag list captured at bake time so reveal events can paint
## just the newly-explored room's pixels instead of re-walking the scene
## tree. Each entry: {"rect": Rect2 (world-space XZ), "room_id": StringName}.
var _walkable_rects: Array = []
## Mutable bake image — _on_room_revealed paints new floor rects into it
## and pushes the update to _bake_texture. Kept around between reveals so
## the previously-painted state persists.
var _bake_image: Image
var _bake_texture: ImageTexture
## Fullscreen-mode arrow-key pan offset (world XZ). Added to the player's
## position to compute the visible map center, and used in reverse to
## reposition the player dot away from the widget center so it stays at
## the player's true world position as the map scrolls. Zeroed on mode
## toggle so closing fullscreen always recenters on the player.
var _manual_pan_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group(&"minimap")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# TextureRect — will hold the baked texture.
	_texture_rect = TextureRect.new()
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader: Shader = load("res://shaders/minimap_circle.gdshader")
	_mask_material = ShaderMaterial.new()
	_mask_material.shader = shader
	_texture_rect.material = _mask_material
	add_child(_texture_rect)

	# Marker overlay sits BELOW the player dot in the z-order so the player
	# dot always wins when a marker overlaps it (you on top of an exit pad).
	_markers = MinimapMarkerOverlay.new()
	add_child(_markers)

	_player_dot = MinimapPlayerDot.new()
	add_child(_player_dot)

	_radar = ScannerRadar.new()
	_radar.visible = scanner_active
	add_child(_radar)

	# Wait one frame so level geometry and entities are in the tree.
	await get_tree().process_frame
	# LevelBuilder._build_level is async (yields between piece batches so the
	# loading screen stays responsive). Baking before it finishes captures
	# only the first 2-4 pieces and produces a sparse, wrong-looking
	# minimap. Await the builder's `built` signal before the first bake.
	# Idempotent — returns immediately if the build already finished.
	var builder := _find_level_builder()
	if builder != null:
		await builder.await_built()
	_player = _find_local_player()
	if _player != null:
		_radar.set_player(_player)

	# Fog-of-war hooks: room_revealed paints full color; room_seen paints the
	# adjacency-preview faded color. Both are connected once — ExplorationState
	# is an autoload so the signals persist across rebakes.
	if not ExplorationState.room_revealed.is_connected(_on_room_revealed):
		ExplorationState.room_revealed.connect(_on_room_revealed)
	if not ExplorationState.room_seen.is_connected(_on_room_seen):
		ExplorationState.room_seen.connect(_on_room_seen)

	_bake_map()
	_apply_layout()


# Walks the scene tree to find the active LevelBuilder. Used to gate the
# initial bake on async build completion. Returns null when no builder
# exists (legacy / test scenes without a level) — callers no-op cleanly.
func _find_level_builder() -> LevelBuilder:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return _find_level_builder_in(scene)


func _find_level_builder_in(node: Node) -> LevelBuilder:
	if node is LevelBuilder:
		return node
	for child in node.get_children():
		var r := _find_level_builder_in(child)
		if r != null:
			return r
	return null

# ── Bake ──────────────────────────────────────────────────────────────────────

## Public rebake entry point. Called after a level transition so the
## minimap re-rasterizes the new floor geometry and resets panning.
func rebake() -> void:
	# Re-acquire the player ref in case it was recycled.
	_player = _find_local_player()
	if _player != null:
		_radar.set_player(_player)
	_bake_map()
	_apply_layout()


# Local-player lookup. In MP the &"player" group holds every peer's avatar
# — picking [0] would land on a remote avatar on the client side and the
# whole minimap would pan around the wrong player. is_multiplayer_authority
# returns true only on the avatar owned by this peer.
func _find_local_player() -> Node3D:
	var players := get_tree().get_nodes_in_group(&"player")
	for n in players:
		var node := n as Node3D
		if node != null and is_instance_valid(node) and node.is_multiplayer_authority():
			return node
	if players.is_empty():
		return null
	return players[0] as Node3D


func _bake_map() -> void:
	# D2-style abstract bake. Walk the &"minimap_walkable" group (every
	# floor StaticBody3D registers itself there in floor_builder.gd),
	# pull each floor's XZ rect from its BoxShape3D collision, and
	# tag each rect with the ExplorationState piece-id it sits inside.
	# Rasterization is selective — only rects whose room is in
	# ExplorationState's explored set get painted; the rest stay void
	# until the player walks into them and reveal_room fires.
	_walkable_rects.clear()
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for n in get_tree().get_nodes_in_group(&"minimap_walkable"):
		var sb := n as Node3D
		if sb == null:
			continue
		var col := sb.get_node_or_null("Collision") as CollisionShape3D
		if col == null:
			continue
		var shape := col.shape as BoxShape3D
		if shape == null:
			continue
		var center_xz := Vector2(sb.global_position.x, sb.global_position.z)
		var size_xz := Vector2(shape.size.x, shape.size.z)
		var rect := Rect2(center_xz - size_xz * 0.5, size_xz)
		var center_world := Vector3(center_xz.x, sb.global_position.y, center_xz.y)
		var room_id: StringName = ExplorationState.room_at_world(center_world)
		_walkable_rects.append({"rect": rect, "room_id": room_id})
		min_x = minf(min_x, rect.position.x)
		max_x = maxf(max_x, rect.position.x + rect.size.x)
		min_z = minf(min_z, rect.position.y)
		max_z = maxf(max_z, rect.position.y + rect.size.y)

	if _walkable_rects.is_empty():
		_bake_center = Vector3.ZERO
		_bake_ortho = BAKE_ORTHO_SIZE_MIN
	else:
		_bake_center = Vector3((min_x + max_x) * 0.5, 0.0, (min_z + max_z) * 0.5)
		var extent := maxf(max_x - min_x, max_z - min_z)
		_bake_ortho = maxf(BAKE_ORTHO_SIZE_MIN, extent * BAKE_ORTHO_MARGIN)

	# True top-down basis. World X → image X (right). World Z → image Y
	# (down). Pan + radar overlay use these via dot product so the
	# orientation is consistent everywhere.
	_bake_right = Vector3.RIGHT
	_bake_up = Vector3.FORWARD  # (0, 0, -1); _world_to_map negates so positive Z → screen Y down

	_bake_image = Image.create(BAKE_VIEWPORT_SIZE.x, BAKE_VIEWPORT_SIZE.y, false, Image.FORMAT_RGBA8)
	_bake_image.fill(VOID_COLOR)
	# Paint state-by-state. Explored beats seen (full color overwrites the
	# faded preview); seen-but-not-explored beats void. Rects with no room_id
	# (legacy levels with no ExplorationState population) get full color
	# unconditionally so we don't break those.
	# On initial load both sets are usually empty (player hasn't moved yet)
	# so the image starts blank; LosCuller's first reveal_room fires within
	# a physics tick of spawn and lights the starting room plus its
	# neighbours.
	# Two passes so explored rects can sit on top of any seen rects that
	# overlap them at boundaries — seen uses void_only painting, so the
	# pass order only matters if a piece switches state mid-bake (it can't).
	for entry in _walkable_rects:
		var rid: StringName = entry["room_id"]
		if rid != &"" and not ExplorationState.is_explored(rid) and ExplorationState.is_seen(rid):
			_paint_rect_into_bake(entry["rect"], FLOOR_COLOR_SEEN, true)
	for entry in _walkable_rects:
		var rid: StringName = entry["room_id"]
		if rid == &"" or ExplorationState.is_explored(rid):
			_paint_rect_into_bake(entry["rect"], FLOOR_COLOR)

	_bake_texture = ImageTexture.create_from_image(_bake_image)
	_texture_rect.texture = _bake_texture


# Paints one walkable rect (world XZ coordinates) onto _bake_image using
# the bake's center+ortho mapping with the given fill color. Used by both
# initial bake and incremental seen/revealed updates; caller is responsible
# for pushing the texture update after a batch of paints (so a multi-rect
# room only triggers one GPU upload).
#
# void_only=true skips pixels that are already painted, used for SEEN paints
# so a seen corridor's overlap-extended rect (FLOOR_OVERLAP pushes ~3 px past
# the piece boundary) can't dim the adjacent explored room's border pixels.
func _paint_rect_into_bake(rect: Rect2, color: Color, void_only: bool = false) -> void:
	if _bake_image == null:
		return
	var px_per_world := float(BAKE_VIEWPORT_SIZE.x) / _bake_ortho
	var center_px := Vector2(BAKE_VIEWPORT_SIZE) * 0.5
	var image_bounds := Rect2i(Vector2i.ZERO, BAKE_VIEWPORT_SIZE)
	var px_min: Vector2 = center_px + (rect.position - Vector2(_bake_center.x, _bake_center.z)) * px_per_world
	var px_size: Vector2 = rect.size * px_per_world
	var px_rect := Rect2i(int(round(px_min.x)), int(round(px_min.y)), int(round(px_size.x)), int(round(px_size.y)))
	px_rect = px_rect.intersection(image_bounds)
	if px_rect.size.x <= 0 or px_rect.size.y <= 0:
		return
	if not void_only:
		_bake_image.fill_rect(px_rect, color)
		return
	for y in range(px_rect.position.y, px_rect.position.y + px_rect.size.y):
		for x in range(px_rect.position.x, px_rect.position.x + px_rect.size.x):
			if _bake_image.get_pixel(x, y).a == 0.0:
				_bake_image.set_pixel(x, y, color)


# ExplorationState.room_revealed handler. Paints every walkable rect
# tagged with the revealed room onto the existing bake image in full color
# — overwrites any previous faded-preview pixels from the seen state.
func _on_room_revealed(room_id: StringName) -> void:
	_repaint_room(room_id, FLOOR_COLOR, false)


# ExplorationState.room_seen handler. Paints the room's rects at faded
# alpha so the player sees a preview of adjacent corridors / rooms before
# walking into them. Skipped if the room is already explored (full color
# wins; we don't want to dim a previously-revealed piece). void_only so the
# overlap band at the piece boundary doesn't tint an already-explored
# neighbour.
func _on_room_seen(room_id: StringName) -> void:
	if ExplorationState.is_explored(room_id):
		return
	_repaint_room(room_id, FLOOR_COLOR_SEEN, true)


func _repaint_room(room_id: StringName, color: Color, void_only: bool) -> void:
	if _bake_image == null or _bake_texture == null:
		return
	var painted := false
	for entry in _walkable_rects:
		if entry["room_id"] != room_id:
			continue
		_paint_rect_into_bake(entry["rect"], color, void_only)
		painted = true
	if painted:
		_bake_texture.update(_bake_image)

# ── Per-frame pan ─────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if mode == Mode.FULLSCREEN:
		_handle_manual_pan(delta)
	_update_pan()


# Accumulates arrow-key input into _manual_pan_offset while in fullscreen.
# Direction vectors use the iso projection basis so "screen up" / "screen
# right" line up with the rotated map display — pressing up arrow pans
# the visible area upward on screen regardless of which world axis that
# corresponds to. Released keys mean no input; the offset stays where it
# was so the user can let go of arrows and the panned view persists.
func _handle_manual_pan(delta: float) -> void:
	var dx := 0.0
	var dy := 0.0
	if Input.is_action_pressed(&"ui_left"):
		dx -= 1.0
	if Input.is_action_pressed(&"ui_right"):
		dx += 1.0
	if Input.is_action_pressed(&"ui_up"):
		dy -= 1.0
	if Input.is_action_pressed(&"ui_down"):
		dy += 1.0
	if dx == 0.0 and dy == 0.0:
		return
	var input := Vector2(dx, dy)
	if input.length_squared() > 1.0:
		input = input.normalized()
	# Screen-axis input → world XZ delta via the iso basis. dy is in
	# "screen down is positive" convention, so we negate it before applying
	# to the up-basis so up arrow moves the visible area up on screen.
	var step: Vector3 = ISO_PROJECT_RIGHT * input.x + ISO_PROJECT_UP * (-input.y)
	_manual_pan_offset += step * FULLSCREEN_PAN_SPEED * delta


func _update_pan() -> void:
	# Visible center = player position + arrow-key offset. The offset is
	# always zero outside fullscreen mode so corner-mode behaviour stays
	# unchanged.
	var view_center := _player.global_position + _manual_pan_offset
	# Project the visible-centre world offset onto the baked image's 2D axes.
	var offset := view_center - _bake_center
	var sx := offset.dot(_bake_right)
	var sy := -offset.dot(_bake_up)  # screen Y is inverted
	# Convert world offset to UV offset (bake covers _bake_ortho world units).
	var uv_x := sx / _bake_ortho
	var uv_y := sy / _bake_ortho
	_mask_material.set_shader_parameter(&"uv_offset", Vector2(uv_x, uv_y))

	# uv_scale controls zoom: ratio of view size to bake size.
	var view_size := FULL_VIEW_SIZE if mode == Mode.FULLSCREEN else CORNER_VIEW_SIZE
	var uv_scale := view_size / _bake_ortho
	_mask_material.set_shader_parameter(&"uv_scale", uv_scale)

	# Player dot follows the panned view. With no manual pan, the dot sits
	# at the widget centre (matching old behaviour). With pan, the dot
	# shifts the opposite way in iso pixel space so it visually stays at
	# the player's actual world position as the map scrolls past.
	var map_r := Rect2(_texture_rect.position, _texture_rect.size)
	var dot_world: Vector3 = -_manual_pan_offset
	var dot_iso_x := dot_world.dot(ISO_PROJECT_RIGHT)
	var dot_iso_y := -dot_world.dot(ISO_PROJECT_UP)
	var px_per_world := map_r.size.x / view_size
	_player_dot.map_center = map_r.get_center() + Vector2(dot_iso_x, dot_iso_y) * px_per_world

	# Marker overlay shares the same projection. view_center is the panned
	# centre so markers scroll with the map; project_* match the iso basis
	# the bake shader rotates into.
	if _markers != null:
		_markers.map_rect = map_r
		_markers.view_center = view_center
		_markers.view_size = view_size
		_markers.project_right = ISO_PROJECT_RIGHT
		_markers.project_up = ISO_PROJECT_UP
		# Always full opacity. The radar dims in fullscreen so its sweep
		# doesn't dominate the map, but markers ARE the map's point of
		# interest — keep them readable in both modes.
		_markers.opacity = 1.0
		_markers.queue_redraw()

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_minimap"):
		mode = Mode.FULLSCREEN if mode == Mode.CORNER else Mode.CORNER
		# Any mode change snaps the view back to player-centred. Matches
		# D2's behaviour: pan around in fullscreen, hit Tab, and the map
		# recentres on the player as it closes.
		_manual_pan_offset = Vector3.ZERO
		_apply_layout()
		mode_changed.emit(mode == Mode.FULLSCREEN)
		get_viewport().set_input_as_handled()
	elif mode == Mode.FULLSCREEN and event.is_action_pressed(&"ui_cancel"):
		mode = Mode.CORNER
		_manual_pan_offset = Vector3.ZERO
		_apply_layout()
		mode_changed.emit(false)
		get_viewport().set_input_as_handled()

# ── Layout ────────────────────────────────────────────────────────────────────

func _apply_layout() -> void:
	var screen := get_viewport_rect().size
	match mode:
		Mode.CORNER:
			var s := CORNER_SIZE
			_texture_rect.position = Vector2(screen.x - s - CORNER_MARGIN, CORNER_MARGIN)
			_texture_rect.size = Vector2(s, s)
			_mask_material.set_shader_parameter(&"border_width", 2.0)
			_mask_material.set_shader_parameter(&"opacity", CORNER_OPACITY)
			_mask_material.set_shader_parameter(&"bg_color", Color(0.04, 0.05, 0.04, 0.95))

		Mode.FULLSCREEN:
			var s := minf(screen.x, screen.y) * FULLSCREEN_FRACTION
			_texture_rect.position = Vector2((screen.x - s) * 0.5, (screen.y - s) * 0.5)
			_texture_rect.size = Vector2(s, s)
			_mask_material.set_shader_parameter(&"border_width", 0.0)
			_mask_material.set_shader_parameter(&"opacity", FULLSCREEN_OPACITY)
			_mask_material.set_shader_parameter(&"bg_color", Color(0.04, 0.05, 0.04, 0.0))

	# Apply iso rotation to the displayed map so it matches the in-game
	# camera angle. Pan keeps using top-down basis (set on _bake_right /
	# _bake_up) because the texture is baked top-down — only the
	# sample-direction rotates inside the shader.
	_mask_material.set_shader_parameter(&"rotation_radians", MAP_ROTATION_RADIANS)

	var map_r := Rect2(_texture_rect.position, _texture_rect.size)
	var o := FULLSCREEN_OPACITY if mode == Mode.FULLSCREEN else 1.0
	_radar.map_rect = map_r
	_radar.camera_ortho_size = FULL_VIEW_SIZE if mode == Mode.FULLSCREEN else CORNER_VIEW_SIZE
	# Radar projects blips in iso basis so they line up with the rotated
	# texture. Pan code above uses _bake_right/_bake_up (top-down) for
	# its own world-to-UV conversion; these are independent.
	_radar.project_right = ISO_PROJECT_RIGHT
	_radar.project_up = ISO_PROJECT_UP
	_radar.opacity = o
	_player_dot.map_center = map_r.get_center()
	_player_dot.opacity = o

