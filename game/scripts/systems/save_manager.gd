extends Node

# Save manager — serialises character state to JSON files under user://saves/.
# One file per character. Forward-compatible: every deserialize read uses
# .get(key, default) so old saves survive new fields without migration.
# Version bumps are reserved for structural renames or type changes.
#
# Designed for Steam Cloud: plain JSON files that Steam Remote Storage can
# sync without changes to the serialization layer. character_id (UUID) is the
# stable identity for multiplayer; save_id is the local file identifier.

const SAVE_DIR := "user://saves/"
const CURRENT_SAVE_VERSION := 1

## Autosave interval in seconds. Fires only when a character is loaded
## (active_save_id is set) and a player node exists in the tree.
const AUTOSAVE_INTERVAL := 120.0

var _autosave_timer: Timer

func _ready() -> void:
	_ensure_save_dir()
	get_tree().set_auto_accept_quit(false)
	_autosave_timer = Timer.new()
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_on_autosave)
	add_child(_autosave_timer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()


# Ordered shutdown — addresses the AMD driver crash report (yesterday's
# user). Tearing down Steam state and pooled GPU resources BEFORE the
# engine's own teardown gives Vulkan a clean state to unwind from.
# Without this, AMD's driver was hitting the swap chain destruction
# while shockwave_bubble.gdshader / chromatic_aberration.gdshader still
# held screen_tex sampler references on pooled projectiles.
#
# Order, top to bottom:
#   1. Save — happens BEFORE any teardown that could mutate state.
#   2. Leave global chat — low-impact lobby with no peer connections.
#   3. Leave gameplay lobby — releases the SteamMultiplayerPeer.
#   4. EntityPool.clear — frees pooled projectiles / VFX / lights so
#      their ShaderMaterials drop screen_tex references before the
#      renderer starts unwinding.
#   5. Steam.run_callbacks — pumps a few frames so leave/disconnect
#      packets actually flush instead of getting orphaned in the queue.
#   6. quit.
func _shutdown() -> void:
	if PlayerState.active_save_id != "":
		save_game(PlayerState.active_save_id)
	if Engine.has_singleton(&"GlobalChatState") or get_node_or_null(^"/root/GlobalChatState") != null:
		GlobalChatState.leave_global_chat()
	NetState.leave_lobby()
	EntityPool.clear()
	# Pump Steam's callback queue a few times so the leave packets land
	# before the engine destroys the runtime. run_callbacks() is normally
	# ticked once per frame in SteamState — at WM_CLOSE_REQUEST we're
	# past the last frame, so we pump it manually here.
	if SteamState.initialized:
		for _i in 4:
			Steam.run_callbacks()
	get_tree().quit()


func _on_autosave() -> void:
	if PlayerState.active_save_id == "":
		return
	# Only save when a player node exists — avoids writing empty state
	# during menus or scene transitions.
	if get_tree().get_first_node_in_group(&"player") == null:
		return
	save_game(PlayerState.active_save_id)


# ── Public API ────────────────────────────────────────────────────────────

## Save current game state. Returns the save_id used. Pass empty string to
## generate a new ID (first save for a new character).
func save_game(save_id: String = "") -> String:
	if save_id == "":
		save_id = _generate_save_id()
	PlayerState.active_save_id = save_id

	var data := {
		"save_version": CURRENT_SAVE_VERSION,
		"save_id": save_id,
		"save_timestamp": Time.get_datetime_string_from_system(true),
		"character_id": PlayerState.character_id,
		"player": _serialize_player(),
		"equipment": _serialize_equipment(),
		"inventory": _serialize_inventory(),
	}

	var json_str := JSON.stringify(data, "\t")
	var path := SAVE_DIR + save_id + ".json"
	var tmp_path := SAVE_DIR + save_id + ".tmp"

	# Write to a temp file first so a crash mid-write doesn't corrupt the
	# real save. Only rename once the full JSON is safely on disk.
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("[SaveManager] Failed to open temp save file: %s (error %d)" % [tmp_path, FileAccess.get_open_error()])
		return save_id
	file.store_string(json_str)
	file.close()

	# Verify the temp file parses before replacing the real save.
	var verify := FileAccess.open(tmp_path, FileAccess.READ)
	if verify == null:
		push_error("[SaveManager] Temp save vanished after write: %s" % tmp_path)
		return save_id
	var verify_json := JSON.new()
	var verify_ok := verify_json.parse(verify.get_as_text()) == OK
	verify.close()
	if not verify_ok:
		push_error("[SaveManager] Temp save is invalid JSON — aborting: %s" % tmp_path)
		DirAccess.remove_absolute(tmp_path)
		return save_id

	# Atomic swap: remove old, rename temp → real.
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp_path, path)
	return save_id


