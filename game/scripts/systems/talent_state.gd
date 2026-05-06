extends Node

# Talent registry + applier. Mirrors PerkState's shape: loads per-class
# trees from TREE_DIR on boot, recomputes the active node set + aggregate
# magnitudes (and granted active-skill bindings) whenever the player's
# allocations or level change.
#
# A node is "active" when:
#   * it exists in the loaded tree at (class_id, tier, node_idx),
#   * the player has a point allocated to that slot (PlayerState), AND
#   * the slot's tier is currently unlocked (PlayerState.is_node_active).
#
# What an active node can do (any combination):
#   1. Contribute magnitudes to one or more effect aggregates via its
#      `effects: Array[PerkEffect]`. Reuses the perk effect schema so
#      a talent can target the SAME aggregate kind a perk does — and
#      Effects.get_aggregate (the unified reader) sums both.
#   2. Grant an active hotbar skill via `granted_skill` + `granted_slot`.
#      Read by PrototypePlayer.resolve_skill, which prefers the talent's
#      grant over the player's authored @export skills array. HUD
#      rebinds via the granted_skills_changed signal.
#
# Effect kinds owned by talents (keep in sync with consumers):
#   doomsayer_dot_per_tick     — base damage applied each Doomsayer tick to
#                                every uncharmed enemy in the aura, scaled
#                                by linear distance falloff. Read by
#                                PrototypePlayer._tick_doomsayer. Zero with
#                                no allocation = no DoT (the perk only
#                                grants the charm; DoT is a talent unlock).
#
# When a talent ADDS to an existing perk-owned kind (e.g. crit_chance_pct,
# crit_damage_pct, exile_curse_damage_pct, telekinesis_bolts, etc.) the
# consumer should be reading via Effects.get_aggregate so both sources
# combine — see scripts/systems/effects.gd.

signal talents_recomputed
# Fires when the set of talent-granted active skills changes (a node
# was allocated/deallocated AND it had a granted_skill on it). HUD
# listens to rebind hotbar slots; consumers that only care about
# aggregates can stay on `talents_recomputed`.
signal granted_skills_changed

const TREE_DIR := "res://resources/talents/"

# class_id (StringName) → { Vector2i(tier, node_idx) → TalentNode }.
# Built once on _ready by scanning TREE_DIR. Classes with no tree file
# load to empty entries; the recompute loop skips them silently.
var _trees: Dictionary = {}
var _aggregates: Dictionary = {}
# slot StringName (e.g. &"skill_q") → Skill. Computed each recompute
# from active nodes whose `granted_skill` and `granted_slot` are set.
# First-allocated wins on collision; later collisions get a warning.
var _granted_skills: Dictionary = {}

func _ready() -> void:
	_load_trees()
	PlayerState.talents_changed.connect(_recompute)
	PlayerState.level_changed.connect(_on_level_changed)
	PlayerState.class_changed.connect(_on_player_changed)
	PlayerState.spec_changed.connect(_on_player_changed)
	_recompute()


func _load_trees() -> void:
	# Tree files live under TREE_DIR keyed by the legacy 3-letter stat_id
	# (amb.tres, ort.tres, etc.) — same convention PlayerState.talent_allocations
	# and the talents panel UI use. Walk CLASS_DEFINITIONS to enumerate the
	# six class slots, but resolve each to its stat_id via CLASS_TO_STAT
	# before reading the file. Origin classes (analog/cyborg) don't have
	# their own trees; their CLASS_TO_STAT entry is missing and we skip.
	var seen: Dictionary = {}
	for class_id: StringName in AttributeState.CLASS_DEFINITIONS.keys():
		var stat_id: StringName = AttributeState.CLASS_TO_STAT.get(class_id, &"")
		if stat_id == &"" or seen.has(stat_id):
			continue
		seen[stat_id] = true
		var path := "%s%s.tres" % [TREE_DIR, stat_id]
		if not ResourceLoader.exists(path):
			continue
		var tree := load(path) as TalentTree
		if tree == null:
			push_warning("[TalentState] Found %s but it isn't a TalentTree; skipping." % path)
			continue
		var index: Dictionary = {}
		for node in tree.nodes:
			if node == null:
				continue
			var key := Vector2i(node.tier, node.node_idx)
			if index.has(key):
				push_warning("[TalentState] Duplicate node at (%d, %d) on %s — keeping the first." % [node.tier, node.node_idx, stat_id])
				continue
			index[key] = node
		_trees[stat_id] = index
	if _trees.is_empty():
		push_warning("[TalentState] No talent trees loaded — allocated talent nodes won't contribute aggregates.")


func _on_level_changed(_new_level: int, _old_level: int) -> void:
	_recompute()


func _on_player_changed(_id: StringName) -> void:
	_recompute()


func _recompute() -> void:
	var new_aggregates: Dictionary = {}
	var new_granted: Dictionary = {}
	if PlayerState.class_id != &"":
		for stat_id: StringName in _trees.keys():
			var index: Dictionary = _trees[stat_id]
			for key: Vector2i in index.keys():
				var node: TalentNode = index[key]
				if not PlayerState.is_node_active(stat_id, key.x, key.y):
					continue
				for effect in node.effects:
					if effect == null:
						continue
					new_aggregates[effect.kind] = float(new_aggregates.get(effect.kind, 0.0)) + effect.magnitude
				if node.granted_skill != null and node.granted_slot != &"":
					if new_granted.has(node.granted_slot):
						push_warning("[TalentState] Two allocated nodes both grant a skill to slot %s — keeping the first." % node.granted_slot)
					else:
						new_granted[node.granted_slot] = node.granted_skill
	_aggregates = new_aggregates
	var prev_granted := _granted_skills
	_granted_skills = new_granted
	talents_recomputed.emit()
	if not _dicts_equal(prev_granted, new_granted):
		granted_skills_changed.emit()


static func _dicts_equal(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k) or b[k] != a[k]:
			return false
	return true


func get_aggregate(kind: StringName) -> float:
	return _aggregates.get(kind, 0.0)


## Returns the TalentNode at (stat_id, tier, node_idx) or null if no
## node is registered there. Used by the talents panel to render
## tooltips with real label/description text.
func get_node_def(stat_id: StringName, tier: int, node_idx: int) -> TalentNode:
	var index: Dictionary = _trees.get(stat_id, {})
	return index.get(Vector2i(tier, node_idx))


## Returns the Skill granted by an allocated talent node for the given
## hotbar input action (e.g. &"skill_q"), or null if no allocated
## talent has claimed that slot. PrototypePlayer.resolve_skill checks
## this before falling through to the player's @export skills array.
func get_granted_skill_for_slot(slot: StringName) -> Skill:
	return _granted_skills.get(slot)
