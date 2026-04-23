class_name UVWallText extends StaticBody3D

## Text written on a wall that is only visible under UV light.
## Add a UVRevealable child to handle range-based fade.
## Hovering highlights the text and shows a tooltip with the message.

const TEXT_COLOR := Color(0.5, 0.2, 0.95, 1.0)
const FONT_SIZE := 24
const PIXEL_SIZE := 0.01

# Approximate collision box in metres: font_size * pixel_size per row,
# ~13px average glyph width * pixel_size per column.
const COLLISION_HEIGHT := 0.32
const COLLISION_WIDTH  := 2.6
const COLLISION_DEPTH  := 0.05

const OUTLINE_SIZE_IDLE  := 2
const OUTLINE_SIZE_HOVER := 8
const OUTLINE_COLOR_IDLE  := Color(0.3, 0.1, 0.6, 0.6)
const OUTLINE_COLOR_HOVER := Color(0.8, 0.5, 1.0, 1.0)

@export var text: String = "THEY WERE HERE"

var _label: Label3D

func _ready() -> void:
	_label = Label3D.new()
	_label.text = text
	_label.font_size = FONT_SIZE
	_label.pixel_size = PIXEL_SIZE
	_label.modulate = TEXT_COLOR
	_label.outline_modulate = OUTLINE_COLOR_IDLE
	_label.outline_size = OUTLINE_SIZE_IDLE
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_label.no_depth_test = true   # flush to wall — no floating gap
	_label.position = Vector3.ZERO
	add_child(_label)

	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(COLLISION_WIDTH, COLLISION_HEIGHT, COLLISION_DEPTH)
	col_shape.shape = box
	add_child(col_shape)

	var revealer := UVRevealable.new()
	add_child(revealer)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_mouse_entered() -> void:
	if not visible:
		return
	_label.outline_size = OUTLINE_SIZE_HOVER
	_label.outline_modulate = OUTLINE_COLOR_HOVER
	get_tree().call_group(&"interactable_tooltip", &"show_text", text)

func _on_mouse_exited() -> void:
	_label.outline_size = OUTLINE_SIZE_IDLE
	_label.outline_modulate = OUTLINE_COLOR_IDLE
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
