---
name: call-deferred-typed-arg-gotcha
description: "In Godot 4, both call_deferred(&\"method\", typed_obj) AND method.call_deferred(typed_obj) fail type check. Use closure form: (func(): method(arg)).call_deferred()"
type: project
---

**The bug:**
```gdscript
call_deferred(&"_handle", node)    # ❌ String-name form fails
_handle.call_deferred(node)        # ❌ Callable form ALSO fails in 4.6.2
```
Logs "Error calling deferred method: 'Node(...)::_handle': Cannot convert
argument 1 from Object to Object" — floods the debugger (498 errors in
one session).

**The fix:**
```gdscript
(func() -> void: _handle(node)).call_deferred()  # ✅ Closure captures arg
```

**Why:** Both the string-name form AND the Callable form pass arguments
through Variant at deferred-dispatch time. When the target method has a
typed Object parameter (`func _handle(n: Node)`), the Variant→typed
conversion fails. The closure form avoids this entirely — no argument
crosses the deferred boundary; the closure captures `node` directly and
calls the typed method synchronously inside.

**How to apply:** Any deferred call passing an Object subclass (Node,
Resource, etc.) to a method with a typed parameter → wrap in a closure.

No-arg `call_deferred(&"...")` is fine — the type-check bug only fires
when there's a typed object being passed.

**Known offenders fixed:**
- ui_sounds.gd `_on_node_added` → closure form
- overhang_fader.gd `_on_node_added` → closure form
- prototype_hud.gd → check if `_animate_perk_pip.call_deferred(perk)` also needs fixing
