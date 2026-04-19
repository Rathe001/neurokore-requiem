extends CanvasLayer

const LOW_HP_RATIO := 0.35
const FULL_COLOR := Color(0.3, 0.95, 1.0, 1.0)
const LOW_COLOR := Color(1.0, 0.25, 0.3, 1.0)

@onready var hp_fill: ColorRect = %HPFill
@onready var hp_label: Label = %HPLabel

var _max_health: int = 1

func _ready() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		push_warning("[prototype_hud] no player in group")
		return
	_max_health = int(player.max_health)
	if player.has_signal(&"health_changed"):
		player.health_changed.connect(_on_health_changed)
	_on_health_changed(_max_health, _max_health)

func _on_health_changed(current: int, max_value: int) -> void:
	_max_health = max(max_value, 1)
	var ratio := clampf(float(current) / float(_max_health), 0.0, 1.0)
	hp_fill.size.x = hp_fill.get_parent().size.x * ratio
	hp_fill.color = FULL_COLOR if ratio > LOW_HP_RATIO else LOW_COLOR
	hp_label.text = "%d / %d" % [max(current, 0), _max_health]
