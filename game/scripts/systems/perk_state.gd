extends Node

# Tier perk registry + applier.
#
# Listens to PlayerState signals and recomputes the active perk set on
# any change. Aggregates effect magnitudes additively for runtime queries.
#
# Perk ladders are authored as .tres files in LADDER_DIR (one per ladder).
# Adding a new tier perk is a resource edit in the editor — no code changes
# here. Schema lives in scripts/perks/{perk_ladder, perk, perk_effect}.gd.
#
# Effect kinds — keep this list in sync with what consumers read via
# get_aggregate(kind). Adding a new effect kind requires a consumer that
# knows what to do with it; the aggregate dict accepts arbitrary keys.
#
# Most consumers should call Effects.get_aggregate(kind) instead of
# PerkState.get_aggregate(kind) — Effects sums perks AND talents so a
# talent that buffs an existing kind (e.g. crit_chance_pct) lands on
# top of the perk's value naturally. Read PerkState directly only when
# you specifically want to know the perk-only contribution (rare).
#   damage_mult                   — % bonus damage (additive across perks)
#   max_health_pct                — % bonus to max HP
#   move_speed_pct                — % bonus move speed
#   cooldown_reduction_pct        — % cooldown reduction
#   crit_chance_pct               — % bonus crit chance
#   crit_damage_pct               — % bonus crit multiplier
#   multistrike_double_chance     — chance to strike twice
#   multistrike_triple_chance     — chance to strike thrice
#   low_hp_damage_pct             — % bonus damage when player HP < threshold
#   target_slowed_damage_pct      — % bonus damage vs slowed/staggered targets
#   extra_weapon_slots            — +N one-handed weapon slots (Forged Amalgamation).
#                                   Read by InventoryState.get_extra_weapon_slot_count
#                                   to gate weapon_2/_3/_4 slots, by CharacterPanel
#                                   to render those slots, and by PrototypePlayer's
#                                   LMB combat path to know how many weapons fire.
#   telekinesis_bolts             — +N psionic bolts per trigger (Polymath
#                                   Telekinesis). Read by PrototypePlayer's
#                                   _process_telekinesis on a fixed cadence;
#                                   each bolt grabs a random nearby enemy and
#                                   slams them into another for AoE damage,
#                                   or grabs scrap (single-target +50%) if no
#                                   second enemy is in range.
#   exile_curse_damage_pct        — +X% damage taken while cursed (Count Exile).
#                                   PlayerCombat applies the curse via
#                                   enemy.apply_curse() after every damage
#                                   path; PrototypeEnemy.take_damage scales
#                                   incoming damage by (1 + pct/100); on
#                                   curse expire the enemy calls back to
#                                   PlayerCombat.fire_exile_shot() for the
#                                   massive auto-shot.
#   automaton_drones              — +N orbiting drones (Automaton Drone Swarm).
#                                   PrototypePlayer reconciles the drone
#                                   pool to match the aggregate on every
#                                   perks_changed (and on death/respawn).
#                                   Each drone runs its own orbit + target +
#                                   fire loop; future Mainboard chips will
#                                   modify their behaviour.
#   doomsayer_max_charms          — Cap on simultaneously-charmed enemies
#                                   (Enculted Doomsayer charm slot). Charm
#                                   persists until the player dies or the
#                                   charmed enemy is killed by another
#                                   enemy. No FIFO eviction; the cap acts
#                                   as a natural rate-limit on the per-tick
#                                   charm aura. PrototypePlayer owns the
#                                   list; release_charm on the enemy side
#                                   just clears state. Damage-over-time
#                                   for the same aura is talent-driven —
#                                   see &"doomsayer_dot_per_tick" in
#                                   talent_state.gd.
#   ied_max_traps                 — +N max active IED traps (Survivalist
#                                   Improvised Explosive Device). PrototypePlayer
#                                   tosses a trap at the cursor on every LMB
#                                   attack; when at cap, the oldest trap is
#                                   despawned to make room. Traps last 15s
#                                   or detonate when an enemy enters
#                                   their proximity radius.
#
# Perks for higher tiers stack additively on top of lower tiers — reaching
# tier 3 means tiers 1..3 are all active simultaneously.

signal perk_gained(perk: Perk)
signal perk_lost(perk: Perk)
signal perks_changed

const LADDER_DIR := "res://resources/perks/"

# ladder_id (StringName) → PerkLadder. Built once on _ready by scanning
# all .tres files in LADDER_DIR. Ladders with no matching file are absent;
# the recompute loop skips them silently.
var _ladders: Dictionary = {}
var _active_perks: Array[Perk] = []
var _aggregates: Dictionary = {}
var _initialized: bool = false

func _ready() -> void:
	_load_ladders()
	PlayerState.class_changed.connect(_on_player_changed)
	PlayerState.spec_changed.connect(_on_player_changed)
	PlayerState.level_changed.connect(_on_level_changed)
	# Talent allocation now drives perk tier unlocks, not level. Re-running on
	# talents_changed is what makes "spend a talent point" actually grant a
	# new perk tier.
	PlayerState.talents_changed.connect(_recompute)
	_recompute()


