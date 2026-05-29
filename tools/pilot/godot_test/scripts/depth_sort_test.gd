extends Node2D

# Phase 0 depth-sort validation. Procedurally builds a small grid of
# graybox floor tiles + a row of walls at the north edge, spawns a
# controllable character. WASD / arrow keys move the character; goal:
# walk through the wall line and confirm y-sort draws the wall on top
# when the character is north of it (above on screen), character on
# top when south of it.
#
# F1 — switch to the sprite picker scene.

const SPRITES_ROOT      := "res://sprites"
const ENV_ROOT          := "res://environment/facility"
const SPRITE_TEST_SCENE := "res://scenes/sprite_test.tscn"

# Iso tile geometry — measured from the 512² floor render at the
# canonical 81 px/m density. Diamond is 232 × 117 px (true 2:1 iso),
# so half-extents are (116, 58). Adjacent tiles in the (row, col)
# grid offset by these half-extents diagonally.
const TILE_HALF_W := 116.0
const TILE_HALF_H := 58.0

# 5x5 floor grid centered on (row=2, col=2). Comfortable size for a
# 1280×720 viewport at the camera zoom set in the scene.
const GRID_SIZE := 5

const CHARACTER_NAME := "analog_male"
const MOVE_SPEED     := 220.0
const SPRITE_SCALE   := Vector2(1.0, 1.0)

@onready var y_sort: Node2D = $YSort
@onready var hint:   Label  = %Hint
@onready var debug:  Label  = %Debug

var character: AnimatedSprite2D


# ── Setup ───────────────────────────────────────────────────────────────────


func _ready() -> void:
	_build_floor()
	_build_north_wall()
	_spawn_character()
	hint.text = "WASD / Arrows — move.  Cross the wall line to test y-sort.  F1 — sprite picker."


func _grid_to_screen(row: int, col: int) -> Vector2:
	# Center the grid on (0, 0). Origin tile is the center of the screen.
	var ca: float = col - GRID_SIZE / 2.0 + 0.5
	var ra: float = row - GRID_SIZE / 2.0 + 0.5
	return Vector2(
		(ca - ra) * TILE_HALF_W,
		(ca + ra) * TILE_HALF_H,
	)


func _build_floor() -> void:
	var tex: Texture2D = load(ENV_ROOT + "/floor_tile.png")
	for row in range(GRID_SIZE):
		for col in range(GRID_SIZE):
			var s := Sprite2D.new()
			s.texture = tex
			s.position = _grid_to_screen(row, col)
			s.z_index = -10  # floors always draw beneath everything
			y_sort.add_child(s)


func _build_north_wall() -> void:
	# One wall sprite per column along the northernmost row of the grid
	# (row index -1, north of the top floor row). Each wall's foot sits
	# at the north edge of column `col`. The wall texture's pivot is
	# the wall foot, so positioning at that screen point lines the foot
	# up with the floor.
	var tex: Texture2D = load(ENV_ROOT + "/wall_section.png")
	for col in range(GRID_SIZE):
		var w := Sprite2D.new()
		w.texture = tex
		# Position the wall foot at the north edge of the row=0 tile in
		# this column. That edge is the row=0 tile's center, shifted
		# half a tile up-and-out — but for graybox validation,
		# placing at row=-1 (one row north of the top floor row) is
		# close enough and visually obvious.
		w.position = _grid_to_screen(-1, col)
		y_sort.add_child(w)


func _spawn_character() -> void:
	character = AnimatedSprite2D.new()
	character.sprite_frames = _build_idle_frames()
	character.scale = SPRITE_SCALE
	character.position = _grid_to_screen(GRID_SIZE / 2, GRID_SIZE / 2)
	character.play("idle_S")
	y_sort.add_child(character)


func _build_idle_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.add_animation("idle_S")
	frames.set_animation_speed("idle_S", 24)
	frames.set_animation_loop("idle_S", true)
	var anim_path := "%s/%s/idle" % [SPRITES_ROOT, CHARACTER_NAME]
	var d := DirAccess.open(anim_path)
	var paths: Array = []
	if d:
		for f in d.get_files():
			if f.begins_with("S_") and f.ends_with(".png"):
				paths.append(anim_path + "/" + f)
		paths.sort()
	for p in paths:
		var t: Texture2D = load(p)
		if t:
			frames.add_frame("idle_S", t)
	if paths.is_empty():
		push_error("[depth_sort_test] No frames found for %s/idle/S_*.png" % CHARACTER_NAME)
	return frames


# ── Input + movement ────────────────────────────────────────────────────────


func _process(delta: float) -> void:
	# Read input as WORLD direction (D2 / PoE convention): W means
	# walk world-north, which projects up-and-left on screen.
	var world_v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		world_v.x += 1  # world east
	if Input.is_physical_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		world_v.x -= 1  # world west
	if Input.is_physical_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		world_v.y += 1  # world south
	if Input.is_physical_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		world_v.y -= 1  # world north
	if world_v.length_squared() > 0.0:
		# Convert world direction → screen direction using the same
		# iso projection as _grid_to_screen, then renormalize so the
		# on-screen speed is uniform regardless of direction.
		var wn := world_v.normalized()
		var screen_v := Vector2(
			(wn.x - wn.y) * TILE_HALF_W,
			(wn.x + wn.y) * TILE_HALF_H,
		).normalized()
		character.position += screen_v * MOVE_SPEED * delta
	debug.text = "char y=%.0f  (wall row y=%.0f)" % [character.position.y, _grid_to_screen(-1, 2).y]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		get_tree().change_scene_to_file(SPRITE_TEST_SCENE)