## Load a save file into the autoload singletons. Returns true on success.
func load_game(save_id: String) -> bool:
	var path := SAVE_DIR + save_id + ".json"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[SaveManager] Save file not found: %s" % path)
		return false
	var json_str := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_str) != OK:
		push_warning("[SaveManager] Failed to parse save JSON: %s" % path)
		return false
	var data: Dictionary = json.data
	if not data is Dictionary:
		push_warning("[SaveManager] Save root is not a Dictionary: %s" % path)
		return false

	data = _migrate(data)

	_deserialize_player(data.get("player", {}))
	_deserialize_equipment(data.get("equipment", {}))
	_deserialize_inventory(data.get("inventory", []))

	PlayerState.active_save_id = save_id
	PlayerState.character_id = str(data.get("character_id", ""))
	return true


## Delete a save file (hardcore permadeath, or manual deletion).
func delete_save(save_id: String) -> void:
	var path := SAVE_DIR + save_id + ".json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## Returns a list of save summaries sorted by timestamp (newest first).
## Each entry: {save_id, player_name, class_id, spec_id, level, hardcore, save_timestamp, character_id, avatar_id, gender}
func list_saves() -> Array[Dictionary]:
	var saves: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return saves
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".json"):
			var summary := _read_save_summary(SAVE_DIR + filename)
			if not summary.is_empty():
				saves.append(summary)
		filename = dir.get_next()
	dir.list_dir_end()
	saves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("save_timestamp", "")) > str(b.get("save_timestamp", ""))
	)
	return saves


func has_any_saves() -> bool:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	dir.list_dir_begin()
	var filename := dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".json"):
			dir.list_dir_end()
			return true
		filename = dir.get_next()
	dir.list_dir_end()
	return false


# ── Migration ─────────────────────────────────────────────────────────────

func _migrate(data: Dictionary) -> Dictionary:
	var v: int = int(data.get("save_version", 0))
	# Future migrations go here:
	# if v < 2:
	#     data = _migrate_1_to_2(data)
	data["save_version"] = CURRENT_SAVE_VERSION
	return data


# ── Serialization: Player ─────────────────────────────────────────────────

func _serialize_player() -> Dictionary:
	var credits := 0
	var resource_current := 0.0
	var level_hp_bonus := 0
	var health_current := -1
	var player := get_tree().get_first_node_in_group(&"player")
	if player != null and player.has_method(&"get_credits"):
		credits = player.get_credits()
	else:
		credits = PlayerState.saved_credits
	if player != null and "resource_pool" in player and player.resource_pool != null:
		resource_current = player._resource_current
	else:
		resource_current = PlayerState.saved_resource_current
	if player != null:
		level_hp_bonus = player._level_hp_bonus
		health_current = player._health
	else:
		level_hp_bonus = PlayerState.saved_level_hp_bonus
		health_current = PlayerState.saved_health

	return {
		"class_id": str(PlayerState.class_id),
		"spec_id": str(PlayerState.spec_id),
		"gender": str(PlayerState.gender),
		"avatar_id": PlayerState.avatar_id,
		"player_name": PlayerState.player_name,
		"hardcore": PlayerState.hardcore,
		"mode_id": str(PlayerState.mode_id),
		"level": PlayerState.level,
		"xp": PlayerState.xp,
		"xp_to_next": PlayerState.xp_to_next,
		"talent_points_total": PlayerState.talent_points_total,
		"new_game_plus": PlayerState.new_game_plus,
		"credits": credits,
		"resource_current": resource_current,
		"level_hp_bonus": level_hp_bonus,
		"health_current": health_current,
		"talent_allocations": _serialize_talent_allocations(),
	}


