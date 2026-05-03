class_name DoomsayerAura
extends Node3D

# Visual aura for the Enculted Doomsayer perk — a swirling purple fog
# sphere around the player, paired with a shadow-casting purple OmniLight
# that washes nearby surfaces. PrototypePlayer creates one on _ready and
# parents it; tier updates come through set_tier() driven by
# PerkState.perks_changed.
#
# Implementation pairs two effects:
#   * SphereMesh + custom shader (game/shaders/doomsayer_fog.gdshader) —
#     provides the visible body of mist around the player. Uses 3D fbm
#     noise + silhouette fade for the soft fluffy-ball look.
#   * Shadow-casting OmniLight3D at the sphere centre — its purple wash
#     on nearby walls / floor is what actually communicates "the fog
#     stops at the wall." Lights respect walls naturally via shadow
#     casting; a depth-tested fog mesh alone can't, because the iso
#     camera can see the floor right past most walls (so the mesh
#     fragments aren't depth-clipped).
#
# Tier readout:
#   T0 — invisible (perk not active)
#   T1 — thin haze, dim purple light
#   T2 — visible cloud, brighter spill
#   T3 — heavy miasma, dramatic light radius

const FOG_SHADER: Shader = preload("res://shaders/doomsayer_fog.gdshader")
const COLOR := Color(0.78, 0.35, 0.85, 1.0)  # AMB stat color (purple)

# Per-tier visual scaling. T0 hides everything. Sphere radius matches
# the perk's effect range (DOOMSAYER_AURA_RADIUS_PER_TIER on the player)
# so the visible mist size = the actual proc-eligible area. The high
# core_softness in the shader (3.5+) means the visible mass concentrates
# in the inner ~40% of radius and fades to transparent at the silhouette,
# so a large geometric sphere doesn't read as a solid ball.
const INTENSITY_PER_TIER: Array[float] = [0.0, 0.7, 1.0, 1.3]
const RADIUS_PER_TIER: Array[float] = [0.0, 5.0, 7.0, 9.0]
const LIGHT_ENERGY_PER_TIER: Array[float] = [0.0, 1.6, 2.8, 4.5]
const LIGHT_RANGE_PER_TIER: Array[float] = [0.0, 5.0, 7.0, 9.0]
const ALPHA_PER_TIER: Array[float] = [0.0, 0.85, 1.0, 1.0]
# Squash factor — sphere Y scale is RADIUS * Y_SQUASH so the body
# becomes an ellipsoid hugging the floor instead of a tall ball. With
# the larger radii (up to 9m) we squash more aggressively so the top
# stays under the 4.5m walls (9 * 0.4 + 0.9 = 4.5).
const Y_SQUASH := 0.4
const Y_OFFSET := 0.9

var _tier: int = 0
var _sphere: MeshInstance3D
var _material: ShaderMaterial
var _light: OmniLight3D


func _ready() -> void:
	_build_sphere()
	_build_light()
	_apply_tier()


func _build_sphere() -> void:
	_sphere = MeshInstance3D.new()
	_sphere.name = &"FogSphere"
	_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Unit-radius sphere — tier scaling expands via the node's own scale
	# so we don't have to rebuild the mesh on every recompute. radial /
	# rings are deliberately modest because the shader does the visual
	# work; high mesh resolution wouldn't help.
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	_sphere.mesh = mesh
	_material = ShaderMaterial.new()
	_material.shader = FOG_SHADER
	_material.set_shader_parameter(&"fog_color", Color(COLOR.r, COLOR.g, COLOR.b, ALPHA_PER_TIER[0]))
	_material.set_shader_parameter(&"intensity", INTENSITY_PER_TIER[0])
	_sphere.material_override = _material
	# Sit low and wide — the sphere is squashed vertically (Y_SQUASH)
	# so fog hugs the floor like dry-ice spill instead of towering above
	# the player. The squash also helps with wall pokethrough: a flat
	# ellipsoid at knee height stays under most 2m wall tops, so the
	# camera doesn't see the fog "leaking" over walls. Position in
	# _apply_tier (depends on radius for floor offset).
	add_child(_sphere)


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = &"Spill"
	_light.light_color = COLOR
	_light.light_energy = LIGHT_ENERGY_PER_TIER[0]
	_light.omni_range = LIGHT_RANGE_PER_TIER[0]
	_light.omni_attenuation = 1.6
	# Shadows are the magic here: walls block the light, so the purple
	# wash on world surfaces naturally stops at obstacles. Without this
	# the fog would visibly extend through walls (the iso camera can
	# see floor past most walls, so per-fragment depth-test on the
	# sphere alone isn't enough). Cubemap shadow on a single light is
	# a real but acceptable cost — only Enculted/Ambition players pay.
	_light.shadow_enabled = true
	_light.shadow_blur = 1.5
	_light.light_volumetric_fog_energy = 0.0
	# Sits at the same Y as the fog ellipsoid centre so the lit volume
	# and the visible mist body share their core. Low enough that
	# walls cast meaningful shadows from this light, high enough that
	# the player's own model doesn't shadow-occlude the floor under
	# them (the player capsule is layer 2, but Light shadow casting
	# reads geometry, not collision — a too-low light still works).
	_light.position = Vector3(0.0, Y_OFFSET, 0.0)
	add_child(_light)


# Public API — PrototypePlayer calls this on perks_changed with the
# unlocked AMB tier (0..3). T0 hides everything; T1+ scales visibility.
func set_tier(t: int) -> void:
	var clamped := clampi(t, 0, 3)
	if clamped == _tier:
		return
	_tier = clamped
	_apply_tier()


func _apply_tier() -> void:
	var on := _tier > 0
	if _sphere != null:
		_sphere.visible = on
		var r: float = RADIUS_PER_TIER[_tier]
		_sphere.scale = Vector3(r, r * Y_SQUASH, r) if on else Vector3.ONE
		_sphere.position = Vector3(0.0, Y_OFFSET, 0.0) if on else Vector3.ZERO
	if _material != null:
		_material.set_shader_parameter(&"fog_color", Color(COLOR.r, COLOR.g, COLOR.b, ALPHA_PER_TIER[_tier]))
		_material.set_shader_parameter(&"intensity", INTENSITY_PER_TIER[_tier])
	if _light != null:
		_light.visible = on
		_light.light_energy = LIGHT_ENERGY_PER_TIER[_tier]
		_light.omni_range = LIGHT_RANGE_PER_TIER[_tier]
