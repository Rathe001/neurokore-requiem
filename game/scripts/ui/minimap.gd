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

## Camera offset direction matches the main camera (4, 14, 4).
const CAMERA_DIRECTION := Vector3(4.0, 14.0, 4.0)

## Bake camera settings — captures the entire playable area in one shot.
## ortho_size must cover the full level diagonal; distance keeps geometry in the
## near/far range. These are generous defaults; the bake centres on the level
## builder's ground centre.
const BAKE_ORTHO_SIZE := 80.0
const BAKE_DISTANCE := 140.0
const BAKE_VIEWPORT_SIZE := Vector2i(1024, 1024)

## Runtime view sizes control how much of the baked texture is visible.
const CORNER_VIEW_SIZE := 30.0   # world-unit radius visible in corner mode
const FULL_VIEW_SIZE := 80.0     # world-unit radius visible in fullscreen

## Visibility layer for entities to exclude from the minimap.
const ENTITY_LAYER := 2
const TERRAIN_ONLY_MASK := 1

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
var _cam_dir: Vector3

## Bake metadata — maps world position to UV coordinates.
var _bake_center: Vector3 = Vector3.ZERO  # world-space centre of the bake
var _bake_ortho: float = BAKE_ORTHO_SIZE  # ortho size used during bake
## Camera basis vectors captured at bake time — used to project world offsets
## onto the baked image's 2D plane.
var _bake_right: Vector3
var _bake_up: Vector3

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_cam_dir = CAMERA_DIRECTION.normalized()

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

	_tag_entity_layers()
	_bake_map()
	_apply_layout()

# ── Bake ──────────────────────────────────────────────────────────────────────

func _bake_map() -> void:
	# Compute the AABB centre of all structures to place the bake camera.
	var structures := get_tree().get_nodes_in_group(&"structures")
	if not structures.is_empty():
		var min_pos := Vector3(INF, INF, INF)
		var max_pos := Vector3(-INF, -INF, -INF)
		for node in structures:
			if node is Node3D:
				var p: Vector3 = (node as Node3D).global_position
				min_pos = Vector3(minf(min_pos.x, p.x), minf(min_pos.y, p.y), minf(min_pos.z, p.z))
				max_pos = Vector3(maxf(max_pos.x, p.x), maxf(max_pos.y, p.y), maxf(max_pos.z, p.z))
		_bake_center = (min_pos + max_pos) * 0.5
	else:
		_bake_center = Vector3.ZERO

	# Create a temporary SubViewport for the one-shot render.
	var vp := SubViewport.new()
	vp.world_3d = get_viewport().world_3d
	vp.size = BAKE_VIEWPORT_SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	add_child(vp)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = BAKE_ORTHO_SIZE
	cam.far = 300.0
	cam.near = 0.1
	cam.current = true
	cam.cull_mask = TERRAIN_ONLY_MASK
	vp.add_child(cam)

	cam.global_position = _bake_center + _cam_dir * BAKE_DISTANCE
	cam.look_at(_bake_center, Vector3.UP)

	_bake_ortho = BAKE_ORTHO_SIZE
	_bake_right = cam.global_transform.basis.x
	_bake_up = cam.global_transform.basis.y

	# Let the viewport render one frame.
	await RenderingServer.frame_post_draw

	# Capture the rendered image as a persistent ImageTexture.
	var img := vp.get_texture().get_image()
	var baked_tex := ImageTexture.create_from_image(img)
	_texture_rect.texture = baked_tex

	# Clean up the temporary viewport.
	vp.queue_free()

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
	var scale := view_size / _bake_ortho
	_mask_material.set_shader_parameter(&"uv_scale", scale)

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

	var map_r := Rect2(_texture_rect.position, _texture_rect.size)
	var o := FULLSCREEN_OPACITY if mode == Mode.FULLSCREEN else 1.0
	_radar.map_rect = map_r
	_radar.camera_ortho_size = FULL_VIEW_SIZE if mode == Mode.FULLSCREEN else CORNER_VIEW_SIZE
	_radar.project_right = _bake_right
	_radar.project_up = _bake_up
	_radar.opacity = o
	_player_dot.map_center = map_r.get_center()
	_player_dot.opacity = o

# ── Entity layer tagging ──────────────────────────────────────────────────────

func _tag_entity_layers() -> void:
	for group in [&"player", &"enemies", &"pickups", &"corpses"]:
		for node in get_tree().get_nodes_in_group(group):
			_add_entity_layer_recursive(node)
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if not node is VisualInstance3D:
		return
	var parent := node.get_parent()
	while parent != null:
		for group in [&"enemies", &"pickups", &"corpses", &"player"]:
			if parent.is_in_group(group):
				(node as VisualInstance3D).layers = (1 << (ENTITY_LAYER - 1))
				return
		parent = parent.get_parent()

func _add_entity_layer_recursive(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = (1 << (ENTITY_LAYER - 1))
	for child in node.get_children():
		_add_entity_layer_recursive(child)
