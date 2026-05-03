extends Node

# Tier perk registry + applier.
#
# Listens to PlayerState tier signals and recomputes the active perk set on
# any change. Aggregates effect magnitudes additively for runtime queries.
#
# Perk ladders are authored as .tres files at LADDER_DIR/{stat_id}.tres
# (one per AttributeState.ROLLABLE_STATS entry). Adding a new tier perk is a
# resource edit in the editor — no code changes here. Schema lives in
# scripts/perks/{perk_ladder, perk, perk_effect}.gd.
#
# Effect kinds — keep this list in sync with what consumers read via
# get_aggregate(kind). Adding a new effect kind requires a consumer that
# knows what to do with it; the aggregate dict accepts arbitrary keys.
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
#
# Perks for higher tiers stack additively on top of lower tiers — reaching
# tier 3 means tiers 1..3 are all active simultaneously.

signal perk_gained(perk: Perk)
signal perk_lost(perk: Perk)
signal perks_changed

const LADDER_DIR := "res://resources/perks/"

# stat_id (StringName) → PerkLadder. Built once on _ready by scanning
# LADDER_DIR for {stat_id}.tres. Stats with no ladder file load to null and
# the recompute loop skips them silently.
var _ladders: Dictionary = {}
var _active_perks: Array[Perk] = []
var _aggregates: Dictionary = {}
var _initialized: bool = false

func _ready() -> void:
	_load_ladders()
	PlayerState.tier_changed.connect(_on_tier_changed)
	PlayerState.class_changed.connect(_on_player_changed)
	PlayerState.spec_changed.connect(_on_player_changed)
	_recompute()


func _load_ladders() -> void:
	for stat_id: StringName in AttributeState.ROLLABLE_STATS:
		var path := "%s%s.tres" % [LADDER_DIR, stat_id]
		if not ResourceLoader.exists(path):
			continue
		var ladder := load(path) as PerkLadder
		if ladder == null:
			push_warning("[PerkState] Found %s but it isn't a PerkLadder; skipping." % path)
			continue
		_ladders[stat_id] = ladder


func _on_tier_changed(_stat: StringName, _old: int, _new: int) -> void:
	_recompute()

func _on_player_changed(_id: StringName) -> void:
	_recompute()

func _recompute() -> void:
	var old := _active_perks
	var new_active: Array[Perk] = []
	var new_aggregates: Dictionary = {}

	# Origin classes (Analog/Cyborg) also receive perks for tiers they unlock
	# in their team / opposing stats — capped at T2 / T1 by the threshold
	# tables. Earlier we required spec_id != "" too, which silently denied
	# origin classes any perks even after unlocking T2.
	if PlayerState.class_id != &"":
		for stat_id: StringName in AttributeState.ROLLABLE_STATS:
			var ladder: PerkLadder = _ladders.get(stat_id)
			if ladder == null or ladder.perks.is_empty():
				continue
			var tier := AttributeState.get_unlocked_tier(stat_id, PlayerState.class_id, PlayerState.spec_id)
			for i in mini(tier, ladder.perks.size()):
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
