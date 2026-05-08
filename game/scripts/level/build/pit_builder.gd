extends RefCounted
class_name PitBuilder
## Pit geometry: shafts (4 inner walls + bottom dressing), ooze / spike /
## bottomless variants, room-pit perimeter strips with pillars, and pillar
## marker lights. Kill volume itself is owned by GroundBuilder — pit
## visuals live above that and never create their own kill area.

enum Kind { OOZE, SPIKES, BOTTOMLESS }

# Bottomless pits use a deeper shaft so the abyss reads as truly deep
# rather than just slightly-deeper-than-normal. Kill zone catches falls
# regardless (it sits at y = -10).
const BOTTOMLESS_DEPTH := 10.0

# Pillar visuals sit a hair below the corridor's floor bias (-0.0015) so the
# corridor floor wins in the overlap zone where pillars at room openings
# overlap the corridor's FLOOR_OVERLAP extension into the room. Keeping
# collision at y=0 means jump landings still hit the expected height — only
# the rendered top face moves. 5 mm easily out-resolves depth-buffer
# precision at the player's view distance, invisible at the top-down camera.
const PILLAR_TOP_Y_BIAS := -0.005


# Generic pit shaft: 4 inner walls + optional bottom dressing, sized by
# inner_x × inner_z. Used by both corridor pits (gap in the floor) and
# full-room pits with a perimeter floor strip. `kind` picks the bottom:
#   OOZE       — glowing green pool, lit (default)
#   SPIKES     — dark stone + impalement spikes + amber rim light
#   BOTTOMLESS — no floor, deeper shaft, no light. Pure abyss.
static func build_pit_shaft(ctx: LevelBuildContext, center: Vector3, inner_x: float, inner_z: float, kind: Kind = Kind.OOZE) -> void:
	var t := ctx.theme
	var depth := BOTTOMLESS_DEPTH if kind == Kind.BOTTOMLESS else t.pit_depth
	var thick := t.wall_thickness
	var hx := inner_x * 0.5
	var hz := inner_z * 0.5

	# East / west walls (along Z) — sit at the inner_x extremes.
	for s in [-1.0, 1.0]:
		_create_pit_wall(ctx,
			center + Vector3(s * hx, -depth * 0.5, 0.0),
			thick, depth, inner_z, ctx.wall_material_alt)
	# North / south walls (across X) — extended by thick on each side so the
	# corner where they meet the E/W walls is fully filled (no light leak).
	for s in [-1.0, 1.0]:
		_create_pit_wall(ctx,
			center + Vector3(0.0, -depth * 0.5, s * hz),
			inner_x + thick * 2.0, depth, thick, ctx.wall_material_alt)

	match kind:
		Kind.SPIKES:
			_build_pit_floor_spikes(ctx, center, inner_x, inner_z, depth)
		Kind.BOTTOMLESS:
			pass  # no floor — fall into darkness
		_:
			_build_pit_floor_ooze(ctx, center, inner_x, inner_z, depth)

	# Per-pit kill area at the pit's actual bottom — without this the global
	# kill zone catches the player ~1m below the rim and they die mid-fall.
	# With it, the player falls the full visible depth before dying, which
	# is especially important for bottomless pits where the visual depth is
	# the whole point.
	_create_pit_kill_area(ctx, center, inner_x, inner_z, depth)


static func _create_pit_kill_area(ctx: LevelBuildContext, center: Vector3, inner_x: float, inner_z: float, depth: float) -> void:
	var kill := Area3D.new()
	kill.name = &"PitKillArea"
	kill.collision_mask = 0xFFFFFFFF
	# Sit just below the visual pit floor (or just above the abyss for
	# bottomless) — half-meter slab so a fast-falling body can't tunnel
	# through it in a single physics frame.
	kill.position = center + Vector3(0.0, -depth - 0.25, 0.0)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	(shape.shape as BoxShape3D).size = Vector3(inner_x, 0.5, inner_z)
	kill.add_child(shape)
	kill.body_entered.connect(func(body: Node) -> void:
		if body.has_method(&"set_death_cause"):
			body.set_death_cause(&"pit")
		if body.has_method(&"take_damage"):
			body.take_damage(9999, Vector3.ZERO, 0.0)
	)
	ctx.root.add_child(kill)


