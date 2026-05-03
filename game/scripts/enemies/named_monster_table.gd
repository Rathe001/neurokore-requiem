extends Node

## Loads NamedMonster .tres files and rolls one for spawn-point named
## encounters. Mirrors MonsterAffixTable's pattern — directory scan at
## _ready, weighted random pick filtered by min_level.
##
## Adding a new named monster = drop a .tres at NAMED_DIR. No code edit.

const NAMED_DIR := "res://resources/enemies/named/"

var _named: Array[NamedMonster] = []
var _ready_called: bool = false

func _ready() -> void:
	_load_named()


func _load_named() -> void:
	if _ready_called:
		return
	_ready_called = true
	var dir := DirAccess.open(NAMED_DIR)
	if dir == null:
		# No directory or no entries is a valid state — named monsters are
		# optional content. EnemySpawner will get null from roll_random and
		# fall through to the regular spawn path.
		return
	for filename in dir.get_files():
		if not filename.ends_with(".tres"):
			continue
		var path := NAMED_DIR + filename
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
