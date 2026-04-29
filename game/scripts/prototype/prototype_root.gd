extends Node3D
class_name PrototypeRoot

const ENEMY_SCENE: PackedScene = preload("res://scenes/prototype/prototype_enemy.tscn")

const SPAWN_BATCH := 25
const MAX_CORPSES := 100
const PLAYER_SPAWN := Vector3(0.0, 0.0, -4.0)
const BOSS_SCENE: PackedScene = preload("res://scenes/prototype/prototype_enemy.tscn")

@export var spawn_min_radius: float = 8.0
@export var spawn_max_radius: float = 14.0
# Boss is spawned at this world position on level start and on every level
# reset. Leave at zero to skip boss creation (e.g. test scenes).
@export var boss_spawn: Vector3 = Vector3.ZERO
@export var spawn_boss_on_ready: bool = false

var _corpses: Array[Node3D] = []
var _corpse_head: int = 0

func _ready() -> void:
	add_to_group(&"corpse_manager")
	add_to_group(&"level_reset_handler")
	get_viewport().physics_object_picking = true
	EntityPool.warmup(ENEMY_SCENE, SPAWN_BATCH)
	_wire_switches()
	if DebugState.config != null and DebugState.config.disable_enemies:
		_clear_enemies()
	elif spawn_boss_on_ready:
		_spawn_boss()

func _wire_switches() -> void:
	var builder := get_node_or_null("LevelBuilder") as LevelBuilder
	if builder == null:
		return
	# All three switches feed the boss arena east door (unlocks_required = 3).
	# The west door auto-unlocks on boss death via the "boss_listeners" group,
	# so it doesn't need wiring here.
	var boss_door := builder.get_door(&"boss_arena", RoomDef.Wall.EAST)
	if boss_door == null:
		return
	for sw_name in [&"SwitchPower", &"SwitchContainment", &"SwitchObservation"]:
		var sw := get_node_or_null(NodePath(sw_name)) as PrototypeSwitch
		if sw != null:
			sw.target_door = sw.get_path_to(boss_door)

func _unhandled_input(event: InputEvent) -> void:
	if not BuildInfo.dev_tools_enabled():
		return
	if event.is_action_pressed(&"debug_horde_spawn"):
		if DebugState.config != null and DebugState.config.disable_enemies:
			return
		_spawn_wave(SPAWN_BATCH)
	elif event.is_action_pressed(&"debug_horde_clear"):
		_clear_enemies()
		_clear_corpses()

func register_corpse(corpse: Node3D) -> void:
	if _corpses.size() < MAX_CORPSES:
		_corpses.append(corpse)
	else:
		var oldest: Node3D = _corpses[_corpse_head]
		if is_instance_valid(oldest):
			EntityPool.release(oldest)
		_corpses[_corpse_head] = corpse
		_corpse_head = (_corpse_head + 1) % MAX_CORPSES

func corpse_count() -> int:
	return _corpses.size()

func _spawn_wave(count: int) -> void:
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	var center: Vector3 = player.global_position if player != null else Vector3.ZERO
	for i in count:
		var angle := randf() * TAU
		var radius := randf_range(spawn_min_radius, spawn_max_radius)
		var pos := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var enemy := EntityPool.acquire(ENEMY_SCENE)
		add_child(enemy)
		enemy.global_position = pos
		if enemy.has_method(&"reset"):
			enemy.reset()

func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group(&"enemies"):
		SpatialGrid.unregister(e)
		EntityPool.release(e)

func _clear_corpses() -> void:
	for c in _corpses:
		if is_instance_valid(c):
			EntityPool.release(c)
	_corpses.clear()
	_corpse_head = 0

# Drops accumulate in the &"pickups" group across level resets. Without this,
# every NG+ run leaves the floor more cluttered with the previous run's loot.
func _clear_pickups() -> void:
	for p in get_tree().get_nodes_in_group(&"pickups"):
		SpatialGrid.unregister(p)
		p.queue_free()

# Group dispatch from PrototypeExit.interact() once the boss is dead and the
# player steps on the unlocked exit pad. Wipes the field, re-rolls every spawn
# at the player's current level (±1), respawns the boss, and snaps the player
# back to the start. PlayerState (level/XP) and InventoryState carry over.
func reset_level() -> void:
	_clear_enemies()
	_clear_corpses()
	_clear_pickups()
	var builder := get_node_or_null("LevelBuilder") as LevelBuilder
	if builder != null:
		builder.respawn_enemies(PlayerState.level)
	if spawn_boss_on_ready:
		_spawn_boss()
	# Doors close + re-lock, switches clear, exit re-locks. Each interactable
	# joins "resettable" via HoverableInteractable._ready and provides its own
	# reset_state() override.
	get_tree().call_group(&"resettable", &"reset_state")
	_reset_player()

func _reset_player() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	if player == null:
		return
	if player.has_method(&"respawn"):
		player.respawn()
	PlayerState.new_game_plus += 1
	if player.has_signal(&"notification_requested"):
		player.emit_signal(&"notification_requested", tr(&"HUD_BANNER_LEVEL_RESET") % PlayerState.new_game_plus)

func _spawn_boss() -> void:
	if boss_spawn == Vector3.ZERO:
		return
	var boss := EntityPool.acquire(BOSS_SCENE)
	# Set identity before add_child so the first _init_enemy pass applies boss
	# stats directly and skips the trash display-name roll. Without this, fresh
	# (un-pooled) instances run trash setup, then re-init through reset() — the
	# trash floor-ring tint can briefly flicker before the boss tint replaces it.
	if "is_boss" in boss:
		boss.is_boss = true
	if "display_name" in boss:
		boss.display_name = "Pickle"
	add_child(boss)
	boss.global_position = boss_spawn
	if boss.has_method(&"reset"):
		boss.reset()
