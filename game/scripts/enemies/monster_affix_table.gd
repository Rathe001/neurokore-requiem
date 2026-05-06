extends Node

## Loads MonsterAffix .tres files and provides weighted rolling for pack
## generation. Mirrors AffixTable's pattern but for monster modifiers
## instead of item affixes.
##
## Adding a new affix = drop a .tres at AFFIX_DIR AND register its filename
## in AFFIX_FILES. The explicit list is required because DirAccess directory
## enumeration is unreliable in exported Godot 4 builds — the .tres files
## exist but the listing comes back empty, leaving the affix pool silently
## empty in the Steam build. ResourceLoader.exists() works in both editor
## and exports.

const AFFIX_DIR := "res://resources/enemies/affixes/"
const AFFIX_FILES: Array[String] = [
	"burning.tres",
	"frenzied.tres",
	"jagged.tres",
	"quickfoot.tres",
	"tough.tres",
	"vampiric.tres",
]

var _affixes: Array[MonsterAffix] = []
var _ready_called: bool = false

func _ready() -> void:
	_load_affixes()


func _load_affixes() -> void:
	if _ready_called:
		return
	_ready_called = true
	for filename in AFFIX_FILES:
		var path := AFFIX_DIR + filename
		if not ResourceLoader.exists(path):
			push_warning("[MonsterAffixTable] Missing affix file: %s" % path)
			continue
		var affix := load(path) as MonsterAffix
		if affix == null:
			push_warning("[MonsterAffixTable] %s isn't a MonsterAffix; skipping." % path)
			continue
		_affixes.append(affix)


## Pick `count` distinct affixes via weighted roll, filtered by min_level.
## Distinct = no affix appears twice in the returned list (no `Tough Tough`
## packs). Returns fewer than `count` if the eligible pool is too small.
func roll_affixes(count: int, monster_level: int, rng: RandomNumberGenerator) -> Array[MonsterAffix]:
	_load_affixes()
	var pool: Array[MonsterAffix] = []
	for a in _affixes:
		if a.min_level <= monster_level:
			pool.append(a)
	var picks: Array[MonsterAffix] = []
	for _i in count:
		if pool.is_empty():
			break
		var winner := _weighted_pick(pool, rng)
		if winner == null:
			break
		picks.append(winner)
		pool.erase(winner)  # distinct: drop from the pool for the next pick
	return picks


func _weighted_pick(pool: Array[MonsterAffix], rng: RandomNumberGenerator) -> MonsterAffix:
	var total := 0
	for a in pool:
		total += a.weight
	if total <= 0:
		return null
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for a in pool:
		acc += a.weight
		if roll < acc:
			return a
	return pool[-1]
