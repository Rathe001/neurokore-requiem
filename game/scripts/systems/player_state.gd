extends Node

# Runtime state for the active player character. Populated by the startup
# screen before the game scene loads; consumed by the player on _ready.

signal class_changed(class_id: StringName)
signal spec_changed(spec_id: StringName)
signal talents_changed
signal level_changed(new_level: int, old_level: int)
signal xp_changed(current_xp: int, xp_to_next: int)
signal leveled_up(new_level: int, hp_gain: int)

# XP curve: each level requires ~1.35× the previous, so leveling slows as you
# climb. With XP_PER_ENEMY_LEVEL=20, a level-1 enemy is 20 xp; a level-5 enemy
# is 100. Tuned for friends-mode demo pacing.
const STARTING_XP_TO_NEXT := 100
const XP_CURVE_GROWTH := 1.35
const XP_PER_ENEMY_LEVEL := 20
const HP_GAIN_PER_LEVEL_MIN := 20
const HP_GAIN_PER_LEVEL_MAX := 25
const TALENT_POINTS_PER_LEVEL := 1

var class_id: StringName = &""
var spec_id: StringName = &""
var gender: StringName = &"male"
## Selected avatar index (1..5). 0 means none chosen — HUD falls back to
## a text-only level display.
var avatar_id: int = 0
## Player-entered display name. Empty = no name shown in HUD.
var player_name: String = ""


# Loads the portrait matching the current class/gender/avatar_id selection.
# Returns null when any are unset, so the HUD can fall back gracefully for
# the legacy prototype scene (which bypasses character creation).
func avatar_texture() -> Texture2D:
	if avatar_id < 1 or avatar_id > 5:
		return null
	if class_id != &"analog" and class_id != &"cyborg":
		return null
	if gender != &"male" and gender != &"female":
		return null
	var path := "res://assets/ui/avatars/%s_%s%d.png" % [gender, class_id, avatar_id]
	return load(path) as Texture2D

## Total talent points granted by leveling. +1 per level-up; starts at 0.
var talent_points_total: int = 0

## Player progression. Level 1 = fresh character, no XP.
var level: int = 1
var xp: int = 0
var xp_to_next: int = STARTING_XP_TO_NEXT

## Number of times the player has cleared the level and triggered a reset.
## Drives the "New Game +N" banner.
var new_game_plus: int = 0

## Spent talent points per stat tree.
## Layout: { stat_id: [[bool]*8]*3 } — 3 tiers × 8 nodes each.
var talent_allocations: Dictionary = {}

## Spent talent points for kore nodes.
## Layout: [[bool]*4]*3 — 3 tiers × 4 nodes.
var kore_node_allocations: Array = []

var _cached_tiers: Dictionary = {}
var _cached_origin_tier: int = -1
var _cached_kore_nodes_tier: int = -1

func _ready() -> void:
	pass

# ── Class / spec identity ─────────────────────────────────────────────────────

func set_class(id: StringName) -> void:
	if class_id == id:
		return
	class_id = id
	spec_id = &""
	reset_talents()
	class_changed.emit(class_id)
	spec_changed.emit(spec_id)

func set_spec(id: StringName) -> void:
	if spec_id == id:
		return
	spec_id = id
	_reset_tier_cache()
	spec_changed.emit(spec_id)

func set_class_and_spec(new_class: StringName, new_spec: StringName) -> void:
	var class_diff := class_id != new_class
	var spec_diff := spec_id != new_spec
	class_id = new_class
	spec_id = new_spec
	if class_diff:
		reset_talents()
	_reset_tier_cache()
	if class_diff:
		class_changed.emit(class_id)
	if spec_diff:
		spec_changed.emit(spec_id)

# ── Talent allocations ────────────────────────────────────────────────────────

func set_talent_alloc(stat: StringName, tier: int, node: int, allocated: bool) -> void:
	if not talent_allocations.has(stat):
		var rows: Array = []
		for _i in 5:
			rows.append(_make_node_row(8))
		talent_allocations[stat] = rows
	talent_allocations[stat][tier][node] = allocated
	talents_changed.emit()

func set_kore_node_alloc(tier: int, node: int, allocated: bool) -> void:
	if kore_node_allocations.is_empty():
		var rows: Array = []
		for _i in 3:
			rows.append(_make_node_row(4))
		kore_node_allocations = rows
	kore_node_allocations[tier][node] = allocated
	talents_changed.emit()

static func _make_node_row(count: int) -> Array:
	var row: Array = []
	row.resize(count)
	row.fill(false)
	return row

func get_talent_points_spent() -> int:
	var total := 0
	for tier_rows in talent_allocations.values():
		for node_row in tier_rows:
			for allocated in node_row:
				if allocated:
					total += 1
	for tier_row in kore_node_allocations:
		for allocated in tier_row:
			if allocated:
				total += 1
	return total

## True if a stat tree node has a point allocated (regardless of tier unlock state).
func is_talent_allocated(stat: StringName, tier: int, node: int) -> bool:
	var tiers_data: Array = talent_allocations.get(stat, [])
	return not tiers_data.is_empty() and tiers_data[tier][node]

## True if a stat tree node is allocated AND its tier is currently unlocked.
func is_node_active(stat_id: StringName, tier: int, node: int) -> bool:
	var tiers_data: Array = talent_allocations.get(stat_id, [])
	if tiers_data.is_empty() or not tiers_data[tier][node]:
		return false
	return is_tier_unlocked(tier)

## True if a kore node is allocated AND its tier is currently unlocked.
func is_kore_node_active(tier: int, node: int) -> bool:
	if kore_node_allocations.is_empty() or not kore_node_allocations[tier][node]:
		return false
	return is_kore_node_tier_unlocked(tier)

func reset_talents() -> void:
	talent_allocations.clear()
	kore_node_allocations.clear()
	_reset_tier_cache()
	talents_changed.emit()

# ── Leveling ──────────────────────────────────────────────────────────────────

## XP awarded for killing an enemy of `enemy_level`. Linear scaling.
func xp_award_for_enemy(enemy_level: int) -> int:
	return XP_PER_ENEMY_LEVEL * maxi(enemy_level, 1)

## Add XP and process any level-ups. Emits xp_changed once at the end and
## leveled_up per level crossed (so multi-level XP awards still feel correct).
func gain_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		_do_level_up()
	xp_changed.emit(xp, xp_to_next)

func _do_level_up() -> void:
	var old := level
	level += 1
	talent_points_total += TALENT_POINTS_PER_LEVEL
	xp_to_next = int(round(STARTING_XP_TO_NEXT * pow(XP_CURVE_GROWTH, float(level - 1))))
	var hp_gain := randi_range(HP_GAIN_PER_LEVEL_MIN, HP_GAIN_PER_LEVEL_MAX)
	level_changed.emit(level, old)
	leveled_up.emit(level, hp_gain)

# ── Tier crossing detection ───────────────────────────────────────────────────

func _reset_tier_cache() -> void:
	_cached_tiers.clear()
	_cached_origin_tier = -1
	_cached_kore_nodes_tier = -1

## Placeholder: tier is unlocked if player level / 3 >= tier (0-indexed).
func is_tier_unlocked(tier: int) -> bool:
	return tier <= level / 3

## Kore nodes are removed; always returns false for now.
func is_kore_node_tier_unlocked(_tier: int) -> bool:
	return false
