extends RefCounted
class_name CeilingBuilder
## The FPS-mode ceiling plane. Hidden by default (the fixed top-down camera
## never sees it) and toggled visible by the FPS view mode.

static func build(ctx: LevelBuildContext) -> void:
	var t := ctx.theme
	var mesh := PlaneMesh.new()
	mesh.size = ctx.layout.ground_size
	if ctx.wall_material != null:
		mesh.material = ctx.wall_material

	var mat := StandardMaterial3D.new()
	mat.albedo_color = t.wall_color if t.wall_shader == null else Color(0.12, 0.12, 0.14)
	mat.metallic = t.wall_metallic if t.wall_shader == null else 0.1
	mat.roughness = t.wall_roughness if t.wall_shader == null else 0.8
	mat.cull_mode = BaseMaterial3D.CULL_BACK

	var inst := MeshInstance3D.new()
	inst.name = &"Ceiling"
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = Vector3(0.0, t.wall_height, 0.0)
	inst.rotation.x = PI
	inst.visible = false
	inst.add_to_group(&"fps_ceiling")
	ctx.root.add_child(inst)
