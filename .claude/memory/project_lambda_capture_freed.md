---
name: lambda-capture-freed
description: Lambdas that capture Object refs (Nodes) and fire from SceneTreeTimers, node_added, or other tree-bound dispatchers spam "Lambda capture freed" on level reload — capture instance IDs instead.
type: project
originSessionId: 82d6aba9-5758-48bf-8247-4867da37ca36
---
**The error**: `call: Lambda capture at index 0 was freed. Passed "null" instead.` (`gdscript_lambda_callable.cpp:242`). Has hit us multiple times — including one playtest with 5754 occurrences. Only `func() -> void:` lambdas trigger this exact message; bound-method Callables (`node.queue_free` directly) fail differently.

**Why it happens**: GDScript lambdas capture variables by reference. When the captured variable is an `Object` (Node, RefCounted), the lambda machinery validates `is_instance_valid()` AT CALL TIME, BEFORE running the body — `ERR_FAIL_MSG` fires and the body never runs. `is_instance_valid(x)` checks inside the body don't help, they're already skipped.

`Resource` (RefCounted) captures are safe — the lambda's capture holds a strong ref, keeping the resource alive. Only `Node` captures are the problem (lambda holds a weak ref).

**The trap**: `get_tree().create_timer()` returns a SceneTreeTimer attached to the SceneTree itself, NOT to the host node. Same for `get_tree().node_added` / `tree_exited` / etc. These survive scene reloads, so callbacks fire AFTER the level has rebuilt and the captured Node is freed.

**Highest-volume offenders we've hit**:

- `OverhangFader._on_node_added` (autoload): deferred-scheduled a lambda for every MeshInstance3D added to the tree (hundreds per level build).
- `UISounds._on_node_added` (autoload): same pattern, for every Control / Button (even higher rate).
- `prototype_attack_indicator.gd` blood/spark/explosion VFX: 15+ sites binding `node.queue_free` / `_release_light.bind(light)` to a SceneTreeTimer or detached tween.
- Combat windup timers in `prototype_player.gd:_fire_volley` and `player_combat.gd` multistrike/double-tap: implicit `self` capture invalidated when the level reloads mid-windup.
- `player_telekinesis.gd` bolt stagger: captured both `self` (PlayerTelekinesis Node) and the target enemy (frequently killed mid-stagger).

**Fix pattern**:

```gdscript
var nid: int = node.get_instance_id()
timer.timeout.connect(func() -> void:
    var n := instance_from_id(nid) as Node
    if n != null:
        # original body, using n instead of node
)
```

When the lambda body referenced instance vars implicitly (`_alive`, `_combat`, etc.) — *implicit self capture* — prefix every reference with the resolved local (`s._alive`, `s._combat`) so `self` isn't captured at all.

**Helpers** (in `prototype_attack_indicator.gd`):

- `static func _free_later(node) -> Callable` — returns a Callable safe to bind to tween_callback / timeout.connect in place of `node.queue_free`.
- `static func _release_light_later(light) -> Callable` — same idea for `_release_light.bind(light)` (pooled OmniLight3D release).

Use these for any new VFX that schedules a free.

**Where it's safe to leave bound `.queue_free`**: when the tween is hosted on `self` AND the captured method is on `self` — `create_tween()` ties tween lifetime to the host, so when `self` queue_frees the tween dies with it and the callback never fires. Examples that don't need the dance: `loading_screen.gd`, `prototype_item_pickup.gd`, `prototype_ragdoll_corpse.gd`, `destructible_prop.gd`. Tween hosted on `host_node` with callback to a different `target_node.queue_free` IS the dangerous pattern.

**Debugging tip**: the error message has no GDScript stack trace because the caller is C++ (Tween/Timer dispatcher). Grep for `func() ->` near `tween_callback`, `timeout.connect`, `node_added.connect`, `call_deferred` — those are the suspect sites. Only the ones with Object captures matter.
