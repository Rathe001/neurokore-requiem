extends RefCounted
class_name CeilingBuilder
## The FPS-mode ceiling plane. Visual is hidden by default (the fixed
## top-down camera never sees it) and toggled visible by the FPS view
## mode. The collision shape is always active — projectiles, LoS rays,
## and player jumps interact with the ceiling the same way they do with
## walls and floor (Layer 1 / World).

## How far the ceiling's shadow caster extends past the level's bounding
## box on each side. Light spilling over wall tops would escape into the
## void outside the level and illuminate volumetric fog there, producing
## a "halo" around the playable area. The shadow caster needs to cover
## that void too — 50m past each edge is enough to outrun even the
## longest ceiling-light range without burning shadow-map resolution.
const SHADOW_OVERHANG := 50.0

## A flat unshaded black "void cover" plane sitting just below the floor.
## Pure absorber for anything the iso camera might see in the area beyond
## the level walls — player headlight leaking past corners, screen-space
## effects (SSAO/glow) bleeding bright pixels outward, etc. Unshaded so
## no light can lift it from pure black. Sized like the ceiling so it
## extends well past the level footprint.
const VOID_COVER_Y := -0.05  # below room floors (y=0) so it doesn't z-fight
static func build_void_cover(ctx: LevelBuildContext) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = ctx.layout.ground_size + Vector2(SHADOW_OVERHANG * 2.0, SHADOW_OVERHANG * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.BLACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	var inst := MeshInstance3D.new()
	inst.name = &"VoidCover"
	inst.mesh = mesh
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	inst.position = Vector3(0.0, VOID_COVER_Y, 0.0)
	ctx.root.add_child(inst)


static func build(ctx: LevelBuildContext) -> void:
	var t := ctx.theme
	var mesh := PlaneMesh.new()
	# Visual mesh extends well past the level bounds so the SHADOWS_ONLY
	# pass covers the void area too. Collision (below) stays sized to the
	# level so projectile sweeps don't hit invisible ceiling out in the void.
	mesh.size = ctx.layout.ground_size + Vector2(SHADOW_OVERHANG * 2.0, SHADOW_OVERHANG * 2.0)
	if ctx.wall_material != null:
		mesh.material = ctx.wall_material

	# Ceiling is invisible in iso (SHADOWS_ONLY below) and only renders in
	# FPS mode. Hard-coded dark grey since the value barely shows; if we
	# ever want a per-theme ceiling tint we can add a theme field for it.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.12, 0.14)
	mat.metallic = 0.1
	mat.roughness = 0.8
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
	# Collision stays sized to the level proper — the visual mesh was
	# enlarged to extend the SHADOWS_ONLY caster into the void, but we
	# don't want projectile sweeps or LoS rays terminating on invisible
	# ceiling out past the playable area.
	var col_size := ctx.layout.ground_size
	(col.shape as BoxShape3D).size = Vector3(col_size.x, 0.1, col_size.y)
	col.position.y = 0.05  # box top sits at wall_height + 0.1, bottom at wall_height
	body.add_child(col)

	var inst := MeshInstance3D.new()
	inst.name = &"Mesh"
	inst.mesh = mesh
	inst.material_override = mat
	inst.rotation.x = PI
	# SHADOWS_ONLY keeps the ceiling invisible in iso view (so the
	# top-down camera still sees the room contents) but lets it occlude
	# light. Without this, ceiling fluorescents sprayed light over the
	# wall tops and lit up exterior surfaces / outside fog, since the
	# rooms have no opaque shadow-caster between the lights and the sky.
	# The FPS toggle below swaps this to SHADOW_CASTING_SETTING_ON to
	# make the ceiling visible while still casting shadow.
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	inst.add_to_group(&"fps_ceiling")
	body.add_child(inst)

	ctx.root.add_child(body)
	body.add_to_group(&"structures")
