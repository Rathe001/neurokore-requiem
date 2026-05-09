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


## Slow-pool zone height. Tall enough that a sprinting player doesn't
## punch out the top in one frame, short enough not to catch jumping
## players in mid-air.
const PUDDLE_SLOW_HEIGHT: float = 0.9
## Layer 3 = Player. The Area3D only monitors player CharacterBody3Ds —
## enemies and projectiles ignore the puddle.
const PUDDLE_PLAYER_MASK: int = 4

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
	_attach_slow_zone(inst, diameter)


# Adds an Area3D under the puddle that fires player.enter_slow_pool /
# exit_slow_pool as the local player walks through. Enemies are not on
# the Area3D's mask, so they ignore puddles entirely (intentional —
# enemies don't have a Traction stat to mediate the slow against).
static func _attach_slow_zone(parent: Node3D, diameter: float) -> void:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = PUDDLE_PLAYER_MASK
	area.monitoring = true
	area.monitorable = false
	# Lift the cylinder so it sits ABOVE the floor — the puddle mesh is at
	# y=0.005; centering the slow zone at half-height keeps the zone's
	# bottom flush with the floor and avoids triggering off the player's
	# capsule clipping below the floor on a slope.
	area.position = Vector3(0.0, PUDDLE_SLOW_HEIGHT * 0.5, 0.0)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = diameter * 0.5
	shape.height = PUDDLE_SLOW_HEIGHT
	col.shape = shape
	area.add_child(col)
	parent.add_child(area)
	area.body_entered.connect(_on_puddle_body_entered)
	area.body_exited.connect(_on_puddle_body_exited)


static func _on_puddle_body_entered(body: Node) -> void:
	# Group + method check — guards against the layer mask ever picking up
	# something that isn't a PrototypePlayer (charmed pets etc. shouldn't
	# trip the slow).
	if body.is_in_group(&"player") and body.has_method(&"enter_slow_pool"):
		body.enter_slow_pool()


static func _on_puddle_body_exited(body: Node) -> void:
	if body.is_in_group(&"player") and body.has_method(&"exit_slow_pool"):
		body.exit_slow_pool()
