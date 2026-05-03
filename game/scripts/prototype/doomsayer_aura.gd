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

# Two-part aura visual. The visible mesh is intentionally SMALL and
# constant — a tight glowing core right at the player that reads as
# "radiating energy" rather than a contained bubble. The wide aura
# range (matching the skill's proc area) is communicated by the
# OmniLight3D's purple wash on world surfaces, which respects walls
# via shadow casting. Per-tier scaling drives intensity (energy feels
# stronger) and light range/energy (wash extends further), but the
# visible mesh radius stays small so it never reaches walls.
const SPHERE_RADIUS := 1.6  # constant — small enough to never bleed into walls
const INTENSITY_PER_TIER: Array[float] = [0.0, 1.4, 2.0, 2.8]
const LIGHT_ENERGY_PER_TIER: Array[float] = [0.0, 2.0, 3.5, 5.5]
# Light range matches the skill's per-tier aura radius so the visible
# wash on walls/floor exactly traces the proc-eligible area. Read from
# PrototypePlayer.DOOMSAYER_AURA_RADIUS_PER_TIER conceptually; values
# duplicated here to keep DoomsayerAura standalone.
const LIGHT_RANGE_PER_TIER: Array[float] = [0.0, 5.0, 7.0, 9.0]
const ALPHA_PER_TIER: Array[float] = [0.0, 0.9, 1.0, 1.0]
# Squash factor — the small core ellipsoid hugs the player at mid-body
# height. Y_OFFSET puts the centre at chest height so the radiating
# energy feels like it's coming from the player's torso.
const Y_SQUASH := 0.7
const Y_OFFSET := 1.0

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
		# Sphere stays at constant SPHERE_RADIUS across all tiers — the
		# visible body is the radiating core right at the player; the
		# wider aura presence is the OmniLight's wash that scales with
		# tier via light range.
		_sphere.scale = Vector3(SPHERE_RADIUS, SPHERE_RADIUS * Y_SQUASH, SPHERE_RADIUS) if on else Vector3.ONE
		_sphere.position = Vector3(0.0, Y_OFFSET, 0.0) if on else Vector3.ZERO
	if _material != null:
		_material.set_shader_parameter(&"fog_color", Color(COLOR.r, COLOR.g, COLOR.b, ALPHA_PER_TIER[_tier]))
		_material.set_shader_parameter(&"intensity", INTENSITY_PER_TIER[_tier])
	if _light != null:
		_light.visible = on
		_light.light_energy = LIGHT_ENERGY_PER_TIER[_tier]
		_light.omni_range = LIGHT_RANGE_PER_TIER[_tier]