static func build_room_pit(ctx: LevelBuildContext, center: Vector3, rd: RoomDef) -> void:
	var t := ctx.theme
	var thick := t.wall_thickness
	var hx := rd.size.x * 0.5
	var hz := rd.size.y * 0.5
	var margin := maxf(0.0, rd.pit_margin)
	var inner_x := rd.size.x - margin * 2.0
	var inner_z := rd.size.y - margin * 2.0

	# Defensive: if margin is so wide it eats the pit, fall back to a normal
	# floor — the room becomes a regular room, no fatal build error.
	if inner_x <= 0.5 or inner_z <= 0.5:
		FloorBuilder.build_piece_floor(ctx, center, rd.size.x, rd.size.y)
		return

	if margin > 0.0:
		# Perimeter floor strips — the player's landing pads next to each
		# opening. North/south strips run the full room width; east/west
		# strips fill only the inner Z band so they don't overlap the corners.
		FloorBuilder.build_exact_floor(ctx,
			center + Vector3(0.0, 0.0, -hz + margin * 0.5),
			rd.size.x, margin)
		FloorBuilder.build_exact_floor(ctx,
			center + Vector3(0.0, 0.0,  hz - margin * 0.5),
			rd.size.x, margin)
		FloorBuilder.build_exact_floor(ctx,
			center + Vector3(-hx + margin * 0.5, 0.0, 0.0),
			margin, inner_z)
		FloorBuilder.build_exact_floor(ctx,
			center + Vector3( hx - margin * 0.5, 0.0, 0.0),
			margin, inner_z)

		# Raised lip on each strip's inner edge so the pit boundary reads
		# clearly — same trim height as corridor pits.
		var lip := FloorBuilder.PIT_TRIM_H
		WallBuilder.create_trim_box(ctx,
			center + Vector3(0.0, lip * 0.5, -inner_z * 0.5),
			rd.size.x, lip, thick, ctx.wall_material_alt)
		WallBuilder.create_trim_box(ctx,
			center + Vector3(0.0, lip * 0.5,  inner_z * 0.5),
			rd.size.x, lip, thick, ctx.wall_material_alt)
		WallBuilder.create_trim_box(ctx,
			center + Vector3(-inner_x * 0.5, lip * 0.5, 0.0),
			thick, lip, inner_z, ctx.wall_material_alt)
		WallBuilder.create_trim_box(ctx,
			center + Vector3( inner_x * 0.5, lip * 0.5, 0.0),
			thick, lip, inner_z, ctx.wall_material_alt)

	var kind: Kind = Kind.OOZE
	if rd.bottomless_pit:
		kind = Kind.BOTTOMLESS
	elif rd.spike_pit:
		kind = Kind.SPIKES
	build_pit_shaft(ctx, center, inner_x, inner_z, kind)

	for p in rd.pillars:
		_build_pillar(ctx, center + Vector3(p.x, 0.0, p.y), rd.pillar_size)
	# Spike + bottomless pits have no ambient floor light (ooze provides its
	# own glow) — without a marker on each pillar the player can't read the
	# jump path in the dark. Amber emergency light reads as warning lighting
	# and keeps the threatening tone.
	if kind != Kind.OOZE:
		for p in rd.pillars:
			_build_pillar_marker_light(ctx, center + Vector3(p.x, 0.0, p.y))
	_create_pit_jump_links(ctx, center, rd)


# Maximum centre-to-centre pillar distance an enemy can jump — covers a
# 3m surface gap on 1.5m pillars. Beyond this we don't link, and the enemy
# treats the gap as impassable. Keep loosely synced with prototype_enemy
# JUMP_MAX_DISTANCE so any pair we link is actually reachable in flight.
const JUMP_LINK_MAX_DIST := 4.6


# Drops a NavigationLink3D between every pair of pillars within jump range
# (and between rim openings and outermost pillars when the rim sits within
# range). Without these, NavigationServer3D treats each pillar top as an
# isolated walkable island and can't path between them — enemies stop at
# the pit edge or fall in.
static func _create_pit_jump_links(ctx: LevelBuildContext, center: Vector3, rd: RoomDef) -> void:
	if rd.pillars.is_empty():
		return
	var positions: Array[Vector3] = []
	for p in rd.pillars:
		positions.append(center + Vector3(p.x, 0.0, p.y))
	for i in positions.size():
		for j in range(i + 1, positions.size()):
			var a := positions[i]
			var b := positions[j]
			if a.distance_to(b) > JUMP_LINK_MAX_DIST:
				continue
			var link := NavigationLink3D.new()
			link.start_position = a
			link.end_position = b
			link.bidirectional = true
			# Heavy penalty so the navmesh strongly prefers walking when a
			# walking path exists (e.g. flush rim → outer pillar). Without
			# this, agents pick the link for any pillar pair within range
			# — even when adjacent surfaces are step-up reachable — and end
			# up jumping every couple of seconds across an entire pit room.
			link.travel_cost = 8.0
			ctx.root.add_child(link)


static func _create_pit_wall(ctx: LevelBuildContext, pos: Vector3, sx: float, sy: float, sz: float, mat: Material = null) -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = BoxMesh.new()
	(mesh_inst.mesh as BoxMesh).size = Vector3(sx, sy, sz)
	var wall_mat := mat if mat != null else ctx.wall_material
	if wall_mat != null:
		mesh_inst.material_override = wall_mat
	mesh_inst.position = pos
	ctx.root.add_child(mesh_inst)
	mesh_inst.add_to_group(&"structures")


