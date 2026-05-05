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
	_recompute()


func _load_ladders() -> void:
	var dir := DirAccess.open(LADDER_DIR)
	if dir == null:
		push_warning("[PerkState] Cannot open LADDER_DIR: %s" % LADDER_DIR)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path := LADDER_DIR + file_name
			var ladder := load(path) as PerkLadder
			if ladder == null:
				push_warning("[PerkState] Found %s but it isn't a PerkLadder; skipping." % path)
			else:
				var ladder_id := StringName(file_name.get_basename())
				_ladders[ladder_id] = ladder
		file_name = dir.get_next()
	dir.list_dir_end()


func _on_level_changed(_new_level: int, _old_level: int) -> void:
	_recompute()

func _on_player_changed(_id: StringName) -> void:
	_recompute()

func _recompute() -> void:
	var old := _active_perks
	var new_active: Array[Perk] = []
	var new_aggregates: Dictionary = {}

	# Placeholder: unlock perks based on player level until the talent-tree-driven
	# perk system is built. For the player's spec ladder, unlock up to
	# tier = level / 3. For non-spec ladders, unlock tier 0 only.
	if PlayerState.class_id != &"":
		var max_tier := PlayerState.level / 3
		for ladder_id: StringName in _ladders.keys():
			var ladder: PerkLadder = _ladders[ladder_id]
			if ladder == null or ladder.perks.is_empty():
				continue
			var tier: int = 0
			if PlayerState.spec_id != &"" and ladder_id == PlayerState.spec_id:
				tier = mini(max_tier, ladder.perks.size())
			for i in tier:
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
