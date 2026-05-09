extends RefCounted
class_name CeilingBuilder
## The FPS-mode ceiling plane. Visual is hidden by default (the fixed
## top-down camera never sees it) and toggled visible by the FPS view
## mode. The collision shape is always active — projectiles, LoS rays,
## and player jumps interact with the ceiling the same way they do with
## walls and floor (Layer 1 / World).

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

	# Wrap the visual mesh in a StaticBody3D so projectiles and raycasts
	# block on it. Layer 1 (World) — same as floors and walls — so existing
	# WORLD_LAYER_MASK consumers (PrototypeProjectile sweep ray, LosCuller,
	# ProximityLighting) all see the ceiling without further changes.
	var body := StaticBody3D.new()
	body.name = &"Ceiling"
	body.input_ray_pickable = false
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(0.0, t.wall_height, 0.0)
	# Slightly thinner than wall thickness — just enough to register the
	# ray sweep and stop a fast-moving projectile that arcs upward.
	var col := CollisionShape3D.new()
	col.name = &"Collision"
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(mesh.size.x, 0.1, mesh.size.y)
	col.position.y = 0.05  # box top sits at wall_height + 0.1, bottom at wall_height
	body.add_child(col)

	var inst := MeshInstance3D.new()
	inst.name = &"Mesh"
	inst.mesh = mesh
	inst.material_override = mat
	inst.rotation.x = PI
	inst.visible = false
	inst.add_to_group(&"fps_ceiling")
	body.add_child(inst)

	ctx.root.add_child(body)
	body.add_to_group(&"structures")
