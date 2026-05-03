class_name PrototypeTrap
extends Area3D

# Survivalist Improvised Explosive Device — proximity-detonated trap
# tossed at the cursor on every LMB attack while the perk is active.
# PrototypePlayer manages the active set (FIFO cap from the perk
# aggregate); each trap manages its own lifetime and detonation.
#
# Lifecycle:
#   spawn (positioned by player) → wait for enemy entry OR timer expiry
#   on enemy entry → detonate (AoE damage in BLAST_RADIUS) → queue_free
#   on timer expiry → silent despawn → queue_free
#
# Damage scales with the player's main stat (Ingenuity for Survivalist)
# via AttributeState.get_player_damage_mult, captured at spawn time so
# the trap doesn't reach back into PlayerState on detonation (player may
# have changed class / spec mid-trap-life).

const LIFETIME := 15.0
const BLAST_RADIUS := 2.6
const BASE_DAMAGE := 28
const KNOCKBACK := 6.0
# Brief arming delay so a trap tossed onto an enemy that's already inside
# the trigger doesn't insta-detonate the same frame as the toss. The
# player should see the trap land first.
const ARM_DELAY := 0.3

var _life_remain: float = LIFETIME
var _arm_remain: float = ARM_DELAY
var _detonated: bool = false
var _captured_damage_mult: float = 1.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_captured_damage_mult = AttributeState.get_player_damage_mult(PlayerState.class_id, PlayerState.spec_id)


func _process(delta: float) -> void:
	if _detonated:
		return
	if _arm_remain > 0.0:
		_arm_remain -= delta
		# Once armed, scan for an enemy already inside the trigger — the
		# body_entered signal only fires on transitions, not on overlap at
		# arm-time. Without this, an enemy parked on the trap during the
		# arm window would never trigger it.
		if _arm_remain <= 0.0:
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
		n.take_damage(dmg, global_position, KNOCKBACK)
	queue_free()
