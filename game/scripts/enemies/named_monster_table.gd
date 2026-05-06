extends Node

## Loads NamedMonster .tres files and rolls one for spawn-point named
## encounters. Weighted random pick filtered by min_level.
##
## Adding a new named monster = drop a .tres at NAMED_DIR AND register its
## filename in NAMED_FILES. The explicit list is required because DirAccess
## directory enumeration is unreliable in exported Godot 4 builds — the
## .tres files exist but the listing comes back empty, leaving the named
## pool silently empty in the Steam build. ResourceLoader.exists() works
## in both editor and exports.

const NAMED_DIR := "res://resources/enemies/named/"
const NAMED_FILES: Array[String] = [
	"cinder_hollowlit.tres",
	"mother_wreath.tres",
	"vex_sundered.tres",
]

var _named: Array[NamedMonster] = []
var _ready_called: bool = false

func _ready() -> void:
	_load_named()


func _load_named() -> void:
	if _ready_called:
		return
	_ready_called = true
	for filename in NAMED_FILES:
		var path := NAMED_DIR + filename
		if not ResourceLoader.exists(path):
			# Missing file is a valid state — named monsters are optional
			# content. EnemySpawner falls through to the regular spawn path
			# when the pool is empty.
			continue
		var named := load(path) as NamedMonster
		if named == null:
			push_warning("[NamedMonsterTable] %s isn't a NamedMonster; skipping." % path)
			continue
		_named.append(named)


## Pick a named monster eligible for monster_level via weighted roll.
## Returns null if the eligible pool is empty — caller falls back to a
## regular spawn instead of leaving the slot blank.
func roll_random(monster_level: int, rng: RandomNumberGenerator) -> NamedMonster:
	_load_named()
	var pool: Array[NamedMonster] = []
	for n in _named:
		if n.min_level <= monster_level:
			pool.append(n)
	if pool.is_empty():
		return null
	var total := 0
	for n in pool:
		total += n.weight
	if total <= 0:
		return null
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for n in pool:
		acc += n.weight
		if roll < acc:
			return n
	return pool[-1]