static func _build_pit_floor_ooze(ctx: LevelBuildContext, center: Vector3, inner_x: float, inner_z: float, depth: float) -> void:
	var t := ctx.theme
	# Glowing ooze surface at the bottom of the pit.
	var ooze_y := -depth + 0.02
	var ooze_mat := StandardMaterial3D.new()
	ooze_mat.albedo_color = t.pit_ooze_color
	ooze_mat.emission_enabled = true
	ooze_mat.emission = t.pit_ooze_color
	ooze_mat.emission_energy_multiplier = t.pit_ooze_energy
	ooze_mat.metallic = 0.0
	ooze_mat.roughness = 0.2

	var ooze_mesh := PlaneMesh.new()
	ooze_mesh.size = Vector2(inner_x, inner_z)
	ooze_mesh.material = ooze_mat

	var ooze_inst := MeshInstance3D.new()
	ooze_inst.name = &"PitOoze"
	ooze_inst.mesh = ooze_mesh
	ooze_inst.position = center + Vector3(0.0, ooze_y, 0.0)
	ctx.root.add_child(ooze_inst)
	ooze_inst.add_to_group(&"structures")
	# LoS-cull the emissive surface so it doesn't bleed through walls. The
	# ooze light is already dimmed by ProximityLighting; this hides the mesh
	# itself so the pit reads as fully dark from outside the room.
	ooze_inst.add_to_group(&"static_glows")

	# Ooze light — casts a glow upward from the pit.
	var ooze_light := OmniLight3D.new()
	ooze_light.light_color = t.pit_ooze_color
	ooze_light.light_energy = t.pit_ooze_energy * 0.6
	ooze_light.omni_range = depth + 2.0
	ooze_light.omni_attenuation = 1.8
	ooze_light.shadow_enabled = false
	ooze_light.light_volumetric_fog_energy = 0.0
	ooze_light.position = center + Vector3(0.0, ooze_y + 0.5, 0.0)
	ctx.root.add_child(ooze_light)


# Spike-pit floor: dark stone slab with a deterministic grid of pyramidal
# spikes pointing up. Visual only — the kill volume sits at y=-10 regardless
# of geometry. A dim amber light below the spike tips silhouettes the spikes
# and lets the room read at all without making the pit feel "lit".
static func _build_pit_floor_spikes(ctx: LevelBuildContext, center: Vector3, inner_x: float, inner_z: float, depth: float) -> void:
	var floor_y := -depth + 0.02
	# Dark stone slab — slightly bluish gray so it doesn't read as pure black
	# under the proximity-dim baseline (pure black would clip to invisible).
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.07, 0.075, 0.085, 1.0)
	floor_mat.metallic = 0.1
	floor_mat.roughness = 0.85

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(inner_x, inner_z)
	floor_mesh.material = floor_mat

	var floor_inst := MeshInstance3D.new()
	floor_inst.name = &"PitFloor"
	floor_inst.mesh = floor_mesh
	floor_inst.position = center + Vector3(0.0, floor_y, 0.0)
	ctx.root.add_child(floor_inst)
	floor_inst.add_to_group(&"structures")

	# Spike grid — combine all spikes into one mesh so the pit costs one draw
	# call regardless of count.
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = Color(0.12, 0.13, 0.14, 1.0)
	spike_mat.metallic = 0.7
	spike_mat.roughness = 0.45

	# Spike spec: ~6:1 aspect ratio so they read as sharp impalement spikes
	# rather than pyramid blocks. Tight spacing forms a continuous carpet of
	# tips so missing a jump can't land between two stubby cones.
	var spacing := 0.65
	var base := 0.18
	var height_min := 1.0
	var height_max := 1.5
	var pad := spacing * 0.5
	var usable_x := maxf(0.0, inner_x - pad * 2.0)
	var usable_z := maxf(0.0, inner_z - pad * 2.0)
	var nx := int(usable_x / spacing)
	var nz := int(usable_z / spacing)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Deterministic jitter keyed off pit centre so re-entering the room
	# doesn't shuffle spikes between visits.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(center.x * 1000.0) ^ int(center.z * 1000.0) ^ 0xC0FFEE
	for ix in nx + 1:
		for iz in nz + 1:
			var gx := -usable_x * 0.5 + float(ix) * spacing
			var gz := -usable_z * 0.5 + float(iz) * spacing
			gx += rng.randf_range(-0.08, 0.08)
			gz += rng.randf_range(-0.08, 0.08)
			var h := rng.randf_range(height_min, height_max)
			_emit_spike(st, Vector3(gx, 0.0, gz), base, h)
	st.generate_normals()
	var spike_mesh := st.commit()

	var spike_inst := MeshInstance3D.new()
	spike_inst.name = &"PitSpikes"
	spike_inst.mesh = spike_mesh
	spike_inst.material_override = spike_mat
	spike_inst.position = center + Vector3(0.0, floor_y, 0.0)
	ctx.root.add_child(spike_inst)
	spike_inst.add_to_group(&"structures")

	# Amber rim-light at the pit floor — uplight strong enough to silhouette
	# the spikes and reach the floor lip above so the room reads at all. Steep
	# attenuation keeps it concentrated as a pit glow rather than spilling
	# out to feel like ambient room light.
	var rim := OmniLight3D.new()
	rim.light_color = Color(1.0, 0.55, 0.25, 1.0)
	rim.light_energy = 1.4
	rim.omni_range = depth + 4.0
	rim.omni_attenuation = 1.8
	rim.shadow_enabled = false
	rim.light_volumetric_fog_energy = 0.0
	rim.position = center + Vector3(0.0, floor_y + 0.4, 0.0)
	ctx.root.add_child(rim)


