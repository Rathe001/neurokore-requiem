class_name Item extends Resource

## Head armor light mod — determines the flashlight type when this item
## is equipped in the head slot. NONE means no light source.
enum LightMod { NONE, FLASHLIGHT, RADIANT, SCANNER, UV }

@export var id: StringName
@export var name_key: String = ""
@export var description_key: String = ""
@export var kind: StringName = &""
@export var main_type: String = ""
@export var sub_type: String = ""
@export var rarity: StringName = &"common"
@export var glyph: String = "?"
@export var glyph_color: Color = Color(1, 1, 1, 1)
## Item level (rolled at generation time). Drives the effectiveness curve:
## items below the player's level decay smoothly, items above the player's
## level scale upward. 0 marks starter gear (intentionally below every drop).
@export var item_level: int = 1

@export_group("Combat")
@export var two_handed: bool = false
@export var fire_skill: Skill
@export var alt_fire_skill: Skill
## Weapon stats rolled once at item generation from the WeaponBase ranges.
## Defaults are no-ops so non-weapon items don't accidentally affect combat.
@export var weapon_base_id: StringName = &""
@export var damage_min: int = 0
@export var damage_max: int = 0
@export var attack_speed: float = 1.0
@export var crit_chance: float = 0.0
@export var accuracy: float = 1.0
@export var weapon_range: float = 3.0
@export var blast_radius: float = 0.0

@export_group("Mods")
## Behavior mod for head armor — determines the player's light source.
@export var light_mod: LightMod = LightMod.NONE
@export var light_energy: float = 1.2
@export var light_range: float = 12.0
@export var light_color: Color = Color.WHITE

@export_group("Stats")
## Flat stat / modifier bonuses applied when this item is equipped.
## Keys are StringName — direct combat bonuses (&"damage_reduction",
## &"max_health_bonus", &"max_resource_bonus", &"move_speed_bonus",
## &"hit_chance_bonus", &"attack_speed_bonus", &"crit_chance_bonus",
## &"cooldown_reduction", &"inventory_bonus", &"range_bonus") live in this
## single dict. Affix table entries MUST use StringName keys (the &"" prefix);
## plain string keys hash differently and silently fail to match reads.
@export var stat_modifiers: Dictionary = {}


## Effectiveness curve shape (see docs/design/itemization.md). Items below
## the player's level decay asymptotically toward EFFECTIVE_FLOOR; items
## above scale linearly toward EFFECTIVE_CEILING.
const EFFECTIVE_DECAY_RATE: float = 0.05
const EFFECTIVE_FLOOR: float = 0.30
const EFFECTIVE_BOOST_RATE: float = 0.01
const EFFECTIVE_CEILING: float = 1.50


## Multiplier applied to this item's combat stats given the player's level.
## Drops below player level decay (1 / (1 + delta * rate)), drops above
## scale upward (linear), each clamped to a floor/ceiling so the system
## never produces zero-power or runaway items. player_level < 0 reads from
## PlayerState — pass an explicit level only when computing for a hypothetical
## (e.g. comparison UI).
func effective_multiplier(player_level: int = -1) -> float:
	var pl: int = player_level if player_level >= 0 else PlayerState.level
	var delta: int = pl - item_level
	if delta <= 0:
		return minf(EFFECTIVE_CEILING, 1.0 + float(-delta) * EFFECTIVE_BOOST_RATE)
	return maxf(EFFECTIVE_FLOOR, 1.0 / (1.0 + float(delta) * EFFECTIVE_DECAY_RATE))


## Read a modifier with a fallback. Single accessor for typed reads from
## stat_modifiers — saves the every-caller `int(item.stat_modifiers.get(...))`
## boilerplate and centralises the dict-key contract. Returns the RAW rolled
## value; use get_effective_modifier when the consumer cares about player-
## level scaling (combat stats, gear bonuses).
func get_modifier(key: StringName, fallback: int = 0) -> int:
	return int(stat_modifiers.get(key, fallback))


## Like get_modifier, but multiplied by effective_multiplier(). Use this
## anywhere the value contributes to character power — HP/resource bonuses,
## damage/crit/accuracy bonuses, resistances, knockback, shield pool, etc.
## Storage stats (inventory_bonus) and feel stats (light_range, light_energy)
## should keep using get_modifier so a low-ilvl backpack doesn't shrink under
## a high-level player.
func get_effective_modifier(key: StringName, fallback: int = 0) -> int:
	var raw: int = int(stat_modifiers.get(key, fallback))
	if raw == 0:
		return 0
	return int(round(float(raw) * effective_multiplier()))


## Float version of get_effective_modifier — returns the unrounded value so
## tooltip code can display fractional percentages (10.2% vs 10.1%) and let
## the player see marginal upgrades. Gameplay paths use the int version for
## consistency with the existing stat_modifier contract.
func get_effective_modifier_float(key: StringName, fallback: int = 0) -> float:
	var raw: int = int(stat_modifiers.get(key, fallback))
	if raw == 0:
		return 0.0
	return float(raw) * effective_multiplier()


# Direct-field effective accessors. Weapon stats are rolled once at
# generation; the live value the combat code uses is raw × multiplier.
# Range and blast_radius intentionally don't have effective accessors —
# those are about weapon character ("this is a long-range rifle") rather
# than power, and shouldn't shrink as the player outlevels the weapon.

func effective_damage_min() -> int:
	return int(round(float(damage_min) * effective_multiplier()))

func effective_damage_max() -> int:
	return int(round(float(damage_max) * effective_multiplier()))

func effective_attack_speed() -> float:
	return attack_speed * effective_multiplier()

func effective_crit_chance() -> float:
	return clampf(crit_chance * effective_multiplier(), 0.0, 1.0)

func effective_accuracy() -> float:
	return clampf(accuracy * effective_multiplier(), 0.0, 1.0)