func _deserialize_player(data: Dictionary) -> void:
	PlayerState.class_id = StringName(data.get("class_id", ""))
	PlayerState.spec_id = StringName(data.get("spec_id", ""))
	PlayerState.gender = StringName(data.get("gender", "male"))
	PlayerState.avatar_id = int(data.get("avatar_id", 0))
	PlayerState.player_name = str(data.get("player_name", ""))
	PlayerState.hardcore = bool(data.get("hardcore", false))
	# Legacy saves predate the SP/MP split — default to "sp" so they
	# stay in the single-player roster instead of leaking into MP.
	PlayerState.mode_id = StringName(data.get("mode_id", "sp"))
	PlayerState.level = int(data.get("level", 1))
	PlayerState.xp = int(data.get("xp", 0))
	PlayerState.xp_to_next = int(data.get("xp_to_next", PlayerState.STARTING_XP_TO_NEXT))
	PlayerState.talent_points_total = int(data.get("talent_points_total", 0))
	PlayerState.new_game_plus = int(data.get("new_game_plus", 0))
	PlayerState.saved_credits = int(data.get("credits", 0))
	PlayerState.saved_resource_current = float(data.get("resource_current", 0.0))
	PlayerState.saved_level_hp_bonus = int(data.get("level_hp_bonus", 0))
	PlayerState.saved_health = int(data.get("health_current", -1))
	_deserialize_talent_allocations(data.get("talent_allocations", {}))
	# Trigger recomputation in dependent systems.
	PlayerState.class_changed.emit(PlayerState.class_id)
	PlayerState.spec_changed.emit(PlayerState.spec_id)
	PlayerState.talents_changed.emit()


# ── Serialization: Talents ────────────────────────────────────────────────

func _serialize_talent_allocations() -> Dictionary:
	var out := {}
	for stat_id: StringName in PlayerState.talent_allocations.keys():
		out[str(stat_id)] = PlayerState.talent_allocations[stat_id].duplicate(true)
	return out


func _deserialize_talent_allocations(data: Dictionary) -> void:
	PlayerState.talent_allocations.clear()
	for key: String in data.keys():
		var stat_id := StringName(key)
		var tiers: Array = data[key]
		PlayerState.talent_allocations[stat_id] = tiers


# ── Serialization: Equipment ──────────────────────────────────────────────

func _serialize_equipment() -> Dictionary:
	var out := {}
	for slot: StringName in InventoryState.equipment.keys():
		var item: Item = InventoryState.equipment[slot]
		out[str(slot)] = _serialize_item(item) if item != null else null
	return out


func _deserialize_equipment(data: Dictionary) -> void:
	InventoryState.equipment.clear()
	for key: String in data.keys():
		var slot := StringName(key)
		var item_data = data[key]
		if item_data != null and item_data is Dictionary:
			var item := _deserialize_item(item_data)
			if item != null:
				InventoryState.equipment[slot] = item
	InventoryState.equipment_changed.emit(&"")


# ── Serialization: Inventory ──────────────────────────────────────────────

func _serialize_inventory() -> Array:
	var out: Array = []
	for item: Item in InventoryState.inventory:
		out.append(_serialize_item(item) if item != null else null)
	return out


func _deserialize_inventory(data: Array) -> void:
	InventoryState.inventory.resize(InventoryState.MAX_INVENTORY_SIZE)
	InventoryState.inventory.fill(null)
	for i in mini(data.size(), InventoryState.MAX_INVENTORY_SIZE):
		var item_data = data[i]
		if item_data != null and item_data is Dictionary:
			InventoryState.inventory[i] = _deserialize_item(item_data)
	InventoryState.capacity_changed.emit()


# ── Serialization: Item ───────────────────────────────────────────────────

func _serialize_item(item: Item) -> Dictionary:
	if item == null:
		return {}
	var d := {
		"id": str(item.id),
		"name_key": item.name_key,
		"description_key": item.description_key,
		"kind": str(item.kind),
		"main_type": item.main_type,
		"sub_type": item.sub_type,
		"rarity": str(item.rarity),
		"glyph": item.glyph,
		"glyph_color": _color_to_array(item.glyph_color),
		"item_level": item.item_level,
		"two_handed": item.two_handed,
		"fire_skill": item.fire_skill.resource_path if item.fire_skill != null else "",
		"alt_fire_skill": item.alt_fire_skill.resource_path if item.alt_fire_skill != null else "",
		"weapon_base_id": str(item.weapon_base_id),
		"damage_min": item.damage_min,
		"damage_max": item.damage_max,
		"attack_speed": item.attack_speed,
		"crit_chance": item.crit_chance,
		"accuracy": item.accuracy,
		"weapon_range": item.weapon_range,
		"blast_radius": item.blast_radius,
		"light_mod": int(item.light_mod),
		"light_energy": item.light_energy,
		"light_range": item.light_range,
		"light_color": _color_to_array(item.light_color),
		"stat_modifiers": _serialize_stat_modifiers(item.stat_modifiers),
	}
	return d


