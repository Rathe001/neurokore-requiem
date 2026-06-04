extends Node

## Autoload registry for behavior mods. Loads every BehaviorMod .tres at
## startup, indexes them by id and by slot, and answers two questions
## the rest of the game asks:
##   1. "Give me the mods that can roll on this armor slot" → ItemRoller
##   2. "Is the mod equipped on this item currently active?" → tooltip
##      coloring + (eventually) effect dispatch
##
## File paths are listed explicitly rather than enumerated at runtime —
## DirAccess directory listing over res:// fails silently in exported
## Godot 4 builds (see project_resource_loader_gotcha memory). Adding a
## new mod = a new entry in _MOD_PATHS plus the .tres file.

## All known behavior mod resource paths. Add new mods here.
const _MOD_PATHS: Array[String] = [
	# Head
	"res://resources/behavior_mods/head/tactical_visor.tres",
	"res://resources/behavior_mods/head/radiant_halo.tres",
	"res://resources/behavior_mods/head/sensor_net.tres",
	"res://resources/behavior_mods/head/uv_lens.tres",
	# Chest
	"res://resources/behavior_mods/chest/kinetic_plating.tres",
	"res://resources/behavior_mods/chest/pain_compiler.tres",
	"res://resources/behavior_mods/chest/shock_discharge.tres",
	"res://resources/behavior_mods/chest/ghost_field.tres",
	# Hands
	"res://resources/behavior_mods/hands/quickdraw_servos.tres",
	"res://resources/behavior_mods/hands/reflex_loader.tres",
	"res://resources/behavior_mods/hands/static_grip.tres",
	"res://resources/behavior_mods/hands/berserker_lock.tres",
	# Legs
	"res://resources/behavior_mods/legs/servo_stride.tres",
	"res://resources/behavior_mods/legs/crouch_tactician.tres",
	"res://resources/behavior_mods/legs/slip_step.tres",
	"res://resources/behavior_mods/legs/glide_pads.tres",
	# Feet
	"res://resources/behavior_mods/feet/mag_boots.tres",
	"res://resources/behavior_mods/feet/recoil_soles.tres",
	"res://resources/behavior_mods/feet/phase_step.tres",
	"res://resources/behavior_mods/feet/silenced_treads.tres",
	# Back (slot id = "backpack")
	"res://resources/behavior_mods/back/jetpack.tres",
	"res://resources/behavior_mods/back/phase_cloak.tres",
	"res://resources/behavior_mods/back/drone_bay.tres",
	"res://resources/behavior_mods/back/ammo_reclamator.tres",
]

var _by_id: Dictionary = {}      # StringName id -> BehaviorMod
var _by_slot: Dictionary = {}    # StringName slot -> Array[BehaviorMod]


func _ready() -> void:
	# Run after SteamState/NetState (-100/-90) but before gameplay UI so
	# ItemRoller and tooltip code can query us during scene setup.
	process_priority = -85
	_load_all_mods()


func _load_all_mods() -> void:
	for path in _MOD_PATHS:
		if not ResourceLoader.exists(path):
			push_warning("[BehaviorModRegistry] missing mod resource: %s" % path)
			continue
		var mod := load(path) as BehaviorMod
		if mod == null:
			push_warning("[BehaviorModRegistry] failed to load: %s" % path)
			continue
		if mod.id == &"":
			push_warning("[BehaviorModRegistry] mod has empty id: %s" % path)
			continue
		_by_id[mod.id] = mod
		if not _by_slot.has(mod.slot):
			_by_slot[mod.slot] = ([] as Array[BehaviorMod])
		(_by_slot[mod.slot] as Array[BehaviorMod]).append(mod)


## Look up a mod by its id. Returns null if unknown — caller should
## treat a missing mod the same as "no mod rolled on this item."
func get_mod(id: StringName) -> BehaviorMod:
	if id == &"":
		return null
	return _by_id.get(id, null)


## All mods registered for a given armor slot. Empty array for slots
## without any mods (weapons/offhands/consumables). Caller MUST NOT
## mutate the returned array — it's the registry's backing storage.
func mods_for_slot(slot: StringName) -> Array[BehaviorMod]:
	return _by_slot.get(slot, [] as Array[BehaviorMod])


## Sub-array of mods_for_slot filtered by is_implemented. Used by
## ItemRoller's "preview-weight blend" to bias rolls toward already-
## working mods on most drops.
func implemented_mods_for_slot(slot: StringName) -> Array[BehaviorMod]:
	var out: Array[BehaviorMod] = []
	for mod in mods_for_slot(slot):
		if mod.is_implemented:
			out.append(mod)
	return out


## True when the mod identified by `id` is currently in its "active"
## state for the local player: implemented AND (no condition OR condition
## passes). Drives tooltip green/gray coloring and effect dispatch.
##
## Condition checks are placeholder for now — chunk #66 plumbs the actual
## condition_id → bool registry. Until then, any non-empty condition_id
## returns false (treated as "context not met").
func is_active(id: StringName) -> bool:
	var mod := get_mod(id)
	if mod == null:
		return false
	if not mod.is_implemented:
		return false
	if mod.condition_id == &"":
		return true
	return _check_condition(mod.condition_id)


# Condition registry. condition_id → Callable returning bool. Mods with
# a condition_id only fire their effects (and only show green in the
# tooltip) when the registered check passes. Add new conditions here as
# new conditional mods get authored — uncomment the example as a
# starting template.
const _CONDITION_CHECKS: Dictionary = {
	# &"wielding_laser_pistol": func() -> bool:
	#     var w: Item = InventoryState.get_equipped(&"weapon")
	#     return w != null and w.weapon_base_id == &"ranged_1h",
}


# Resolves a condition_id to a runtime bool. Unknown ids read as "not
# met" so a half-authored mod (the .tres mentions a condition but the
# check isn't registered yet) stays gray rather than silently turning
# on for everyone.
func _check_condition(condition_id: StringName) -> bool:
	var check: Callable = _CONDITION_CHECKS.get(condition_id, Callable())
	if not check.is_valid():
		return false
	return bool(check.call())


## Returns the BehaviorMod resource currently equipped in `slot`, or
## null if no item is equipped, the item has no mod, or the mod isn't
## registered.
func get_equipped_mod(slot: StringName) -> BehaviorMod:
	var item: Item = InventoryState.get_equipped(slot)
	if item == null:
		return null
	return get_mod(item.behavior_mod_id)


## True when the named mod is equipped in `slot` AND currently active
## (implemented + any condition met). The canonical "should this mod
## fire?" check for effect dispatch from gameplay code.
func is_mod_equipped_and_active(slot: StringName, mod_id: StringName) -> bool:
	var mod := get_equipped_mod(slot)
	if mod == null or mod.id != mod_id:
		return false
	return is_active(mod_id)


## Returns the rolled param value for the equipped mod in `slot` if and
## only if the mod is currently active. Returns `default` when no item
## equipped / no mod / mod not active / param key missing. Use this from
## gameplay code so unimplemented mods or unmet conditions silently
## leave the default behavior in place.
func get_active_param(slot: StringName, mod_id: StringName, key: StringName, default: float) -> float:
	if not is_mod_equipped_and_active(slot, mod_id):
		return default
	var item: Item = InventoryState.get_equipped(slot)
	if item == null:
		return default
	return float(item.mod_params.get(String(key), default))
