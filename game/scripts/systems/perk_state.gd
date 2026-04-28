extends Node

# Tier perk registry + applier.
#
# Listens to PlayerState tier signals and recomputes the active perk set on
# any change. Aggregates effect magnitudes additively for runtime queries.
#
# Effect kinds (extend as new perks are designed):
#   damage_mult                   — % bonus damage (additive across perks)
#   max_health_pct                — % bonus to max HP
#   move_speed_pct                — % bonus move speed
#   cooldown_reduction_pct        — % cooldown reduction
#   crit_chance_pct               — % bonus crit chance
#   crit_damage_pct               — % bonus crit multiplier
#   multistrike_double_chance     — chance to strike twice (Forged)
#   multistrike_triple_chance     — chance to strike thrice (Forged)
#   low_hp_damage_pct             — % bonus damage when player HP < threshold
#   target_slowed_damage_pct      — % bonus damage vs slowed/staggered targets
#
# Perks for higher tiers stack additively on top of lower tiers — reaching
# tier 5 means tiers 1..5 are all active simultaneously.

signal perk_gained(perk: Dictionary)
signal perk_lost(perk: Dictionary)
signal perks_changed

# Per-stat tier perk ladders, indexed 0 = tier 1.
# Each perk: { id, label, description, effects: [{kind, magnitude}, ...] }
const STAT_PERKS: Dictionary = {
	&"dev": [
		{
			"id": &"dev_t1",
			"label": "Erratic Strikes",
			"description": "5% chance to strike twice.",
			"effects": [{"kind": &"multistrike_double_chance", "magnitude": 0.05}],
		},
		{
			"id": &"dev_t2",
			"label": "Frenzied Strikes",
			"description": "Additional 5% chance to strike twice.",
			"effects": [{"kind": &"multistrike_double_chance", "magnitude": 0.05}],
		},
		{
			"id": &"dev_t3",
			"label": "Manic Cadence",
			"description": "Additional 8% chance to strike twice.",
			"effects": [{"kind": &"multistrike_double_chance", "magnitude": 0.08}],
		},
		{
			"id": &"dev_t4",
			"label": "Shattered Tempo",
			"description": "Additional 4% chance to strike twice; 5% chance to strike thrice.",
			"effects": [
				{"kind": &"multistrike_double_chance", "magnitude": 0.04},
				{"kind": &"multistrike_triple_chance", "magnitude": 0.05},
			],
		},
		{
			"id": &"dev_t5",
			"label": "Unbound Frenzy",
			"description": "Additional 3% chance to strike twice; additional 7% chance to strike thrice.",
			"effects": [
				{"kind": &"multistrike_double_chance", "magnitude": 0.03},
				{"kind": &"multistrike_triple_chance", "magnitude": 0.07},
			],
		},
	],
	# Other stat ladders pending design — see attribute-system.md "Specialized
	# Class Tier Perks" table. Target T5 effective DPS ≈ 1.45×, expressed
	# through each class's flavor lever (crit, cooldowns, conditional damage).
	&"ort": [],
	&"opt": [],
	&"ing": [],
	&"cla": [],
	&"amb": [],
}

var _active_perks: Array[Dictionary] = []
var _aggregates: Dictionary = {}
var _initialized: bool = false

func _ready() -> void:
	PlayerState.tier_changed.connect(_on_tier_changed)
	PlayerState.class_changed.connect(_on_player_changed)
	PlayerState.spec_changed.connect(_on_player_changed)
	_recompute()

func _on_tier_changed(_stat: StringName, _old: int, _new: int) -> void:
	_recompute()

func _on_player_changed(_id: StringName) -> void:
	_recompute()

func _recompute() -> void:
	var old := _active_perks
	var new_active: Array[Dictionary] = []
	var new_aggregates: Dictionary = {}

	if PlayerState.class_id != &"" and PlayerState.spec_id != &"":
		for stat_id in AttributeState.ROLLABLE_STATS:
			var ladder: Array = STAT_PERKS.get(stat_id, [])
			if ladder.is_empty():
				continue
			var tier := AttributeState.get_unlocked_tier(stat_id, PlayerState.class_id, PlayerState.spec_id)
			for i in mini(tier, ladder.size()):
				var perk: Dictionary = ladder[i]
				new_active.append(perk)
				for effect: Dictionary in perk.get("effects", []):
					var k: StringName = effect.get("kind", &"")
					var m: float = float(effect.get("magnitude", 0.0))
					new_aggregates[k] = float(new_aggregates.get(k, 0.0)) + m

	_active_perks = new_active
	_aggregates = new_aggregates

	# Suppress signals on the very first compute so initial perks don't fire
	# tier-up banners at game start.
	if _initialized:
		for perk: Dictionary in new_active:
			if not _has_perk(old, perk.id):
				perk_gained.emit(perk)
		for perk: Dictionary in old:
			if not _has_perk(new_active, perk.id):
				perk_lost.emit(perk)
	_initialized = true
	perks_changed.emit()

func _has_perk(list: Array, id: StringName) -> bool:
	for p: Dictionary in list:
		if p.get("id", &"") == id:
			return true
	return false

func get_aggregate(kind: StringName) -> float:
	return _aggregates.get(kind, 0.0)

func get_active_perks() -> Array[Dictionary]:
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
