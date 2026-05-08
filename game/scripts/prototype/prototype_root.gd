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
var _spec_overlay: SpecSelectOverlay
@onready var _enemies_container: Node3D = get_node_or_null("EnemiesContainer") as Node3D


func _get_enemy_parent() -> Node3D:
	return _enemies_container if _enemies_container != null else self

## True when we're a non-host client in an active MP session. Enemy spawning,
## wave clears, and boss creation are host-only; clients receive enemy nodes
## via the MultiplayerSpawner on EnemiesContainer.
func _is_mp_client() -> bool:
	return NetState.is_in_lobby() and not NetState.is_host()

func _ready() -> void:
	add_to_group(&"corpse_manager")
	add_to_group(&"level_reset_handler")
	get_viewport().physics_object_picking = true
	EntityPool.warmup(ENEMY_SCENE, SPAWN_BATCH)
	_wire_switches()
	_move_player_to_spawn()
	if DebugState.config != null and DebugState.config.disable_enemies:
		_clear_enemies()
	elif spawn_boss_on_ready and not _is_mp_client():
		_spawn_boss()


# If the level placed a PrototypePlayerSpawn marker (via a player_spawn slot
# on a RoomDef), move the player to it. Levels without a marker keep the
# player at its scene-defined transform — preserves the prototype scene's
# fixed (0,0,-4) spawn while letting graph- and generator-driven levels
# decide their own spawn position.
func _move_player_to_spawn() -> void:
	var marker := get_tree().get_first_node_in_group(&"player_spawn") as Node3D
	if marker == null:
		return
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		return
	if player.has_method(&"set_spawn_position"):
		player.set_spawn_position(marker.global_position)
	else:
		player.global_position = marker.global_position

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
	# Debug spawning/clearing is host-only in MP — clients receive enemies via
	# the MultiplayerSpawner.
	if _is_mp_client():
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
	var player_node := get_tree().get_first_node_in_group(&"player")
	var player: Node3D = null
	if player_node != null and is_instance_valid(player_node):
		player = player_node as Node3D
	var center: Vector3 = player.global_position if player != null else Vector3.ZERO
	var parent := _get_enemy_parent()
	for i in count:
		var angle := randf() * TAU
		var radius := randf_range(spawn_min_radius, spawn_max_radius)
		var pos := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		var enemy := EntityPool.acquire(ENEMY_SCENE)
		parent.add_child(enemy)
		enemy.global_position = pos
		# Wipe any leftover affixes / named identity the pool occupant
		# carried — wave spawns are vanilla trash, not pack leaders or
		# named encounters. The cast is required: PrototypeEnemy.affixes
		# is Array[MonsterAffix] and Godot 4 won't auto-coerce `[]`.
		if "affixes" in enemy:
			enemy.affixes = [] as Array[MonsterAffix]
		if "named_monster" in enemy:
			enemy.named_monster = null
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
# player steps on the unlocked exit pad. Two paths depending on whether the
# layout is generator-driven:
#   - Generator (procgen): tear down everything, reroll seed, regenerate.
#     Player walks into a fresh layout each NG+. Player position resets via
#     the new spawn marker the rebuild places.
#   - Legacy (hand-authored pieces[]): in-place reset — respawn enemies at
#     scaled level, reset interactable states, keep geometry. Same level.
# PlayerState (level/XP) and InventoryState carry over either way.
func reset_level() -> void:
	# In MP, only the host resets the level — clients receive the rebuilt
	# enemies via MultiplayerSpawner. Full client-side NG+ coordination
	# (geometry rebuild, player teleport) is future work (Phase 4+).
	if _is_mp_client():
		return
	# Drop any active tooltip BEFORE freeing the world — otherwise an exit-pad
	# tooltip (or anything else hovered at the moment of interaction) keeps
	# showing because mouse_exited doesn't fire reliably when the anchor body
	# is removed from the tree mid-interaction.
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
	_clear_enemies()
	_clear_corpses()
	_clear_pickups()
	var builder := get_node_or_null("LevelBuilder") as LevelBuilder
	if builder != null and builder.layout != null and builder.layout.generator != null:
		# Procgen path: fresh layout per NG+. randi() may rarely be 0; the
		# generator falls back to wall-clock time in that case, so it's fine.
		await builder.rebuild(randi())
		# The freshly-built level placed a new player_spawn marker; teleport
		# the player there (and update their post-death respawn anchor).
		_move_player_to_spawn()
		# Rebake the minimap so it shows the new level geometry.
		get_tree().call_group(&"minimap", &"rebake")
	elif builder != null:
		# Legacy in-place reset — zone-level-based, not player-level.
		# center=2+offset, spread=1 → range [1+offset, 3+offset].
		var zoff := PlayerState.zone_level_offset()
		builder.respawn_enemies(2 + zoff, 1)
		if spawn_boss_on_ready:
			_spawn_boss()
		# Doors close + re-lock, switches clear, exit re-locks. Each interactable
		# joins "resettable" via HoverableInteractable._ready and provides its own
		# reset_state() override. Skipped on rebuild — those nodes were freed.
		get_tree().call_group(&"resettable", &"reset_state")

	# First completion: let the player choose a specialization before continuing.
	if PlayerState.new_game_plus == 0:
		_show_spec_select()
	else:
		_reset_player()

func _show_spec_select() -> void:
	if _spec_overlay == null:
		_spec_overlay = SpecSelectOverlay.new()
		add_child(_spec_overlay)
		_spec_overlay.class_selected.connect(_on_spec_selected)
	_spec_overlay.show_for_origin(PlayerState.class_id)

func _on_spec_selected(class_id: StringName, spec_id: StringName) -> void:
	PlayerState.set_class_and_spec(class_id, spec_id)
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
	if PlayerState.active_save_id != "":
		SaveManager.save_game(PlayerState.active_save_id)

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
	# Wipe any leftover affixes / named identity — bosses use is_boss for
	# their stat boost, not pack/named overrides. Cast required (see boss
	# spawn comment).
	if "affixes" in boss:
		boss.affixes = [] as Array[MonsterAffix]
	if "named_monster" in boss:
		boss.named_monster = null
	_get_enemy_parent().add_child(boss)
	boss.global_position = boss_spawn
	if boss.has_method(&"reset"):
		boss.reset()
