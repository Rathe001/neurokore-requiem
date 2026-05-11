extends Node

## Registry of EnemyClass .tres files for the default spawn pool.
## Follows the same explicit-list pattern as MonsterAffixTable and
## NamedMonsterTable — DirAccess enumeration is unreliable in exported
## Godot 4 builds.
##
## Adding a new enemy weapon class:
##   1. Drop the .tres in CLASS_DIR
##   2. Add its filename to CLASS_FILES
## That's it — EnemySpawner picks it up automatically.

const CLASS_DIR := "res://resources/enemies/classes/"
const CLASS_FILES: Array[String] = [
	# Melee
	"melee_blade.tres",
	"melee_sledgehammer.tres",
	# Ranged — kinetic (bullet visuals)
	"ranged_smg.tres",
	"ranged_lmg.tres",
	"ranged_shotgun.tres",
	"ranged_sniper.tres",
	"ranged_rpg.tres",
	# Ranged — energy (bolt visuals)
	"ranged_laser_pistol.tres",
	"ranged_plasma_rifle.tres",
	"ranged_accelerator.tres",
	"ranged_taser.tres",
	# Support
	"melee_healer.tres",
	"ranged_healer.tres",
	"ranged_buffer.tres",
]

var _classes: Array[EnemyClass] = []
var _ready_called: bool = false


func _ready() -> void:
	_load_classes()


func _load_classes() -> void:
	if _ready_called:
		return
	_ready_called = true
	for filename in CLASS_FILES:
		var path := CLASS_DIR + filename
		if not ResourceLoader.exists(path):
			push_warning("[EnemyClassTable] Missing class file: %s" % path)
			continue
		var c := load(path) as EnemyClass
		if c == null:
			push_warning("[EnemyClassTable] %s isn't an EnemyClass; skipping." % path)
			continue
		_classes.append(c)
	if _classes.is_empty():
		push_warning("[EnemyClassTable] Pool is empty after load — enemies will use scene defaults.")


## Returns all registered classes. EnemySpawner uses this as the default
## pool when a room doesn't specify its own enemy_classes override.
func get_all() -> Array[EnemyClass]:
	return _classes
