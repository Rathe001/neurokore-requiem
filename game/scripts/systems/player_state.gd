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
## How often a talent point is granted. 1 point every N level-ups; the
## level-up only awards a point when the new level is divisible by this.
## Level 100 → ~33 points at the current cadence.
const LEVELS_PER_TALENT_POINT := 3

var class_id: StringName = &""
var spec_id: StringName = &""
var gender: StringName = &"male"
## Selected avatar index (1..5). 0 means none chosen — HUD falls back to
## a text-only level display.
var avatar_id: int = 0
## Player-entered display name. Empty = no name shown in HUD.
var player_name: String = ""
## Hardcore mode — death is permanent. Set during character creation.
var hardcore: bool = false
## Stable UUID for this character — generated once at creation, never changes.
## Used as the persistent identity in multiplayer and cloud sync.
var character_id: String = ""
## File identifier for the active save slot. Empty = unsaved new character.
var active_save_id: String = ""
## Bus fields written by SaveManager on load, read by PrototypePlayer on _ready().
## Same transfer pattern as class_id/spec_id.
var saved_credits: int = 0
var saved_resource_current: float = 0.0
## Accumulated HP gained from level-ups. Restored on load so max_health
## reflects all past level-up rolls, not just the base @export value.
var saved_level_hp_bonus: int = 0
## Current health at the time of save. -1 means "use max_health" (fresh character).
var saved_health: int = -1


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

## Zone level offset derived from NG+ count. Each NG+ shifts enemy levels
## up by 2 so zones feel progressively harder across resets.
## NG+0 → +0 (enemies start L1-3), NG+1 → +2 (L3-5), NG+2 → +4 (L5-7), etc.
func zone_level_offset() -> int:
	return new_game_plus * 2

## Spent talent points per stat tree.
## Layout: { stat_id: [[bool]*8]*5 } — 5 tiers × 8 nodes each.
var talent_allocations: Dictionary = {}

var _cached_tiers: Dictionary = {}
var _cached_origin_tier: int = -1

func _ready() -> void:
	pass

## Reset all character state to fresh defaults. Called before creating a new
## character so no data from a previous session leaks through.
func reset() -> void:
	class_id = &""
	spec_id = &""
	gender = &"male"
	avatar_id = 0
	player_name = ""
	hardcore = false
	character_id = ""
	active_save_id = ""
	level = 1
	xp = 0
	xp_to_next = STARTING_XP_TO_NEXT
	talent_points_total = 0
	new_game_plus = 0
	saved_credits = 0
	saved_resource_current = 0.0
	saved_level_hp_bonus = 0
	saved_health = -1
	talent_allocations.clear()
	_reset_tier_cache()

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
	reset_talents()
	spec_changed.emit(spec_id)

func set_class_and_spec(new_class: StringName, new_spec: StringName) -> void:
	var class_diff := class_id != new_class
	var spec_diff := spec_id != new_spec
	class_id = new_class
	spec_id = new_spec
	if class_diff or spec_diff:
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
	return total

## True if a stat tree node has a point allocated (regardless of tier unlock state).
func is_talent_allocated(stat: StringName, tier: int, node: int) -> bool:
	var tiers_data: Array = talent_allocations.get(stat, [])
	return not tiers_data.is_empty() and tiers_data[tier][node]

## True if a stat tree node is allocated AND its tier is currently unlocked
## under the per-tree gating rules (own spec, same-origin, opposing-origin).
func is_node_active(stat_id: StringName, tier: int, node: int) -> bool:
	var tiers_data: Array = talent_allocations.get(stat_id, [])
	if tiers_data.is_empty() or not tiers_data[tier][node]:
		return false
	return tier < get_unlocked_tier(stat_id)

func reset_talents() -> void:
	talent_allocations.clear()
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
	if level % LEVELS_PER_TALENT_POINT == 0:
		talent_points_total += 1
	xp_to_next = int(round(STARTING_XP_TO_NEXT * pow(XP_CURVE_GROWTH, float(level - 1))))
	var hp_gain := randi_range(HP_GAIN_PER_LEVEL_MIN, HP_GAIN_PER_LEVEL_MAX)
	level_changed.emit(level, old)
	leveled_up.emit(level, hp_gain)

# ── Tier crossing detection ───────────────────────────────────────────────────

func _reset_tier_cache() -> void:
	_cached_tiers.clear()
	_cached_origin_tier = -1

const TALENT_TIER_COUNT := 5
## Origin class players can access same-origin trees up to this tier (exclusive).
const ORIGIN_CLASS_TIER_CAP := 3

## Cumulative point thresholds to unlock each tier within a track.
## Tier I (index 0) is always open (0 points). Each subsequent tier
## requires 4 more total points spent anywhere in the same track.
const TIER_POINT_THRESHOLDS: Array[int] = [0, 4, 8, 12, 16]

## Count total talent points allocated in a single track.
func _points_in_track(stat_id: StringName) -> int:
	var tiers_data: Array = talent_allocations.get(stat_id, [])
	var total := 0
	for tier_row in tiers_data:
		for allocated in tier_row:
			if allocated:
				total += 1
	return total

## Returns the number of unlocked tiers (exclusive upper bound) for a talent
## tree identified by its legacy stat_id (&"dev", &"ort", etc.).
## 0 = fully locked, 5 = all tiers open.
## Tier progression is gated by cumulative points spent in the track, not
## player level. Origin/spec access rules still apply on top.
func get_unlocked_tier(stat_id: StringName) -> int:
	var tree_class: StringName = AttributeState.STAT_TO_CLASS.get(stat_id, &"")
	if tree_class == &"":
		return 0
	var tree_origin: StringName = AttributeState.get_spec_origin(tree_class)
	var player_origin: StringName = class_id

	# Opposing origin → fully locked (only accessible via item grants later)
	if tree_origin != player_origin:
		return 0

	# Point-based tier cap: count points in this track and find the highest
	# tier whose threshold is met.
	var points := _points_in_track(stat_id)
	var point_cap := 1  # tier I is always open
	for i in range(1, TIER_POINT_THRESHOLDS.size()):
		if points >= TIER_POINT_THRESHOLDS[i]:
			point_cap = i + 1
	var tier_cap: int = mini(point_cap, TALENT_TIER_COUNT)

	# Origin class (no spec) → same-origin trees capped at tier 3
	if spec_id == &"":
		return mini(tier_cap, ORIGIN_CLASS_TIER_CAP)

	# Own spec tree → full point-gated access
	var own_stat: StringName = AttributeState.CLASS_TO_STAT.get(spec_id, &"")
	if stat_id == own_stat:
		return tier_cap

	# Same-origin, different spec → requires tier 1+ investment in own spec
	if _has_own_spec_investment():
		return tier_cap
	return 0

## True if the player has allocated at least one node at tier 1+ in their
## own spec tree. This gates access to same-origin off-spec trees.
func _has_own_spec_investment() -> bool:
	var own_stat: StringName = AttributeState.CLASS_TO_STAT.get(spec_id, &"")
	if own_stat == &"":
		return false
	var tiers_data: Array = talent_allocations.get(own_stat, [])
	if tiers_data.is_empty():
		return false
	for tier_idx in range(1, tiers_data.size()):
		for allocated in tiers_data[tier_idx]:
			if allocated:
				return true
	return false
