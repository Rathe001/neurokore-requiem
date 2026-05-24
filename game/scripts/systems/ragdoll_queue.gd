extends Node

## Ratelimits ragdoll setup+activate so a multi-kill explosion can't stack
## 5× XBotRagdoll.setup() (~100 PhysicalBone3D + 100 Jolt joint constraints)
## into one frame. Perf logs showed recurring 100-200ms proc spikes that
## correlated 1:1 with enemy-death bursts; spreading the cost across N
## frames flattens them to ~40ms each — imperceptible at 60fps.
##
## Usage:
##   var got_slot := await RagdollQueue.await_slot()
##   if got_slot:
##       XBotRagdoll.setup(skel)
##       XBotRagdoll.activate(skel, ...)
##
## await_slot() returns true once a slot is granted (max wait ~8 frames at
## the cap) or false if the cap is somehow saturated for the whole window
## (which would mean 16+ near-simultaneous deaths and is fine to drop).

# How many ragdoll setup+activate pairs we'll let through per frame.
# Each pair costs ~30-50ms locally (20 PhysicalBone3D × Jolt body+joint
# instantiation), so 2 per frame ≈ one frame's worth of budget at the
# 8ms-per-ragdoll ceiling. Bump to 3 if combat feels starved of physics
# reactions; drop to 1 if 2 still produces visible hitches.
const MAX_RAGDOLLS_PER_FRAME: int = 2

# Cap on how long await_slot will block before giving up and returning
# false. 8 frames at 60fps = 133ms — beyond that and the caller is
# better off falling back to the legacy capsule corpse than waiting.
const AWAIT_MAX_FRAMES: int = 8

var _used_this_frame: int = 0


func _ready() -> void:
	# Run BEFORE everyone else's _process so the counter resets at the
	# very top of the frame, before any death paths fire. Negative
	# priority = earlier execution.
	process_priority = -1000


func _process(_delta: float) -> void:
	_used_this_frame = 0


# ── Public API ──────────────────────────────────────────────────────────────

## Synchronous, non-awaiting variant. Returns true and consumes a slot if
## one is available this frame, false otherwise. Use when the caller is
## OK falling back to a cheaper death path on miss.
func try_consume() -> bool:
	if _used_this_frame >= MAX_RAGDOLLS_PER_FRAME:
		return false
	_used_this_frame += 1
	return true


## Awaits until a slot is available, up to AWAIT_MAX_FRAMES. Returns true
## when consumed, false if the budget was saturated for the whole window.
##
## Note: callers MUST validate they're still in_tree after the await —
## the enemy could be freed mid-wait (level reload, pool recycle).
func await_slot() -> bool:
	for _i in AWAIT_MAX_FRAMES:
		if try_consume():
			return true
		await get_tree().process_frame
	return false
