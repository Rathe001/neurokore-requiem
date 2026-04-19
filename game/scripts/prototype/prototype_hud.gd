extends CanvasLayer

const HP_BAR_WIDTH := 196.0
const RESOURCE_BAR_WIDTH := 196.0
const LOW_HP_RATIO := 0.35
const FULL_HP_COLOR := Color(0.3, 0.95, 1.0, 1.0)
const LOW_HP_COLOR := Color(1.0, 0.25, 0.3, 1.0)

const SLOT_LABELS: Array[String] = ["LMB", "RMB", "1", "2", "3", "4", "Q", "E"]

@onready var hp_fill: ColorRect = %HPFill
@onready var hp_label: Label = %HPLabel
@onready var resource_fill: ColorRect = %ResourceFill
@onready var resource_label: Label = %ResourceLabel
@onready var skill_bar: Control = %SkillBar
@onready var banner: Label = %Banner
@onready var debug_label: Label = %DebugLabel
@onready var credits_label: Label = %CreditsLabel
@onready var pause_menu: Node = %PauseMenu

var _max_health: int = 1
var _banner_token: int = 0

func _ready() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		push_warning("[prototype_hud] no player in group")
		return
	_max_health = int(player.max_health)
	if player.has_signal(&"health_changed"):
		player.health_changed.connect(_on_health_changed)
	if player.has_signal(&"resource_changed"):
		player.resource_changed.connect(_on_resource_changed)
	if player.has_signal(&"died"):
		player.died.connect(_on_player_died)
	if player.has_signal(&"credits_changed"):
		player.credits_changed.connect(_on_credits_changed)
	_on_health_changed(_max_health, _max_health)
	_on_credits_changed(player.get_credits() if player.has_method(&"get_credits") else 0)
	_bind_skill_slots(player)
	_bind_resource_pool(player)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	for modal in get_tree().get_nodes_in_group(&"ui_modal"):
		if modal == pause_menu:
			continue
		if modal.visible:
			modal.call(&"close_menu")
			get_viewport().set_input_as_handled()
			return
	if pause_menu.visible:
		pause_menu.close_menu()
	else:
		pause_menu.open_menu()
	get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	var fps := Engine.get_frames_per_second()
	var frame_ms := 1000.0 / maxf(float(fps), 1.0)
	var enemy_count := get_tree().get_nodes_in_group(&"enemies").size()
	var corpse_count := get_tree().get_nodes_in_group(&"corpses").size()
	debug_label.text = "FPS: %d  (%.1f ms)\nEnemies: %d  Corpses: %d\n[F1] +25  [F2] clear" % [fps, frame_ms, enemy_count, corpse_count]

func _bind_skill_slots(player: Node) -> void:
	var skills: Array = player.skills
	for i in SLOT_LABELS.size():
		var slot := skill_bar.get_node_or_null("Slot%d" % i) as SkillSlot
		if slot == null:
			continue
		var skill: Skill = skills[i] if i < skills.size() else null
		slot.bind(player, skill, SLOT_LABELS[i])

func _bind_resource_pool(player: Node) -> void:
	var pool: ResourcePool = player.resource_pool
	if pool == null:
		resource_fill.size.x = 0.0
		resource_label.text = "—"
		return
	resource_fill.color = pool.color
	_on_resource_changed(pool.start_value, pool.max_value)

func _on_health_changed(current: int, max_value: int) -> void:
	_max_health = max(max_value, 1)
	var ratio := clampf(float(current) / float(_max_health), 0.0, 1.0)
	hp_fill.size.x = HP_BAR_WIDTH * ratio
	hp_fill.color = FULL_HP_COLOR if ratio > LOW_HP_RATIO else LOW_HP_COLOR
	hp_label.text = "%d / %d" % [max(current, 0), _max_health]

func _on_resource_changed(current: int, max_value: int) -> void:
	var ratio := 0.0 if max_value <= 0 else clampf(float(current) / float(max_value), 0.0, 1.0)
	resource_fill.size.x = RESOURCE_BAR_WIDTH * ratio
	resource_label.text = "%d / %d" % [max(current, 0), max_value]

func _on_credits_changed(amount: int) -> void:
	credits_label.text = "%d cr" % amount

func _on_player_died() -> void:
	_show_banner("You died", 2.0)

func _show_banner(text: String, duration: float) -> void:
	_banner_token += 1
	var token := _banner_token
	banner.text = text
	banner.visible = true
	await get_tree().create_timer(duration).timeout
	if token == _banner_token:
		banner.visible = false
