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
const VOID_COLOR := Color(0.0, 0.0, 0.0, 0.0)

## Runtime view sizes control how much of the baked texture is visible.
const CORNER_VIEW_SIZE := 30.0   # world-unit radius visible in corner mode
const FULL_VIEW_SIZE := 80.0     # world-unit radius visible in fullscreen

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

	_player_dot = MinimapPlayerDot.new()
	add_child(_player_dot)

	_radar = ScannerRadar.new()
	_radar.visible = scanner_active
	add_child(_radar)

	# Wait one frame so level geometry and entities are in the tree.
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group(&"player")
	if not players.is_empty():
		_player = players[0] as Node3D
		_radar.set_player(_player)

	_bake_map()
	_apply_layout()

# ── Bake ──────────────────────────────────────────────────────────────────────

## Public rebake entry point. Called after a level transition so the
## minimap re-rasterizes the new floor geometry and resets panning.
func rebake() -> void:
	# Re-acquire the player ref in case it was recycled.
	var players := get_tree().get_nodes_in_group(&"player")
	if not players.is_empty():
		_player = players[0] as Node3D
		_radar.set_player(_player)
	_bake_map()
	_apply_layout()


func _bake_map() -> void:
	# D2-style abstract bake. Walk the &"minimap_walkable" group (every
	# floor StaticBody3D registers itself there in floor_builder.gd),
	# pull each floor's XZ rect from its BoxShape3D collision, and
	# rasterize the rects onto a flat Image. No SubViewport, no 3D
	# render pass — just filled rectangles in world coords projected to
	# pixel coords. Result is a clean walkable shape: floor where you
	# can stand, transparent void everywhere else. The parent shader's
	# bg_color paints the void.
	var rects: Array[Rect2] = []
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
		rects.append(rect)
		min_x = minf(min_x, rect.position.x)
		max_x = maxf(max_x, rect.position.x + rect.size.x)
		min_z = minf(min_z, rect.position.y)
		max_z = maxf(max_z, rect.position.y + rect.size.y)

	if rects.is_empty():
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

	var img := Image.create(BAKE_VIEWPORT_SIZE.x, BAKE_VIEWPORT_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(VOID_COLOR)
	if not rects.is_empty():
		var px_per_world := float(BAKE_VIEWPORT_SIZE.x) / _bake_ortho
		var center_px := Vector2(BAKE_VIEWPORT_SIZE) * 0.5
		var image_bounds := Rect2i(Vector2i.ZERO, BAKE_VIEWPORT_SIZE)
		for rect in rects:
			var px_min: Vector2 = center_px + (rect.position - Vector2(_bake_center.x, _bake_center.z)) * px_per_world
			var px_size: Vector2 = rect.size * px_per_world
			var px_rect := Rect2i(int(round(px_min.x)), int(round(px_min.y)), int(round(px_size.x)), int(round(px_size.y)))
			px_rect = px_rect.intersection(image_bounds)
			if px_rect.size.x > 0 and px_rect.size.y > 0:
				img.fill_rect(px_rect, FLOOR_COLOR)

	_texture_rect.texture = ImageTexture.create_from_image(img)

# ── Per-frame pan ─────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_update_pan()

func _update_pan() -> void:
	# Project the player's world offset onto the baked image's 2D axes.
	var offset := _player.global_position - _bake_center
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

# ── Input ─────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_minimap"):
		mode = Mode.FULLSCREEN if mode == Mode.CORNER else Mode.CORNER
		_apply_layout()
		mode_changed.emit(mode == Mode.FULLSCREEN)
		get_viewport().set_input_as_handled()
	elif mode == Mode.FULLSCREEN and event.is_action_pressed(&"ui_cancel"):
		mode = Mode.CORNER
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

