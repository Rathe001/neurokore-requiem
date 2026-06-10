---
name: godot4-runtime-gotchas
description: "Four Godot 4.6 + Jolt runtime gotchas discovered during the X Bot ragdoll + transient-VFX work. Each one renders something wrong silently."
type: project
---

Behaviours that aren't documented anywhere obvious and silently render
something wrong. Worth knowing about before adding any new transient
VFX / physics / soft-particle effect.

**1. `gi_mode` defaults to STATIC on GeometryInstance3D.** Every
MeshInstance3D / GPUParticles3D / MultiMeshInstance3D gets
voxelized into SDFGI's indirect-light cascade by default. Fine for
level geometry; **disastrous for transient VFX** — for the ~2s a
flipbook explosion or particle burst is alive, SDFGI treats it as
a solid 8×8m wall and carves a dark rectangle of "indirect light
occluded here" into the floor underneath it. Always
`gi_mode = GI_MODE_DISABLED` on:
- Explosion flipbook quads
- Flash spheres
- Spark particles
- Any moving / flickering visual that lives less than ~5 seconds

This was invisible until SDFGI got re-enabled in 15fe46a.

**2. `depth_draw_opaque` + soft-particle alpha = self-reference.**
Soft-particle shaders sample `depth_texture` to compute alpha based
on the distance between the fragment's depth and nearby scene
geometry. If the shader's render_mode is `depth_draw_opaque`, the
quad writes its own depth into the buffer FIRST, then reads
`depth_texture` and gets its own depth back — distance-to-self = 0,
alpha collapses to 1.0, the quad renders as a solid 8×8m rectangle
showing whatever dark gradient the flipbook had at those UVs. Fix:
`render_mode blend_mix, depth_draw_never, ...`. This was the original
"black box explosion" bug. May have worked in earlier Godot versions
that snapshotted `depth_texture` before the transparent pass started;
4.6 reads the live buffer.

**3. Jolt rejects non-uniform collision scale.** Mixamo bone bind
matrices carry tiny non-uniform scale residue (typical
0.99×1.01×0.99) from the FBX→Godot transform decomposition. If you
add a PhysicalBone3D to a skeleton bone and start simulation, Jolt
logs `_try_build_shape: Failed to correctly scale body... scale of
(0.99x, 1.02y, 0.99z) is not supported` for every bone every kill,
spamming the Output panel. Fix: orthonormalize each PhysicalBone3D's
basis before `physical_bones_start_simulation()` — strips the
scale residue while preserving rotation. Should be done in the
same loop that syncs bone poses.

**4. ufbx vs FBX2glTF scale handling.** Godot 4.6 ships ufbx as the
default FBX importer (`fbx/importer=0`). ufbx handles the cm→m unit
conversion natively, so `nodes/root_scale=1.0` is correct for
Mixamo FBXs. **The old FBX2glTF habit of setting root_scale=0.01
produces a 1.78cm enemy** (invisible at iso distance). The
dropdown value in the Import dock can be misleading too — value 0
is ufbx in this version, but the label may not match older
documentation. Check via `strings`-ing the imported `.scn` for
known bone-name patterns to confirm what importer is actually
running.

**Bonus: `Node.name` shadowing.** GDScript 2.0 will fail type
inference on `var name := pb.bone_name` if `name` shadows
`Node.name` (a `StringName` property), even though
`PhysicalBone3D.bone_name` is a `String`. The error reads "Cannot
infer the type of 'name' variable because the value doesn't have a
set type". Annotate explicitly: `var bone_name_str: String =
pb.bone_name` — or just avoid `name` as a local variable name when
working in `Node`-derived contexts.

**6. Typed `var x: Node = dict[key]` fails on freed instance.**
Pulling a possibly-freed Object reference from a Dictionary into a
strictly-typed variable raises `Trying to assign invalid previously
freed instance` because the type-cast happens BEFORE you can guard
with `is_instance_valid`. Variant typing dodges this entirely:
```gdscript
# BAD — crashes if dict holds a freed Node reference:
var copy: Node = _copies[key]
if is_instance_valid(copy): copy.queue_free()

# GOOD — Variant accepts the freed handle, guard then cast:
var copy_var: Variant = _copies[key]
if is_instance_valid(copy_var) and copy_var is Node:
    (copy_var as Node).queue_free()
```
Bit `outline_compositor._drop_key` in level-reload (the dict held
freed entries from the prior level). Pattern applies anywhere a
Dictionary or Array can outlive its Object values — particularly
across EntityPool recycle and scene reload.

**7. `fract()` is shader-only — GDScript has no builtin.** Use
`x - floor(x)` instead. The error reads `Parse Error: Function
"fract()" not found in base self` and is easy to miss because shader
code uses fract() constantly (every hash/noise expression). Bit us in
`prototype_attack_indicator.gd` procedural texture generation — the
noise hash needed fract for [0,1) wrapping. Same warning applies to
other shader builtins missing from GDScript: `mix()` (use `lerp`),
`mod()` (use `fposmod` or `%`).

**8. GPUParticles3D with `local_coords=false` ignores node scale —
size via the draw-pass mesh, in direct meters.** Scaling the particle
node (or any ancestor) does nothing to world-space particles; the
"sizing" code can be a silent no-op for years (the explosion flipbook
rendered at its authored 8×8m for every blast size — fx.scale was
never read). Fix: duplicate `draw_pass_1`, set its mesh size, and grow
`visibility_aabb` to match or large quads self-cull. Second trap in
the same fix: prefer DIRECT METERS over a scale factor multiplied
onto the authored size — `8m × clamp(...)≈0.9` produced a 7.2m quad
vs the old 8m, visually identical, and read as "fix didn't work" twice
(commits 194df16, 495d781; real fix 114d7da).

**5. RichTextLabel `[font_size=N]` is ABSOLUTE, not relative.** Both
the bare `[font_size=N]` BBCode tag and `add_theme_font_size_override`
on a RichTextLabel set the pixel size directly. If the label's base
font is configured to `normal_font_size = 7` (e.g. the item tooltip's
stats block), then `[font_size=10]` inside the BBCode RENDERS LARGER
than the surrounding body, not smaller. Cost me two iterations on the
behavior-mod tooltip — I assumed font_size 10 was "compact" because
default Godot Labels are usually ~16pt, forgot the tooltip overrides
the base to 7pt. Sanity check: grep the label's
`add_theme_font_size_override` calls to confirm the base size before
picking a BBCode override. To make text smaller than base, omit the
tag entirely (inherit base) or use a value LOWER than the configured
base. To match base, just don't tag it.
