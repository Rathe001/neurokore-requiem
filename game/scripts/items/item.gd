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

# Ammo / reload — populated for bullet weapons (LMG/SMG/sniper/RPG).
# Weapons with ammo_max == 0 are energy weapons (laser pistol, plasma rifle,
# melee) that pay resource per shot; weapons with ammo_max > 0 burn ammo
# instead and trigger a reload when empty (or on R-key).
@export var ammo_max: int = 0
@export var ammo_current: int = 0
@export var reload_time: float = 0.0


## Bullet-weapon base ids — single source of truth for "does this archetype
## use ammo / reload". Used by is_bullet_weapon for legacy-save migration.
const BULLET_BASE_IDS: Array[StringName] = [
	&"lmg_2h", &"smg_1h", &"sniper_2h", &"rpg_2h",
]


## True for bullet weapons (LMG/SMG/sniper/RPG). UI and combat code use
## this to swap the resource-cost path for the ammo+reload path.
##
## Lazy-migrates pre-fix items: characters rolled before bullet ammo was
## added saved with ammo_max=0 even on bullet weapons. The first call here
## detects the legacy state via weapon_base_id and backfills from the
## WeaponBase .tres so the rest of the code treats them as proper bullet
## weapons without requiring a save/reload.
func is_bullet_weapon() -> bool:
	if ammo_max > 0:
		return true
	if weapon_base_id in BULLET_BASE_IDS:
		_backfill_ammo_from_base()
		return ammo_max > 0
	return false


func _backfill_ammo_from_base() -> void:
	var base_path := "res://resources/items/weapon_bases/%s.tres" % weapon_base_id
	if not ResourceLoader.exists(base_path):
		return
	var base := load(base_path) as WeaponBase
	if base == null or base.ammo_capacity_range.y <= 0:
		return
	# Midpoint of the rolled range — pre-fix saves have no RNG seed for
	# the missing field, so a deterministic mid-roll is the least
	# surprising default. Magazine starts full so the player isn't
	# punished with an immediate reload on the first shot post-migration.
	var lo: int = mini(base.ammo_capacity_range.x, base.ammo_capacity_range.y)
	var hi: int = maxi(base.ammo_capacity_range.x, base.ammo_capacity_range.y)
	ammo_max = maxi(1, (lo + hi) / 2)
	ammo_current = ammo_max
	reload_time = base.reload_time

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


# ── Network serialization ──────────────────────────────────────────
# Used by PickupsContainer to replicate item drops across MP peers.
# Colors become [r,g,b,a] arrays; Skill resources become resource_path
# strings. Everything else is a primitive that Godot can send natively.

func to_dict() -> Dictionary:
	var d: Dictionary = {}
	d[&"id"] = String(id)
	d[&"name_key"] = name_key
	d[&"description_key"] = description_key
	d[&"kind"] = String(kind)
	d[&"main_type"] = main_type
	d[&"sub_type"] = sub_type
	d[&"rarity"] = String(rarity)
	d[&"glyph"] = glyph
	d[&"glyph_color"] = [glyph_color.r, glyph_color.g, glyph_color.b, glyph_color.a]
	d[&"item_level"] = item_level
	d[&"two_handed"] = two_handed
	d[&"weapon_base_id"] = String(weapon_base_id)
	d[&"damage_min"] = damage_min
	d[&"damage_max"] = damage_max
	d[&"attack_speed"] = attack_speed
	d[&"crit_chance"] = crit_chance
	d[&"accuracy"] = accuracy
	d[&"weapon_range"] = weapon_range
	d[&"blast_radius"] = blast_radius
	d[&"ammo_max"] = ammo_max
	d[&"ammo_current"] = ammo_current
	d[&"reload_time"] = reload_time
	d[&"light_mod"] = int(light_mod)
	d[&"light_energy"] = light_energy
	d[&"light_range"] = light_range
	d[&"light_color"] = [light_color.r, light_color.g, light_color.b, light_color.a]
	d[&"fire_skill"] = fire_skill.resource_path if fire_skill != null else ""
	d[&"alt_fire_skill"] = alt_fire_skill.resource_path if alt_fire_skill != null else ""
	# stat_modifiers keys are StringName; convert to String for safe RPC transit.
	var mods: Dictionary = {}
	for k in stat_modifiers:
		mods[String(k)] = stat_modifiers[k]
	d[&"stat_modifiers"] = mods
	return d


static func from_dict(d: Dictionary) -> Item:
	var item := Item.new()
	item.id = StringName(d.get(&"id", ""))
	item.name_key = d.get(&"name_key", "")
	item.description_key = d.get(&"description_key", "")
	item.kind = StringName(d.get(&"kind", ""))
	item.main_type = d.get(&"main_type", "")
	item.sub_type = d.get(&"sub_type", "")
	item.rarity = StringName(d.get(&"rarity", "common"))
	item.glyph = d.get(&"glyph", "?")
	var gc: Array = d.get(&"glyph_color", [1, 1, 1, 1])
	item.glyph_color = Color(gc[0], gc[1], gc[2], gc[3])
	item.item_level = int(d.get(&"item_level", 1))
	item.two_handed = d.get(&"two_handed", false)
	item.weapon_base_id = StringName(d.get(&"weapon_base_id", ""))
	item.damage_min = int(d.get(&"damage_min", 0))
	item.damage_max = int(d.get(&"damage_max", 0))
	item.attack_speed = float(d.get(&"attack_speed", 1.0))
	item.crit_chance = float(d.get(&"crit_chance", 0.0))
	item.accuracy = float(d.get(&"accuracy", 1.0))
	item.weapon_range = float(d.get(&"weapon_range", 3.0))
	item.blast_radius = float(d.get(&"blast_radius", 0.0))
	item.ammo_max = int(d.get(&"ammo_max", 0))
	item.ammo_current = int(d.get(&"ammo_current", 0))
	item.reload_time = float(d.get(&"reload_time", 0.0))
	item.light_mod = int(d.get(&"light_mod", 0)) as LightMod
	item.light_energy = float(d.get(&"light_energy", 1.2))
	item.light_range = float(d.get(&"light_range", 12.0))
	var lc: Array = d.get(&"light_color", [1, 1, 1, 1])
	item.light_color = Color(lc[0], lc[1], lc[2], lc[3])
	var skill_path: String = d.get(&"fire_skill", "")
	if skill_path != "":
		item.fire_skill = load(skill_path) as Skill
	var alt_path: String = d.get(&"alt_fire_skill", "")
	if alt_path != "":
		item.alt_fire_skill = load(alt_path) as Skill
	var mods: Dictionary = d.get(&"stat_modifiers", {})
	item.stat_modifiers = {}
	for k in mods:
		item.stat_modifiers[StringName(k)] = mods[k]
	return item
