class_name ItemVisuals
extends RefCounted

# Builds the procedural geometry that represents an item in 3D pickup form.
# `build(item)` returns a Node3D with one or more MeshInstance3D children
# composed from primitive meshes + StandardMaterial3D presets, centered roughly
# at the local origin so it sits cleanly when parented under the pickup's
# Visual/Object node. The per-type branch is the swap point for authored
# Blender meshes later — `build()`'s signature stays the same.

static func build(item: Item) -> Node3D:
	var root := Node3D.new()
	if item == null:
		_build_fallback(root)
		return root
	match item.main_type:
		"1H Weapon":   _build_sword(root, false)
		"2H Weapon":   _build_sword(root, true)
		"Offhand":     _build_shield(root)
		"Head Armor":  _build_helmet(root)
		"Chest Armor": _build_chest(root)
		"Gloves":      _build_gloves(root)
		"Boots":       _build_boots(root)
		"Belt":        _build_belt(root)
		"Mainboard":   _build_mainboard(root)
		"Backpack":    _build_backpack(root)
		"Recon":       _build_optics(root)
		_:             _build_fallback(root)
	return root

# ── Materials ────────────────────────────────────────────────────────────────

static func _mat_steel() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.80, 0.83, 0.88)
	m.metallic = 0.95
	m.roughness = 0.18
	return m

static func _mat_dark_steel() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.42, 0.46, 0.52)
	m.metallic = 0.90
	m.roughness = 0.40
	return m

static func _mat_leather() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.28, 0.18, 0.12)
	m.metallic = 0.0
	m.roughness = 0.85
	return m

static func _mat_plate() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.50, 0.55, 0.60)
	m.metallic = 0.85
	m.roughness = 0.45
	return m

static func _mat_fabric() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.40, 0.30, 0.24)
	m.metallic = 0.0
	m.roughness = 0.95
	return m

static func _mat_pcb() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.08, 0.28, 0.15)
	m.metallic = 0.30
	m.roughness = 0.55
	m.emission_enabled = true
	m.emission = Color(0.25, 0.95, 0.55)
	m.emission_energy_multiplier = 0.6
	return m

static func _mat_pcb_solder() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.75, 0.40)
	m.metallic = 0.85
	m.roughness = 0.35
	return m

static func _mat_lens() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.65, 0.85)
	m.metallic = 0.10
	m.roughness = 0.20
	m.emission_enabled = true
	m.emission = Color(0.40, 0.90, 1.0)
	m.emission_energy_multiplier = 1.4
	return m

# ── Helpers ──────────────────────────────────────────────────────────────────

