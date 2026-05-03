class_name TalentNode extends Resource

## One node on a class talent tree. (tier, node_idx) addresses where it
## sits in the 8×3 grid the talents panel renders. Effects reuse the
## PerkEffect schema (kind / magnitude) so the same aggregate keys can
## be sourced from either system, but TalentState aggregates separately
## from PerkState — consumers decide whether to combine them.

@export var id: StringName = &""
@export var label: String = ""
@export var description: String = ""
# 0-indexed tier (0..2) and node index within the tier (0..7). Must
# match the slot in the panel; TalentState indexes by (tier, node_idx)
# on load and warns on collisions.
@export var tier: int = 0
@export var node_idx: int = 0
@export var effects: Array[PerkEffect] = []
# Optional active-skill grant. When `granted_skill` is set and
# `granted_slot` names a skill input (e.g. &"skill_q", &"skill_1"),
# allocating this node binds the skill to that hotbar slot. Two
# allocated nodes targeting the same slot is a configuration error;
# TalentState keeps the first-loaded one and warns. Leave both fields
# empty for talents that only modify aggregates.
@export var granted_skill: Skill = null
@export var granted_slot: StringName = &""
