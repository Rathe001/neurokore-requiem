---
name: call-deferred-typed-arg-gotcha
description: "In Godot 4, call_deferred(&\"method\", typed_object_arg) fails the deferred-dispatch type check with \"Cannot convert argument 1 from Object to Object\". Always use the Callable form for deferred calls with typed Object args."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8cb2236a-ff5a-4a76-8cc4-a33a9a8014b8
---

**The bug:**
```gdscript
call_deferred(&"_handle", node)  # ❌ Errors at deferred-dispatch time
```
Logs "Error calling deferred method: 'Node(...)::_handle': Cannot convert
argument 1 from Object to Object" — once per call, can flood the
debugger (172 errors per session was the worst case).

**The fix:**
```gdscript
_handle.call_deferred(node)  # ✅ Callable form preserves typing
```

**Why:** The string-name form of `call_deferred` looks up the method by
name and re-binds arguments at deferred-dispatch time. The Variant-typed
binding doesn't match the method's typed Object parameter on dispatch.
The Callable form captures the binding at the call site, so types are
preserved through the defer.

**How to apply:** Any `call_deferred(&"...", arg)` where `arg` is an
Object subclass (Node, Resource, etc.) and the target method has a
typed parameter (`func _handle(n: Node)` not `func _handle(n)`) → swap
to `<method>.call_deferred(arg)`.

No-arg `call_deferred(&"...")` is fine — the type-check bug only fires
when there's a typed object being passed.

**Known offenders fixed (search for `call_deferred(&"` if more turn up):**
- ui_sounds.gd `_on_node_added` → `_try_wire.call_deferred(node)`
- overhang_fader.gd `_on_node_added` → `_maybe_register.call_deferred(node)`
- prototype_hud.gd → `_animate_perk_pip.call_deferred(perk)`
