---
name: mp-damage-heal-routing
description: PrototypePlayer.apply_damage + apply_heal static helpers route damage/heal across MP authority boundaries. Mirror of PrototypeEnemy.deal_damage. Every cross-actor damage source must use these — direct take_damage / heal early-returns on non-authority targets in MP.
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

MP authority routing for player damage + heal. Mirrors the
[[PrototypeEnemy.deal_damage]] pattern but for the inverse direction
(enemy → player). Added 2026-06-03 as audit Phase 1a (commit `8880d59`)
+ Phase 3 (commit `9339c96`).

## The bug pattern this prevents

`PrototypePlayer.take_damage` and `PrototypePlayer.heal` only apply
state changes on the LOCAL authority instance. In MP:

- Host runs enemy AI. Enemy melee/projectile damages a player.
- If the target is a remote player, the host's reference to that
  player is non-authority. Calling `remote_player.take_damage(...)`
  early-returns at `if _is_remote_player(): return`.
- Damage silently drops. Remote co-op players were invincible to all
  enemy damage until this routing landed.

Same issue lurks for any heal that targets a player not owned by the
calling peer.

## The helpers

```gdscript
# Damage routing (apply_damage + request_damage):
static func apply_damage(target: Node3D, amount: int,
        knockback_from: Vector3, knockback_strength: float = 0.0) -> void:
    if not (target is PrototypePlayer):
        # Defensive fallback for callers that pass Node3D
        if target.has_method(&"take_damage"):
            target.take_damage(amount, knockback_from, knockback_strength)
        return
    if NetState.is_in_lobby() and not target.is_multiplayer_authority():
        var auth_id: int = target.get_multiplayer_authority()
        target.request_damage.rpc_id(auth_id, amount,
            knockback_from, knockback_strength)
        return
    target.take_damage(amount, knockback_from, knockback_strength)

@rpc("any_peer", "call_remote", "reliable")
func request_damage(amount: int, knockback_from: Vector3,
        knockback_strength: float) -> void:
    if not is_multiplayer_authority(): return
    if not is_inside_tree(): return
    take_damage(amount, knockback_from, knockback_strength)
```

`apply_heal` + `request_heal` follow the identical pattern with the
heal's narrower 1-arg signature.

## When to use these vs direct take_damage / heal

**Always use the helper** when the caller is on the enemy side or any
authority other than the player target's own peer:

- `enemy_combat.gd:248` melee attack
- `enemy_combat.gd:436` directed skill (player branch)
- `enemy_combat.gd:473` AoE radial (player branch)
- `prototype_projectile.gd:762` direct hit on player
- `prototype_projectile.gd:845` AoE blast on player

**Direct take_damage / heal is fine** when:
- Self-targeting on the same peer (`_host.heal(amount)` from
  `player_recovery` is the canonical case — the local player heals
  themselves on their own peer; authority always matches)
- `_host.take_damage(tick_dmg)` from `enemy_afflictions` — enemy
  self-DoT runs on the host, host owns the enemy
- Environmental (pit/ground hazard) Area3D fires on each peer for
  THEIR local player — the Area is per-peer, the take_damage call
  reaches the local authority instance

## Why hit visuals work without separate RPC

`take_damage` on the player authority already triggers
`HitFlash`, blood-on-character splatter, hit grunt SFX, and damage
numbers locally. Those are visible TO that player. Other peers see
the health bar update via `health_changed` signal replication (if
wired) or via the next state sync.

If you need cross-peer hit visuals like the enemy's
`_client_show_hit` RPC (damage numbers above the head visible to
everyone), you'd add a parallel `@rpc("authority", "call_remote",
"unreliable")` on the player. Not done today — only the player who
took the hit sees their own hit feedback. Acceptable for now.

## Adding new player-damage callers

Any new code path that damages or heals a player from outside that
player's own authority MUST go through `apply_damage` / `apply_heal`.
Check: is the caller running on the host or a different peer than
the target? If yes, use the helper. If unsure, use the helper anyway
— the helper handles the SP case correctly too (calls take_damage
directly).

## Related

- [[PrototypeEnemy.deal_damage]] — reference pattern (line 1218)
- [[feedback_mp_sp_parity]] — the audit memory that flagged this gap
- [[project_audit_2026_06_03]] — full audit findings including this
  one as 🟥 #1 with commit history
