extends CanvasLayer
class_name HUD

# Screen-space overlay. Binds to the player and level via groups on
# _ready so it doesn't need direct node paths. The HP bar mirrors the
# player's current health; the banner shows transient messages
# (death, level cleared, etc).

const HP_BAR_WIDTH := 200.0

@onready var hp_fill: ColorRect = $Root/HPContainer/HPFill
@onready var hp_label: Label = $Root/HPContainer/HPLabel
@onready var banner: Label = $Root/Banner

func _ready() -> void:
	_bind_player()
	_bind_level()

func _bind_player() -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var player := players[0]
	player.health_changed.connect(_on_player_health_changed)
	player.died.connect(_on_player_died)
	_on_player_health_changed(player.current_health, Player.MAX_HEALTH)

func _bind_level() -> void:
	var levels := get_tree().get_nodes_in_group(&"level")
	if levels.is_empty():
		return
	var level := levels[0]
	level.cleared.connect(_on_level_cleared)

func _on_player_health_changed(current: int, max_value: int) -> void:
	var ratio := 0.0 if max_value <= 0 else clampf(float(current) / float(max_value), 0.0, 1.0)
	hp_fill.size.x = HP_BAR_WIDTH * ratio
	hp_label.text = "%d / %d" % [maxi(0, current), max_value]

func _on_player_died() -> void:
	_show_banner("You died", 2.0)

func _on_level_cleared() -> void:
	_show_banner("Level cleared", 2.5)

func _show_banner(text: String, duration: float) -> void:
	banner.text = text
	banner.visible = true
	await get_tree().create_timer(duration).timeout
	if not is_instance_valid(self):
		return
	banner.visible = false