static func _make_mi(mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	mi.rotation = rot
	mi.scale = scale
	return mi

static func _box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m

static func _cyl(h: float, r: float, segments: int = 16) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.height = h
	m.top_radius = r
	m.bottom_radius = r
	m.radial_segments = segments
	m.rings = 1
	return m

static func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 20
	m.rings = 10
	return m

# ── Per-type builders. Each composes primitives so the centroid sits near y=0
# ── and the silhouette reads from the camera's high-angle viewpoint.

static func _build_sword(root: Node3D, two_handed: bool) -> void:
	var blade_h: float = 0.62 if two_handed else 0.45
	var grip_h: float = 0.20 if two_handed else 0.14
	var guard_w: float = 0.26 if two_handed else 0.20
	var blade_y := blade_h * 0.5 + 0.02
	var guard_y := 0.0
	var grip_y := -grip_h * 0.5 - 0.02
	var pommel_y := grip_y - grip_h * 0.5 - 0.02
	root.add_child(_make_mi(_box(Vector3(0.05, blade_h, 0.012)), _mat_steel(), Vector3(0, blade_y, 0)))
	root.add_child(_make_mi(_box(Vector3(guard_w, 0.04, 0.06)), _mat_steel(), Vector3(0, guard_y, 0)))
	root.add_child(_make_mi(_cyl(grip_h, 0.025, 12), _mat_leather(), Vector3(0, grip_y, 0)))
	root.add_child(_make_mi(_sphere(0.038), _mat_steel(), Vector3(0, pommel_y, 0)))

static func _build_shield(root: Node3D) -> void:
	# Round shield: short cylinder face + thin rim band.
	var face := _cyl(0.05, 0.30, 24)
	var face_mi := _make_mi(face, _mat_dark_steel(), Vector3.ZERO, Vector3(deg_to_rad(90), 0, 0))
	root.add_child(face_mi)
	var rim := _cyl(0.07, 0.32, 24)
	var rim_mi := _make_mi(rim, _mat_steel(), Vector3.ZERO, Vector3(deg_to_rad(90), 0, 0))
	rim_mi.scale = Vector3(1.0, 1.0, 0.6)
	root.add_child(rim_mi)
	# Boss in the center.
	root.add_child(_make_mi(_sphere(0.07), _mat_steel(), Vector3(0, 0, 0.04)))

static func _build_helmet(root: Node3D) -> void:
	# Half-sphere dome + visor slit.
	var dome := SphereMesh.new()
	dome.radius = 0.22
	dome.height = 0.30
	dome.radial_segments = 20
	dome.rings = 10
	dome.is_hemisphere = true
	root.add_child(_make_mi(dome, _mat_plate(), Vector3(0, 0.02, 0)))
	# Brim / visor.
	root.add_child(_make_mi(_box(Vector3(0.46, 0.04, 0.10)), _mat_dark_steel(), Vector3(0, 0.0, 0.18)))
	root.add_child(_make_mi(_box(Vector3(0.32, 0.04, 0.04)), _mat_dark_steel(), Vector3(0, 0.06, 0.22)))

static func _build_chest(root: Node3D) -> void:
	# Cuirass: tapered body box + shoulder pauldrons.
	var body := _make_mi(_box(Vector3(0.40, 0.50, 0.24)), _mat_plate(), Vector3.ZERO)
	root.add_child(body)
	root.add_child(_make_mi(_sphere(0.10), _mat_plate(), Vector3(-0.22, 0.20, 0)))
	root.add_child(_make_mi(_sphere(0.10), _mat_plate(), Vector3(0.22, 0.20, 0)))
	# Belt seam.
	root.add_child(_make_mi(_box(Vector3(0.42, 0.05, 0.26)), _mat_leather(), Vector3(0, -0.18, 0)))

static func _build_gloves(root: Node3D) -> void:
	# Pair of gauntlets side by side.
	for x in [-0.13, 0.13]:
		root.add_child(_make_mi(_box(Vector3(0.16, 0.20, 0.16)), _mat_plate(), Vector3(x, 0, 0)))
		root.add_child(_make_mi(_box(Vector3(0.18, 0.06, 0.18)), _mat_dark_steel(), Vector3(x, 0.10, 0)))

static func _build_boots(root: Node3D) -> void:
	# Pair of boots, toe forward.
	for x in [-0.10, 0.10]:
		root.add_child(_make_mi(_box(Vector3(0.14, 0.22, 0.20)), _mat_leather(), Vector3(x, 0, 0)))
		root.add_child(_make_mi(_box(Vector3(0.16, 0.07, 0.32)), _mat_leather(), Vector3(x, -0.08, 0.06)))
		# Buckle.
		root.add_child(_make_mi(_box(Vector3(0.06, 0.04, 0.04)), _mat_pcb_solder(), Vector3(x, 0.02, 0.10)))

static func _build_belt(root: Node3D) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.20
	ring.outer_radius = 0.26
	ring.rings = 32
	ring.ring_segments = 10
	root.add_child(_make_mi(ring, _mat_leather(), Vector3.ZERO, Vector3(deg_to_rad(90), 0, 0)))
	# Buckle.
	root.add_child(_make_mi(_box(Vector3(0.10, 0.08, 0.04)), _mat_pcb_solder(), Vector3(0, 0, 0.26)))

static func _build_mainboard(root: Node3D) -> void:
	# PCB plate + a few solder pads + a chip.
	root.add_child(_make_mi(_box(Vector3(0.42, 0.04, 0.42)), _mat_pcb(), Vector3.ZERO))
	root.add_child(_make_mi(_box(Vector3(0.18, 0.05, 0.10)), _mat_dark_steel(), Vector3(0, 0.04, 0)))
	for px in [-0.15, -0.05, 0.05, 0.15]:
		for pz in [-0.18, 0.18]:
			root.add_child(_make_mi(_cyl(0.02, 0.012, 8), _mat_pcb_solder(), Vector3(px, 0.03, pz)))

static func _build_backpack(root: Node3D) -> void:
	# Main sack + flap + strap.
	root.add_child(_make_mi(_box(Vector3(0.42, 0.50, 0.26)), _mat_fabric(), Vector3.ZERO))
	root.add_child(_make_mi(_box(Vector3(0.40, 0.18, 0.04)), _mat_leather(), Vector3(0, 0.18, 0.15)))
	root.add_child(_make_mi(_box(Vector3(0.06, 0.52, 0.04)), _mat_leather(), Vector3(0.16, 0, -0.14)))
	root.add_child(_make_mi(_box(Vector3(0.06, 0.52, 0.04)), _mat_leather(), Vector3(-0.16, 0, -0.14)))

static func _build_optics(root: Node3D) -> void:
	# Lens housing + glowing element.
	root.add_child(_make_mi(_cyl(0.20, 0.16, 20), _mat_dark_steel(), Vector3.ZERO, Vector3(deg_to_rad(90), 0, 0)))
	root.add_child(_make_mi(_sphere(0.13), _mat_lens(), Vector3.ZERO))
	root.add_child(_make_mi(_cyl(0.06, 0.18, 20), _mat_steel(), Vector3(0, 0, 0.10), Vector3(deg_to_rad(90), 0, 0)))
	root.add_child(_make_mi(_cyl(0.06, 0.18, 20), _mat_steel(), Vector3(0, 0, -0.10), Vector3(deg_to_rad(90), 0, 0)))

static func _build_fallback(root: Node3D) -> void:
	root.add_child(_make_mi(_box(Vector3(0.30, 0.30, 0.30)), _mat_dark_steel(), Vector3.ZERO))
