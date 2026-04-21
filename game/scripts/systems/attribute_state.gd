extends Node

# Moral attribute stats. See docs/design/attribute-system.md.
# Rollable stats (ort/ing/amb/dev/opt/cla) are set by equipment + class scaling.
# Soul and Interface are derived: average of their origin's three team stats.
# Stat identity (tier perks, visual metamorphosis) is computed from breakpoints — not yet implemented.

signal stats_changed

# Accent colors per stat — match class theme resources (attribute-system.md § Attribute Colors)
const STAT_COLORS: Dictionary = {
	&"soul": Color(0.65, 0.45, 0.25, 1.0),
	&"itf":  Color(0.3,  0.85, 1.0,  1.0),
	&"ort":  Color(0.95, 0.92, 0.8,  1.0),
	&"dev":  Color(0.9,  0.25, 0.2,  1.0),
	&"opt":  Color(0.55, 0.78, 0.85, 1.0),
	&"ing":  Color(0.7,  0.85, 0.35, 1.0),
	&"cla":  Color(0.95, 0.9,  0.3,  1.0),
	&"amb":  Color(0.78, 0.35, 0.85, 1.0),
}

# i18n keys for display labels
const STAT_I18N: Dictionary = {
	&"soul": &"STAT_SOUL",
	&"itf":  &"STAT_INTERFACE",
	&"ort":  &"STAT_ORTHODOXY",
	&"dev":  &"STAT_DEVIATION",
	&"opt":  &"STAT_OPTIMIZATION",
	&"ing":  &"STAT_INGENUITY",
	&"cla":  &"STAT_CLARITY",
	&"amb":  &"STAT_AMBITION",
}

# Stat shorthands for compact display
const STAT_SHORT: Dictionary = {
	&"soul": "SOU",
	&"itf":  "ITF",
	&"ort":  "ORT",
	&"dev":  "DEV",
	&"opt":  "OPT",
	&"ing":  "ING",
	&"cla":  "CLA",
	&"amb":  "AMB",
}

# Display order for UI — Human origin (left col), Cyborg origin (right col)
const HUMAN_STATS: Array[StringName] = [&"soul", &"ort", &"ing", &"amb"]
const CYBORG_STATS: Array[StringName] = [&"itf", &"dev", &"opt", &"cla"]

# Rollable stats — set via set_stat()
var ort: int = 0
var ing: int = 0
var amb: int = 0
var dev: int = 0
var opt: int = 0
var cla: int = 0

# Derived stats — computed from team stats
var soul: int:
	get:
		return _avg3(ort, ing, amb)

var itf: int:
	get:
		return _avg3(dev, opt, cla)

func get_stat(id: StringName) -> int:
	match id:
		&"soul": return soul
		&"itf":  return itf
		&"ort":  return ort
		&"ing":  return ing
		&"amb":  return amb
		&"dev":  return dev
		&"opt":  return opt
		&"cla":  return cla
	return 0

func set_stat(id: StringName, value: int) -> void:
	match id:
		&"ort": ort = value
		&"ing": ing = value
		&"amb": amb = value
		&"dev": dev = value
		&"opt": opt = value
		&"cla": cla = value
		_: return
	stats_changed.emit()

func _avg3(a: int, b: int, c: int) -> int:
	return int(round((a + b + c) / 3.0))
