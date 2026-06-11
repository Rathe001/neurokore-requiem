extends Node

## Catches MeshInstance3D / MultiMeshInstance3D nodes as they enter the
## scene tree and assigns a fallback StandardMaterial3D to any null
## surface. Suppresses the RenderingServer's
## `material_update_dependency / material_casts_shadows /
## material_is_animated / material_get_instance_shader_parameters:
## Parameter "material" is null` log spam that fires once per
## null-material surface per frame.
##
## Lives as an autoload because the main scene's nodes enter the tree
## after autoloads' _ready but BEFORE the main scene's own _ready —
## so connecting node_added from a main-scene script misses the
## level_shell scene's initial children. The autoload _ready fires
## first, the connection is live, every node the main scene adds (and
## every node the level builder streams in afterwards) fires the
## signal at insertion time and my handler patches surfaces in the
## same frame, before the render server processes them.
##
## Implementation lives in XBotRagdoll.ensure_surface_materials_single
## so the same logic that runs for ragdoll bodies also runs everywhere
## else.
func _ready() -> void:
	get_tree().node_added.connect(XBotRagdoll.ensure_surface_materials_single)

# ── Temporary diagnostic sweep ─────────────────────────────────────────
# The node_added hook still leaks ~76 "material is null" errors during
# level build. This sweep names the culprits: every 1s for the first 12s
# it walks the tree and prints any visual node whose active material is
# null. Remove (or gate off) once the leak source is fixed.
const _SWEEP_DEBUG := false
var _sweep_elapsed := 0.0
var _sweep_next := 1.0

func _process(delta: float) -> void:
	if not _SWEEP_DEBUG:
		set_process(false)
		return
	_sweep_elapsed += delta
	if _sweep_elapsed < _sweep_next:
		return
	_sweep_next += 1.0
	if _sweep_elapsed > 12.0:
		set_process(false)
		return
	_sweep(get_tree().root)

func _sweep(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				if mi.get_active_material(i) == null:
					print("[mat-sweep] %s surface %d NULL (mesh=%s)" % [mi.get_path(), i, mi.mesh.get_class()])
	elif node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.material_override == null and mmi.multimesh != null and mmi.multimesh.mesh != null:
			var mesh: Mesh = mmi.multimesh.mesh
			for i in mesh.get_surface_count():
				if mesh.surface_get_material(i) == null:
					print("[mat-sweep] %s MMI surface %d NULL (mesh=%s)" % [mmi.get_path(), i, mesh.get_class()])
	elif node is GPUParticles3D:
		var p := node as GPUParticles3D
		if p.material_override == null and p.draw_pass_1 != null:
			for i in p.draw_pass_1.get_surface_count():
				if p.draw_pass_1.surface_get_material(i) == null and p.process_material != null:
					print("[mat-sweep] %s PARTICLES draw-pass surface %d NULL (mesh=%s)" % [p.get_path(), i, p.draw_pass_1.get_class()])
	for c in node.get_children():
		_sweep(c)
