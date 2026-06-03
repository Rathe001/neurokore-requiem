---
name: liquid-layer-stamp-lifecycle
description: "One-frame LiquidLayer.stamp_* sprites must outlive the SubViewport render pass — use create_timer(0.1), not process_frame.connect, or stamps silently never deposit."
type: project
---

`LiquidLayer.stamp` / `stamp_oriented` add a `Sprite2D` to the SubViewport's stamp root, then schedule cleanup. The catch: **the cleanup signal must fire AFTER the SubViewport renders, not before.**

**Why:** `SceneTree.process_frame` is emitted before the rendering server runs that frame's draw pass. If you connect cleanup there and `queue_free` the sprite, the SubViewport sees an empty tree on render and the stamp deposits nothing into the persistent mask. The mask shader then samples zero coverage at those pixels — visible result: no footprint, no splatter, nothing.

**Symptom that bit me:** footprints went through the full pipeline (group lookup found the layer, alpha calculated correctly, debug prints showed every stamp firing) but rendered nothing visible. Pools still worked because `stamp_growing` keeps its sprite alive via a tween that lasts multiple frames.

**Fix:** keep the sprite alive long enough for at least one full render frame. `create_timer(0.1)` covers several render frames and self-cleans. Pattern:

```gdscript
_stamp_root.add_child(sprite)
var stamp_id := sprite.get_instance_id()
var t := get_tree().create_timer(0.1)
t.timeout.connect(
    func() -> void:
        var s := instance_from_id(stamp_id)
        if s != null and is_instance_valid(s):
            (s as Node).queue_free(),
    CONNECT_ONE_SHOT,
)
```

**How to apply:** any new directional/one-shot stamp method on LiquidLayer (e.g. drag marks, scuff trails) — never `process_frame.connect` for the free, always a short timer.

**Why not move to tween:** `stamp_growing`'s tween works because it actually mutates scale over time, requiring the sprite alive multiple frames. For static one-shot stamps a timer is simpler.

Related: [[liquid_layer]], [[blood-migration-status]] (footprint migration where this bug surfaced).