func _deserialize_item(data: Dictionary) -> Item:
	if data.is_empty():
		return null
	var item := Item.new()
	item.id = StringName(data.get("id", ""))
	item.name_key = str(data.get("name_key", ""))
	item.description_key = str(data.get("description_key", ""))
	item.kind = StringName(data.get("kind", ""))
	item.main_type = str(data.get("main_type", ""))
	item.sub_type = str(data.get("sub_type", ""))
	item.rarity = StringName(data.get("rarity", "common"))
	item.glyph = str(data.get("glyph", "?"))
	item.glyph_color = _array_to_color(data.get("glyph_color", [1, 1, 1, 1]))
	item.item_level = int(data.get("item_level", 1))
	item.two_handed = bool(data.get("two_handed", false))

	var fire_path: String = data.get("fire_skill", "")
	item.fire_skill = load(fire_path) as Skill if fire_path != "" and ResourceLoader.exists(fire_path) else null
	var alt_path: String = data.get("alt_fire_skill", "")
	item.alt_fire_skill = load(alt_path) as Skill if alt_path != "" and ResourceLoader.exists(alt_path) else null

	item.weapon_base_id = StringName(data.get("weapon_base_id", ""))
	item.damage_min = int(data.get("damage_min", 0))
	item.damage_max = int(data.get("damage_max", 0))
	item.attack_speed = float(data.get("attack_speed", 1.0))
	item.crit_chance = float(data.get("crit_chance", 0.0))
	item.accuracy = float(data.get("accuracy", 1.0))
	item.weapon_range = float(data.get("weapon_range", 3.0))
	item.blast_radius = float(data.get("blast_radius", 0.0))

	var lm: int = int(data.get("light_mod", 0))
	item.light_mod = lm as Item.LightMod if lm >= 0 and lm <= 4 else Item.LightMod.NONE
	item.light_energy = float(data.get("light_energy", 1.2))
	item.light_range = float(data.get("light_range", 12.0))
	item.light_color = _array_to_color(data.get("light_color", [1, 1, 1, 1]))
	item.stat_modifiers = _deserialize_stat_modifiers(data.get("stat_modifiers", {}))
	return item


# ── Helpers ───────────────────────────────────────────────────────────────

func _serialize_stat_modifiers(mods: Dictionary) -> Dictionary:
	var out := {}
	for key in mods.keys():
		out[str(key)] = mods[key]
	return out


func _deserialize_stat_modifiers(data: Dictionary) -> Dictionary:
	var out := {}
	for key: String in data.keys():
		out[StringName(key)] = data[key]
	return out


static func _color_to_array(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]


static func _array_to_color(a) -> Color:
	if a is Array and a.size() >= 4:
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Color.WHITE


func _generate_save_id() -> String:
	var dt := Time.get_datetime_dict_from_system()
	var hex := "%04x" % (randi() & 0xFFFF)
	return "%04d%02d%02d_%02d%02d%02d_%s" % [dt["year"], dt["month"], dt["day"], dt["hour"], dt["minute"], dt["second"], hex]


func _ensure_save_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


## Read just the summary fields from a save file without fully deserializing.
func _read_save_summary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json_str := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return {}
	var data: Dictionary = json.data
	if not data is Dictionary:
		return {}
	var player: Dictionary = data.get("player", {})
	return {
		"save_id": str(data.get("save_id", "")),
		"character_id": str(data.get("character_id", "")),
		"save_timestamp": str(data.get("save_timestamp", "")),
		"player_name": str(player.get("player_name", "")),
		"class_id": str(player.get("class_id", "")),
		"spec_id": str(player.get("spec_id", "")),
		"level": int(player.get("level", 1)),
		"hardcore": bool(player.get("hardcore", false)),
		"mode_id": str(player.get("mode_id", "sp")),
		"avatar_id": int(player.get("avatar_id", 0)),
		"gender": str(player.get("gender", "male")),
	}