func _load_ladders() -> void:
	# Resolve files by stat_id (amb.tres, ort.tres, etc.) — same convention
	# TalentState uses. We avoid DirAccess.list_dir_begin here because it
	# isn't reliable in exported Godot 4 builds: the .tres files exist as
	# resources but the directory listing returns empty, so _ladders ended
	# up empty in the Steam playtest build and no perks ever unlocked.
	# Walk CLASS_DEFINITIONS to enumerate the six class slots and resolve
	# each to its stat_id; ResourceLoader.exists works in both editor and
	# exported builds.
	var seen: Dictionary = {}
	for class_id: StringName in AttributeState.CLASS_DEFINITIONS.keys():
		var stat_id: StringName = AttributeState.CLASS_TO_STAT.get(class_id, &"")
		if stat_id == &"" or seen.has(stat_id):
			continue
		seen[stat_id] = true
		var path := "%s%s.tres" % [LADDER_DIR, stat_id]
		if not ResourceLoader.exists(path):
			continue
		var ladder := load(path) as PerkLadder
		if ladder == null:
			push_warning("[PerkState] Found %s but it isn't a PerkLadder; skipping." % path)
			continue
		_ladders[stat_id] = ladder
	if _ladders.is_empty():
		push_warning("[PerkState] No perk ladders loaded — talent allocations won't grant any perks.")


func _on_level_changed(_new_level: int, _old_level: int) -> void:
	_recompute()

func _on_player_changed(_id: StringName) -> void:
	_recompute()

func _recompute() -> void:
	var old := _active_perks
	var new_active: Array[Perk] = []
	var new_aggregates: Dictionary = {}

	# Each ladder's perk progression is driven by the player's talent
	# allocations in the matching tree. A perk at tier N unlocks once the
	# player has allocated any talent node at allocation-tier N (0-indexed,
	# so tier 0 → perk[0] = T1). Class lockouts already gate which tiers
	# the player could have spent on (via PlayerState.is_node_active /
	# get_unlocked_tier), so iterating allocations here implicitly respects
	# the lockout shape.
	if PlayerState.class_id != &"":
		for ladder_id: StringName in _ladders.keys():
			var ladder: PerkLadder = _ladders[ladder_id]
			if ladder == null or ladder.perks.is_empty():
				continue
			var alloc: Array = PlayerState.talent_allocations.get(ladder_id, [])
			var max_alloc_tier := -1
			for tier_idx in alloc.size():
				var row: Array = alloc[tier_idx]
				for node_alloc in row:
					if node_alloc:
						max_alloc_tier = maxi(max_alloc_tier, tier_idx)
						break
			var unlocked_perks := mini(max_alloc_tier + 1, ladder.perks.size())
			for i in unlocked_perks:
				var perk: Perk = ladder.perks[i]
				if perk == null:
					continue
				new_active.append(perk)
				for effect in perk.effects:
					if effect == null:
						continue
					new_aggregates[effect.kind] = float(new_aggregates.get(effect.kind, 0.0)) + effect.magnitude

	_active_perks = new_active
	_aggregates = new_aggregates

	# Suppress signals on the very first compute so initial perks don't fire
	# tier-up banners at game start.
	if _initialized:
		for perk in new_active:
			if not _has_perk(old, perk.id):
				perk_gained.emit(perk)
		for perk in old:
			if not _has_perk(new_active, perk.id):
				perk_lost.emit(perk)
	_initialized = true
	perks_changed.emit()

func _has_perk(list: Array[Perk], id: StringName) -> bool:
	for p in list:
		if p != null and p.id == id:
			return true
	return false

func get_aggregate(kind: StringName) -> float:
	return _aggregates.get(kind, 0.0)

func get_active_perks() -> Array[Perk]:
	return _active_perks

# Rolls a multistrike for an attack. Returns total hit count: 1, 2, or 3.
# Triple beats double; rolls are mutually exclusive (one outcome per attack).
func roll_multistrike() -> int:
	var p_triple: float = _aggregates.get(&"multistrike_triple_chance", 0.0)
	var p_double: float = _aggregates.get(&"multistrike_double_chance", 0.0)
	var roll := randf()
	if roll < p_triple:
		return 3
	if roll < p_triple + p_double:
		return 2
	return 1


# Expected hit count for tooltip DPS math. Returns the average number of
# hits per cast given the current multistrike aggregates — 1.0 with no
# sources, scaling toward 3.0 as triple-strike chance approaches 1.0.
# Mirrors roll_multistrike's outcome distribution exactly:
#   E[hits] = 3*p_triple + 2*p_double*(1-p_triple) + 1*(rest)
#          = 1 + 2*p_triple + p_double*(1-p_triple)
func expected_multistrike() -> float:
	var p_triple: float = _aggregates.get(&"multistrike_triple_chance", 0.0)
	var p_double: float = _aggregates.get(&"multistrike_double_chance", 0.0)
	return 1.0 + 2.0 * p_triple + p_double * (1.0 - p_triple)
