extends Node2D

# Runtime sprite loader for the pilot validation. Scans res://sprites/
# at startup, builds SpriteFrames resources on demand as the user picks
# character / anim / direction. Same layout convention as the Blender
# render output: <character>/<anim>/<dir>_<frame>.png.

const SPRITE_ROOT := "res://sprites"
const DIRECTIONS := ["S", "SW", "W", "NW", "N", "NE", "E", "SE"]
# Which anims should loop in playback. One-shot anims (attack, hit,
# death, jump, dodge, cast) play once and freeze on the last frame.
const LOOPING := {
	"idle": true, "walk": true, "run": true,
	"attack": false, "attack2": false,
	"hit": false, "death": false, "jump": false, "dodge": false, "cast": false,
}

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var char_picker: OptionButton = %CharacterPicker
@onready var anim_picker: OptionButton = %AnimPicker
@onready var dir_picker: OptionButton = %DirPicker
@onready var fps_spin: SpinBox = %FPSSpin
@onready var status_label: Label = %StatusLabel

# {character_name: {anim_name: {direction_name: [sorted texture paths]}}}
var sprite_tree: Dictionary = {}
var current_char := ""
var current_anim := ""
var current_dir := "S"


func _ready() -> void:
	_scan_sprite_tree()
	_populate_dir_picker()
	_populate_character_picker()
	char_picker.item_selected.connect(_on_character_changed)
	anim_picker.item_selected.connect(_on_anim_changed)
	dir_picker.item_selected.connect(_on_dir_changed)
	fps_spin.value_changed.connect(_on_fps_changed)
	_update_sprite()


func _scan_sprite_tree() -> void:
	var root := DirAccess.open(SPRITE_ROOT)
	if root == null:
		push_error("[sprite_test] Couldn't open %s — run `python tools/pilot/copy_sprites_to_godot.py` first" % SPRITE_ROOT)
		return
	for char_name in root.get_directories():
		sprite_tree[char_name] = _scan_character(SPRITE_ROOT + "/" + char_name)


func _scan_character(char_path: String) -> Dictionary:
	var result := {}
	var d := DirAccess.open(char_path)
	if d == null:
		return result
	for anim_name in d.get_directories():
		result[anim_name] = _scan_anim(char_path + "/" + anim_name)
	return result


func _scan_anim(anim_path: String) -> Dictionary:
	var per_dir := {}
	for d in DIRECTIONS:
		per_dir[d] = []
	var dir := DirAccess.open(anim_path)
	if dir == null:
		return per_dir
	# Godot's import system creates .png.import siblings — we want the .png.
	for fname in dir.get_files():
		if not fname.ends_with(".png"):
			continue
		# Filenames look like "S_00.png", "SW_07.png"
		var stem := fname.get_basename()  # strips trailing ".png"
		var parts := stem.split("_")
		if parts.size() < 2:
			continue
		var dir_name: String = parts[0]
		if not per_dir.has(dir_name):
			continue
		per_dir[dir_name].append(anim_path + "/" + fname)
	for d in DIRECTIONS:
		per_dir[d].sort()
	return per_dir


func _populate_dir_picker() -> void:
	dir_picker.clear()
	for d in DIRECTIONS:
		dir_picker.add_item(d)
	dir_picker.select(DIRECTIONS.find(current_dir))


func _populate_character_picker() -> void:
	char_picker.clear()
	var names := sprite_tree.keys()
	names.sort()
	for n in names:
		char_picker.add_item(n)
	if names.size() > 0:
		current_char = names[0]
		char_picker.select(0)
		_populate_anim_picker()


func _populate_anim_picker() -> void:
	anim_picker.clear()
	var anims: Array = sprite_tree[current_char].keys() if sprite_tree.has(current_char) else []
	anims.sort()
	for a in anims:
		anim_picker.add_item(a)
	if anims.size() > 0:
		current_anim = anims[0]
		anim_picker.select(0)


func _on_character_changed(idx: int) -> void:
	current_char = char_picker.get_item_text(idx)
	_populate_anim_picker()
	_update_sprite()


func _on_anim_changed(idx: int) -> void:
	current_anim = anim_picker.get_item_text(idx)
	_update_sprite()


func _on_dir_changed(idx: int) -> void:
	current_dir = dir_picker.get_item_text(idx)
	_update_sprite()


func _on_fps_changed(_v: float) -> void:
	_update_sprite()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		get_tree().change_scene_to_file("res://scenes/depth_sort_test.tscn")


func _update_sprite() -> void:
	if current_char == "" or current_anim == "" or current_dir == "":
		return
	if not sprite_tree.has(current_char):
		return
	var anim_data: Dictionary = sprite_tree[current_char]
	if not anim_data.has(current_anim):
		return
	var paths: Array = anim_data[current_anim][current_dir]

	# Build a fresh SpriteFrames resource — one animation, named
	# generically so we can swap content without renaming.
	var frames := SpriteFrames.new()
	var anim_name := "playing"
	frames.add_animation(anim_name)
	frames.set_animation_speed(anim_name, fps_spin.value)
	frames.set_animation_loop(anim_name, bool(LOOPING.get(current_anim, false)))

	for p in paths:
		var tex: Texture2D = load(p)
		if tex:
			frames.add_frame(anim_name, tex)

	sprite.sprite_frames = frames
	sprite.play(anim_name)
	status_label.text = "%s / %s / %s — %d frames @ %d FPS" % [
		current_char, current_anim, current_dir, paths.size(), int(fps_spin.value)
	]
