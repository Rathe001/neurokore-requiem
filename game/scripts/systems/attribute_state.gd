extends Node

# Class metadata and tier definitions. Provides class/origin lookups used by
# UI (spec select, character creation, class cards) and gameplay systems
# (perk unlocks, scaling).
#
# The old 8-attribute moral stat system has been removed. Build identity now
# comes from talent tree progression (perk tiers I–V) and gear (direct
# bonuses + behavior mods). See docs/design/itemization.md.

# All specialized class definitions in one place — avoids sync bugs when
# adding classes. Add presentational fields here too (glyph for placeholder
# portraits, i18n keys for label + backstory) so spec_select / character
# panels read from a single source instead of carrying parallel dicts.
const CLASS_DEFINITIONS: Dictionary = {
	&"count":       {&"origin": &"analog", &"glyph": "G", &"label_key": &"STARTUP_PICK_ANALOG_COUNT", &"backstory_key": &"STARTUP_BACKSTORY_COUNT"},
	&"survivalist": {&"origin": &"analog", &"glyph": "S", &"label_key": &"STARTUP_PICK_ANALOG_SURVIVALIST", &"backstory_key": &"STARTUP_BACKSTORY_SURVIVALIST"},
	&"enculted":    {&"origin": &"analog", &"glyph": "E", &"label_key": &"STARTUP_PICK_ANALOG_ENCULTED",    &"backstory_key": &"STARTUP_BACKSTORY_ENCULTED"},
	&"forged":      {&"origin": &"cyborg", &"glyph": "F", &"label_key": &"STARTUP_PICK_CYBORG_FORGED",      &"backstory_key": &"STARTUP_BACKSTORY_FORGED"},
	&"automaton":   {&"origin": &"cyborg", &"glyph": "A", &"label_key": &"STARTUP_PICK_CYBORG_AUTOMATON",   &"backstory_key": &"STARTUP_BACKSTORY_AUTOMATON"},
	&"polymath":    {&"origin": &"cyborg", &"glyph": "P", &"label_key": &"STARTUP_PICK_CYBORG_POLYMATH",    &"backstory_key": &"STARTUP_BACKSTORY_POLYMATH"},
}

# The two origin classes — same shape as CLASS_DEFINITIONS. UI iterates
# this when offering origin selection (character creation, spec overlay).
const ORIGIN_DEFINITIONS: Dictionary = {
	&"analog": {&"glyph": "H", &"label_key": &"STARTUP_PICK_ANALOG", &"backstory_key": &"STARTUP_BACKSTORY_ANALOG"},
	&"cyborg": {&"glyph": "C", &"label_key": &"STARTUP_PICK_CYBORG", &"backstory_key": &"STARTUP_BACKSTORY_CYBORG"},
}

# Roman numeral tier labels — 5 perk tiers, unlocked via talent tree depth.
const TIER_ROMAN: Array[String] = ["I", "II", "III", "IV", "V"]
const TIER_COUNT := 5

# Class accent colors — used for UI theming and class-colored displays.
const CLASS_COLORS: Dictionary = {
	&"analog":      Color(0.65, 0.45, 0.25, 1.0),
	&"cyborg":      Color(0.3,  0.85, 1.0,  1.0),
	&"count":       Color(0.95, 0.92, 0.8,  1.0),
	&"survivalist": Color(0.7,  0.85, 0.35, 1.0),
	&"enculted":    Color(0.78, 0.35, 0.85, 1.0),
	&"forged":      Color(0.9,  0.25, 0.2,  1.0),
	&"automaton":   Color(0.55, 0.78, 0.85, 1.0),
	&"polymath":    Color(0.95, 0.9,  0.3,  1.0),
}

# Legacy perk/talent tree IDs use the old 3-letter stat abbreviations
# (ort, ing, amb, dev, opt, cla). These map to class names so UI code
# can resolve colors and display names from perk IDs without renaming
# every .tres resource.
const STAT_TO_CLASS: Dictionary = {
	&"ort": &"count",
	&"ing": &"survivalist",
	&"amb": &"enculted",
	&"dev": &"forged",
	&"opt": &"automaton",
	&"cla": &"polymath",
}

# Inverse of STAT_TO_CLASS — resolves a class/spec name back to its legacy
# 3-letter talent tree ID.
const CLASS_TO_STAT: Dictionary = {
	&"count": &"ort", &"survivalist": &"ing", &"enculted": &"amb",
	&"forged": &"dev", &"automaton": &"opt", &"polymath": &"cla",
}

## Returns the origin (&"analog" or &"cyborg") for a specialized class spec_id.
func get_spec_origin(spec_id: StringName) -> StringName:
	return CLASS_DEFINITIONS.get(spec_id, {}).get(&"origin", &"analog")

## Resolve a legacy stat abbreviation or class name to the class color.
static func color_for_id(id: StringName) -> Color:
	var class_id: StringName = STAT_TO_CLASS.get(id, id)
	return CLASS_COLORS.get(class_id, Color.WHITE)
