extends Control
class_name Minimap

## Isometric minimap rendered via SubViewport. Two modes:
## - Corner: small circle in the upper-right.
## - Fullscreen: large centered circle with dimmed background.
## Tab key toggles between them. Scanner radar draws on top when equipped.
##
## The minimap camera matches the main camera's isometric angle but zoomed out.
## It uses cull_mask to hide entities (player, enemies, pickups) — only terrain
## and structures are visible. Enemy positions come from the scanner radar overlay.

signal mode_changed(is_fullscreen: bool)

enum Mode { CORNER, FULLSCREEN }

const CORNER_SIZE := 170.0
const CORNER_MARGIN := 12.0
const FULLSCREEN_FRACTION := 0.6  # fraction of the shorter screen axis

## Camera offset direction matches the main camera (4, 14, 4) but at greater
## distance for a wider view. The ratio is preserved for identical perspective.
const CAMERA_DISTANCE_CORNER := 60.0
const CAMERA_DISTANCE_FULL := 120.0
const CAMERA_ORTHO_SIZE_CORNER := 30.0
const CAMERA_ORTHO_SIZE_FULL := 80.0

## Visibility layer for entities to exclude from the minimap.
## Entities (player, enemies, pickups) should be on layer 2.
## The minimap camera only renders layer 1 (terrain/structures).
const ENTITY_LAYER := 2
const TERRAIN_ONLY_MASK := 1  # only layer 1

const CORNER_OPACITY := 0.92
const FULLSCREEN_OPACITY := 0.4
const VIEWPORT_SIZE_CORNER := Vector2i(256, 256)
const VIEWPORT_SIZE_FULL := Vector2i(512, 512)

var mode: Mode = Mode.CORNER
var scanner_active: bool = false:
	set(value):
		scanner_active = value
		if _radar != null:
			_radar.visible = value

var _viewport: SubViewport
var _camera: Camera3D
var _texture_rect: TextureRect
var _mask_material: ShaderMaterial
var _player_dot: MinimapPlayerDot
var _radar: ScannerRadar
var _player: Node3D
## Normalized offset direction matching the main camera's (4, 14, 4).
var _cam_dir: Vector3

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_cam_dir = Vector3(4.0, 14.0, 4.0).normalized()

	# SubViewport — shares the same 3D world.
	_viewport = SubViewport.new()
	_viewport.world_3d = get_viewport().world_3d
	_viewport.size = VIEWPORT_SIZE_CORNER
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_2d = Viewport.MSAA_DISABLED
	_viewport.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
	add_child(_viewport)

	# Isometric orthographic camera — same angle as the main camera.
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = CAMERA_ORTHO_SIZE_CORNER
	_camera.far = 200.0
	_camera.near = 0.1
	_camera.current = true
	# Only render terrain (layer 1), hide entities (layer 2).
	_camera.cull_mask = TERRAIN_ONLY_MASK
	_viewport.add_child(_camera)

	# TextureRect to display the viewport.
	_texture_rect = TextureRect.new()
	_texture_rect.texture = _viewport.get_texture()
	_texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Circular mask shader.
	var shader: Shader = load("res://shaders/minimap_circle.gdshader")
	_mask_material = ShaderMaterial.new()
	_mask_material.shader = shader
	_texture_rect.material = _mask_material
	add_child(_texture_rect)

	# Player position dot (always visible, class-colored).
	_player_dot = MinimapPlayerDot.new()
	add_child(_player_dot)

	# Scanner radar overlay (drawn on top).
	_radar = ScannerRadar.new()
	_radar.visible = scanner_active
	add_child(_radar)

	# Find player and tag entities for cull mask exclusion.
	await get_tree().process_frame
	var players := get_tree().get_nodes_in_group(&"player")
	if not players.is_empty():
		_player = players[0] as Node3D
		_radar.set_player(_player)

	_tag_entity_layers()
	_apply_layout()

func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dist := CAMERA_DISTANCE_FULL if mode == Mode.FULLSCREEN else CAMERA_DISTANCE_CORNER
	_camera.global_position = _player.global_position + _cam_dir * dist
	_camera.look_at(_player.global_position, Vector3.UP)

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

func _apply_layout() -> void:
	var screen := get_viewport_rect().size
	match mode:
		Mode.CORNER:
			var s := CORNER_SIZE
			_texture_rect.position = Vector2(screen.x - s - CORNER_MARGIN, CORNER_MARGIN)
			_texture_rect.size = Vector2(s, s)
			_viewport.size = VIEWPORT_SIZE_CORNER
			_camera.size = CAMERA_ORTHO_SIZE_CORNER
			_mask_material.set_shader_parameter(&"border_width", 2.0)
			_mask_material.set_shader_parameter(&"opacity", CORNER_OPACITY)

		Mode.FULLSCREEN:
			var s := minf(screen.x, screen.y) * FULLSCREEN_FRACTION
			_texture_rect.position = Vector2((screen.x - s) * 0.5, (screen.y - s) * 0.5)
			_texture_rect.size = Vector2(s, s)
			_viewport.size = VIEWPORT_SIZE_FULL
			_camera.size = CAMERA_ORTHO_SIZE_FULL
			_mask_material.set_shader_parameter(&"border_width", 0.0)
			_mask_material.set_shader_parameter(&"opacity", FULLSCREEN_OPACITY)

	# Match radar and player dot to the texture rect.
	var map_r := Rect2(_texture_rect.position, _texture_rect.size)
	var o := FULLSCREEN_OPACITY if mode == Mode.FULLSCREEN else 1.0
	_radar.map_rect = map_r
	_radar.camera_ortho_size = _camera.size
	_radar.opacity = o
	_player_dot.map_center = map_r.get_center()
	_player_dot.opacity = o

func _tag_entity_layers() -> void:
	## Move all entity groups to visibility layer 2 only. The main camera sees
	## all layers (default mask), but the minimap camera sees only layer 1.
	for group in [&"player", &"enemies", &"pickups", &"corpses"]:
		for node in get_tree().get_nodes_in_group(group):
			_add_entity_layer_recursive(node)
	# Also connect tree signals so newly spawned entities get tagged.
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if not node is VisualInstance3D:
		return
	# Only care about nodes that are descendants of a tagged entity.
	# Walk parents to check — avoids connecting callbacks to terrain/structure nodes.
	var parent := node.get_parent()
	while parent != null:
		for group in [&"enemies", &"pickups", &"corpses", &"player"]:
			if parent.is_in_group(group):
				(node as VisualInstance3D).layers = (1 << (ENTITY_LAYER - 1))
				return
		parent = parent.get_parent()

func _add_entity_layer_recursive(node: Node) -> void:
	if node is VisualInstance3D:
		var vi := node as VisualInstance3D
		# Move from layer 1 to layer 2 only. The main camera sees both (mask 3),
		# but the minimap camera sees only layer 1 (terrain).
		vi.layers = (1 << (ENTITY_LAYER - 1))
	for child in node.get_children():
		_add_entity_layer_recursive(child)