# Append a 4-sided pyramid (4 triangle side faces, no base — the base sits
# flush against the pit floor and isn't visible) to the SurfaceTool. Vertex
# order on each face is (next_corner, prev_corner, apex) so generate_normals()
# gives an outward normal — light catches the slopes, not the cavity inside.
static func _emit_spike(st: SurfaceTool, origin: Vector3, base_size: float, height: float) -> void:
	var h := base_size * 0.5
	var apex := origin + Vector3(0.0, height, 0.0)
	var c0 := origin + Vector3(-h, 0.0, -h)
	var c1 := origin + Vector3( h, 0.0, -h)
	var c2 := origin + Vector3( h, 0.0,  h)
	var c3 := origin + Vector3(-h, 0.0,  h)
	st.add_vertex(c1); st.add_vertex(c0); st.add_vertex(apex)
	st.add_vertex(c2); st.add_vertex(c1); st.add_vertex(apex)
	st.add_vertex(c3); st.add_vertex(c2); st.add_vertex(apex)
	st.add_vertex(c0); st.add_vertex(c3); st.add_vertex(apex)


# Pillar = static box rising from just above the pit ooze to floor level.
# Player can stand on top; collides as a wall on the sides. Top sits flush at
# y=0 so movement onto/off the pillar is seamless with the perimeter strips.
static func _build_pillar(ctx: LevelBuildContext, top_xz_center: Vector3, size: Vector2) -> void:
	var t := ctx.theme
	var clearance := 0.5  # bottom clearance so the pillar doesn't pierce the ooze surface
	var height := t.pit_depth - clearance
	if height <= 0.1:
		return

	var body := StaticBody3D.new()
	body.name = &"Pillar"
	body.input_ray_pickable = false
	body.transform.origin = Vector3(top_xz_center.x, -height * 0.5, top_xz_center.z)

	var col := CollisionShape3D.new()
	col.shape = BoxShape3D.new()
	(col.shape as BoxShape3D).size = Vector3(size.x, height, size.y)
	body.add_child(col)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = BoxMesh.new()
	(mesh_inst.mesh as BoxMesh).size = Vector3(size.x, height, size.y)
	# Sink the visual mesh below the corridor floor's bias so the corridor
	# floor wins where its FLOOR_OVERLAP strip enters a pit room and clips
	# the outer pillar's top. Collision stays unbiased.
	mesh_inst.position.y = PILLAR_TOP_Y_BIAS
	# Use floor material — pillars are walked-on platforms and the floor
	# shader is tuned for top-down viewing (wall shaders blow out under
	# overhead fluorescents because they're tuned for vertical surfaces
	# in indirect light).
	if ctx.floor_material != null:
		mesh_inst.material_override = ctx.floor_material
	body.add_child(mesh_inst)

	ctx.root.add_child(body)
	body.add_to_group(&"structures")
	body.add_to_group(&"minimap_walkable")


# Ceiling-mounted spotlight pointing straight down on each pillar. Reads as
# an interrogation lamp / emergency drop-light and silhouettes the spikes
# around the pillar's base, giving a clear visual anchor for each jump
# target without flooding the room with ambient light.
static func _build_pillar_marker_light(ctx: LevelBuildContext, top_xz_center: Vector3) -> void:
	var ceiling_y := ctx.theme.wall_height - 0.3
	var light := SpotLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.30, 1.0)
	light.light_energy = 1.6
	light.spot_range = ceiling_y + 1.0
	light.spot_angle = 28.0
	light.spot_angle_attenuation = 0.6
	light.spot_attenuation = 1.4
	light.shadow_enabled = false
	light.light_volumetric_fog_energy = 0.0
	light.position = Vector3(top_xz_center.x, ceiling_y, top_xz_center.z)
	light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	ctx.root.add_child(light)
