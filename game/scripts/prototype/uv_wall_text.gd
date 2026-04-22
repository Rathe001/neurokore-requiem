class_name UVWallText extends StaticBody3D

## Text written on a wall that is only visible under UV light.
## Add a UVRevealable child to handle range-based fade.

const TEXT_COLOR := Color(0.5, 0.2, 0.95, 1.0)
const FONT_SIZE := 24

@export var text: String = "THEY WERE HERE"

var _label: Label3D

func _ready() -> void:
	_label = Label3D.new()
	_label.text = text
	_label.font_size = FONT_SIZE
	_label.modulate = TEXT_COLOR
	_label.outline_modulate = Color(0.3, 0.1, 0.6, 0.6)
	_label.outline_size = 2
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_label.no_depth_test = false
	_label.pixel_size = 0.01
	_label.position = Vector3(0, 0, 0.01)  # slight offset from wall
	add_child(_label)

	# UV reveal component.
	var revealer := UVRevealable.new()
	add_child(revealer)
