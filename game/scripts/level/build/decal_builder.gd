extends RefCounted
class_name DecalBuilder
## Decal-style geometry that sits on the floor — currently only puddles.
## Each puddle is a flat plane with a procedural blob mask in the shader, so
## the silhouette is irregular without per-puddle modelling. The shader runs
## at low roughness so room fluorescents catch as a sharp specular highlight
## on the water surface — that's the "wet" read.

const PUDDLE_SHADER: Shader = preload("res://scripts/prototype/puddle.gdshader")
const PUDDLE_Y := 0.005  ## tiny lift so puddles don't z-fight the floor


static func place_puddles(ctx: LevelBuildContext, center: Vector3, hx: float, hz: float, rd: RoomDef) -> void:
	if rd.puddle_count <= 0:
		return
	# Deterministic placement keyed off the room id so re-entering the room
	# doesn't shuffle puddles. Hash the id string into a seed.
	var seed_hash := 0
	for c in String(rd.id):
		seed_hash = (seed_hash * 31 + c.unicode_at(0)) & 0x7FFFFFFF
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_hash if seed_hash != 0 else 1

	var margin := 1.2  # keep puddles off the wall line
	for i in rd.puddle_count:
		var radius := rng.randf_range(rd.puddle_size.x, rd.puddle_size.y)
		var px := rng.randf_range(-hx + margin + radius, hx - margin - radius)
		var pz := rng.randf_range(-hz + margin + radius, hz - margin - radius)
		_create_puddle(ctx, center + Vector3(px, PUDDLE_Y, pz), radius * 2.0, rng.randf_range(0.0, 100.0))


static func _create_puddle(ctx: LevelBuildContext, pos: Vector3, diameter: float, shader_seed: float) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(diameter, diameter)
	var mat := ShaderMaterial.new()
	mat.shader = PUDDLE_SHADER
	mat.set_shader_parameter(&"seed", shader_seed)
	var inst := MeshInstance3D.new()
	inst.name = &"Puddle"
	inst.mesh = mesh
	inst.material_override = mat
	inst.position = pos
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ctx.root.add_child(inst)
	inst.add_to_group(&"structures")
