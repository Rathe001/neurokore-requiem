class_name PrototypeTrap
extends Area3D

# Survivalist Improvised Explosive Device — proximity-detonated trap
# tossed at the cursor on every LMB attack while the perk is active.
# PrototypePlayer manages the active set (FIFO cap from the perk
# aggregate); each trap manages its own lifetime and detonation.
#
# Lifecycle:
#   spawn (positioned + arm_delay set by player) → arm window (visible
#   pulsing, won't trigger) → armed (won't visibly pulse, ready to
#   detonate on enemy entry) → detonate OR lifetime expiry → queue_free
#
# Arm window length scales with the player's IED tier — set by the
# caller via `arm_delay` before `add_child`. Higher tiers = shorter
# arm window. The pulse during arming gives the player visual
# feedback that the trap isn't yet live.
#
# Damage mult is captured at spawn time so the trap doesn't reach back
# into PlayerState on detonation (player may have changed class / spec
# mid-trap-life). Gear-based bonuses will come via stat_modifiers.

const LIFETIME := 15.0
const BLAST_RADIUS := 2.6
const BASE_DAMAGE := 28
const KNOCKBACK := 6.0

# Arming pulse — emission energy oscillates between min and max during
# the arm window so the player can read the trap as "not live yet."
# Once armed the material snaps to ARMED_EMISSION (the .tscn baseline).
const ARM_PULSE_HZ := 3.0          # full pulses per second
const ARM_EMISSION_MIN := 0.4
const ARM_EMISSION_MAX := 1.6
const ARMED_EMISSION := 5.0
const ARM_LIGHT_MIN := 0.4
const ARM_LIGHT_MAX := 1.4
const ARMED_LIGHT_ENERGY := 1.6

# Set by the caller (PrototypePlayer._toss_ied_trap) BEFORE add_child
# fires _ready. Default fallback exists for any caller that forgets,
# so the trap still arms eventually rather than being permanently inert.
@export var arm_delay: float = 0.5

var _life_remain: float = LIFETIME
var _arm_remain: float = 0.0
var _arm_t: float = 0.0  # accumulator for pulse phase
var _detonated: bool = false
var _captured_damage_mult: float = 1.0
var _mesh_material: StandardMaterial3D
var _glow: OmniLight3D


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_arm_remain = arm_delay
	_captured_damage_mult = 1.0
	# Cache visual handles so the per-frame pulse doesn't repeat node
	# lookups. The .tscn gives each instance its own SubResource copy of
	# the material, so modulating it per-trap doesn't bleed across the
	# active set.
	var mesh: MeshInstance3D = $Mesh
	if mesh != null and mesh.material_override is StandardMaterial3D:
		_mesh_material = mesh.material_override
	_glow = $Glow as OmniLight3D
	# Start the visible pulse at its minimum so the trap appears to
	# "wake up" rather than pop in at full brightness.
	if _mesh_material != null:
		_mesh_material.emission_energy_multiplier = ARM_EMISSION_MIN
	if _glow != null:
		_glow.light_energy = ARM_LIGHT_MIN


func _process(delta: float) -> void:
	if _detonated:
		return
	if _arm_remain > 0.0:
		_arm_remain -= delta
		_arm_t += delta
		var pulse := 0.5 + 0.5 * sin(_arm_t * ARM_PULSE_HZ * TAU)
		if _mesh_material != null:
			_mesh_material.emission_energy_multiplier = lerpf(ARM_EMISSION_MIN, ARM_EMISSION_MAX, pulse)
		if _glow != null:
			_glow.light_energy = lerpf(ARM_LIGHT_MIN, ARM_LIGHT_MAX, pulse)
		# Once armed, snap visuals to the "live" look and scan for any
		# enemy already inside the trigger — body_entered only fires on
		# transitions, not on overlap at arm-time. Without this scan, an
		# enemy parked on the trap during the arm window would never
		# trigger it.
		if _arm_remain <= 0.0:
			if _mesh_material != null:
				_mesh_material.emission_energy_multiplier = ARMED_EMISSION
			if _glow != null:
				_glow.light_energy = ARMED_LIGHT_ENERGY
			for body in get_overlapping_bodies():
				if body.is_in_group(&"enemies") and (body as Node3D).has_method(&"take_damage"):
					_detonate()
					return
	_life_remain -= delta
	if _life_remain <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if _detonated or _arm_remain > 0.0:
		return
	if not body.is_in_group(&"enemies"):
		return
	if not body.has_method(&"take_damage"):
		return
	# Charmed enemies are allies — they shouldn't trigger the trap they
	# walked over. Skipping here keeps the trap armed for a real enemy.
	if body.has_method(&"is_player_friendly") and body.is_player_friendly():
		return
	_detonate()


func _detonate() -> void:
	_detonated = true
	# Visual: radial pulse at the trap point so the AoE landing reads.
	# Reuses the same indicator the player's hitscan paths use, anchored
	# to self so the ring scales correctly even if the trap was nudged by
	# physics (it isn't, but cheap insurance).
	PrototypeAttackIndicator.spawn_hit_radial(self, BLAST_RADIUS)
	var dmg := int(round(float(BASE_DAMAGE) * _captured_damage_mult))
	for n in SpatialGrid.query_radius(global_position, BLAST_RADIUS, &"enemies"):
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		if not n.has_method(&"take_damage"):
			continue
		# Spare friendly (charmed) enemies caught in the blast radius.
		if n.has_method(&"is_player_friendly") and n.is_player_friendly():
			continue
		n.take_damage(dmg, global_position, KNOCKBACK)
	queue_free()
