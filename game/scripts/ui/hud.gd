extends CanvasLayer
class_name HUD

# Screen-space overlay. Binds to the player and level via groups on
# _ready so it doesn't need direct node paths. HP + resource bars and
# skill slots mirror the player's state; the banner shows transient
# messages (death, level cleared, etc).

const HP_BAR_WIDTH := 176.0
const RESOURCE_BAR_WIDTH := 176.0

const SLOT_LABELS: Array[String] = ["LMB", "RMB", "1", "2", "3", "4", "Q", "E"]

@onready var hp_fill: ColorRect = $Root/HPContainer/HPFill
@onready var hp_label: Label = $Root/HPContainer/HPLabel
@onready var resource_fill: ColorRect = $Root/ResourceContainer/ResourceFill
@onready var resource_label: Label = $Root/ResourceContainer/ResourceLabel
@onready var skill_bar: Control = $Root/SkillBar
@onready var banner: Label = $Root/Banner
@onready var tooltip: PanelContainer = $Root/Tooltip
@onready var tooltip_text: Label = $Root/Tooltip/Text
@onready var fade_overlay: ColorRect = $Root/FadeOverlay

func _ready() -> void:
	add_to_group(&"hud")
	_bind_player()
	_bind_level()

func _process(_delta: float) -> void:
	if tooltip.visible:
		tooltip.position = get_viewport().get_mouse_position() + Vector2(16, 16)

func show_tooltip(text: String) -> void:
	tooltip_text.text = text
	tooltip.visible = true

func hide_tooltip() -> void:
	tooltip.visible = false

func fade_out(duration: float = 0.25) -> void:
	await _tween_fade(1.0, duration)

func fade_in(duration: float = 0.25) -> void:
	await _tween_fade(0.0, duration)

func _tween_fade(target_alpha: float, duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade_overlay, "color:a", target_alpha, duration)
	await tween.finished

func _bind_player() -> void:
	var players := get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var player := players[0] as Player
	player.health_changed.connect(_on_player_health_changed)
	player.resource_changed.connect(_on_resource_changed)
	player.died.connect(_on_player_died)
	_on_player_health_changed(player.current_health, Player.MAX_HEALTH)
	_bind_skill_slots(player)
	_bind_resource_pool(player.resource_pool)

func _bind_skill_slots(player: Player) -> void:
	for i in SLOT_LABELS.size():
		var slot := skill_bar.get_node_or_null("Slot%d" % i) as SkillSlot
		if slot == null:
			continue
		var skill: Skill = null
		if i < player.skills.size():
			skill = player.skills[i]
		slot.bind(player, skill, SLOT_LABELS[i])

func _bind_resource_pool(pool: ResourcePool) -> void:
	if pool == null:
		_on_resource_changed(0, 0)
		return
	resource_fill.color = pool.color
	_on_resource_changed(pool.start_value, pool.max_value)

func _bind_level() -> void:
	var levels := get_tree().get_nodes_in_group(&"level")
	if levels.is_empty():
		return
	bind_level(levels[0])

func bind_level(level: Node) -> void:
	if not level.cleared.is_connected(_on_level_cleared):
		level.cleared.connect(_on_level_cleared)

func _on_player_health_changed(current: int, max_value: int) -> void:
	var ratio := 0.0 if max_value <= 0 else clampf(float(current) / float(max_value), 0.0, 1.0)
	hp_fill.size.x = HP_BAR_WIDTH * ratio
	hp_label.text = "%d / %d" % [maxi(0, current), max_value]

func _on_resource_changed(current: int, max_value: int) -> void:
	var ratio := 0.0 if max_value <= 0 else clampf(float(current) / float(max_value), 0.0, 1.0)
	resource_fill.size.x = RESOURCE_BAR_WIDTH * ratio
	resource_label.text = "%d / %d" % [maxi(0, current), max_value]

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
