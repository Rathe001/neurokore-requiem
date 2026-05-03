class_name DoomsayerAura
extends Node3D

# Visual aura for the Enculted Doomsayer perk — a swirling purple fog
# disc emitted from the player's feet. PrototypePlayer creates one on
# _ready and parents it; tier updates come through set_tier() driven
# by PerkState.perks_changed.
#
# Implementation is a single PlaneMesh laid flat on the floor with a
# custom fbm-noise shader (game/shaders/doomsayer_fog.gdshader). The
# shader handles the rotating noise field, radial alpha falloff, and
# soft-particles depth fade so the disc clips cleanly against walls
# and step edges instead of painting through them.
#
# Tier readout:
#   T0 — invisible (perk not active)
#   T1 — thin haze + dim purple ambient light
#   T2 — visible cloud, brighter spill
#   T3 — heavy miasma, dramatic purple light radius
#
# Particles approach was scrapped 2026-05-03 because GPUParticles3D
# doesn't have a clean way to clip against world geometry — the fog
# was visibly extending through walls regardless of soft-particles
# tweaks. Shader-on-mesh hits the depth_sampler directly.

const FOG_SHADER: Shader = preload("res://shaders/doomsayer_fog.gdshader")
const COLOR := Color(0.78, 0.35, 0.85, 1.0)  # AMB stat color (purple)

# Per-tier visual scaling. Index 0 = "off." The shader's intensity
# uniform multiplies the whole density; mesh scale grows the disc
# radius; the OmniLight3D handles ambient color spill against nearby
# surfaces. All three should ramp together so the tier reads at a
# glance regardless of zone lighting.
const INTENSITY_PER_TIER: Array[float] = [0.0, 0.55, 1.0, 1.6]
const RADIUS_PER_TIER: Array[float] = [0.0, 4.0, 5.5, 7.0]
const LIGHT_ENERGY_PER_TIER: Array[float] = [0.0, 0.9, 1.7, 3.0]
const LIGHT_RANGE_PER_TIER: Array[float] = [0.0, 5.5, 7.5, 10.0]
const ALPHA_PER_TIER: Array[float] = [0.0, 0.65, 0.85, 1.0]

# Disc sits a hair above the floor so depth-fade has room to work
# without z-fighting the floor mesh itself.
const FOOT_OFFSET_Y := 0.05

var _tier: int = 0
var _disc: MeshInstance3D
var _material: ShaderMaterial
var _light: OmniLight3D


func _ready() -> void:
	_build_disc()
	_build_light()
	_apply_tier()


func _build_disc() -> void:
	_disc = MeshInstance3D.new()
	_disc.name = &"FogDisc"
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Flat plane, default 2x2 m — tier scaling expands via the node's
	# own scale so we don't have to rebuild the mesh on every recompute.
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	# Subdivide so depth-fade interpolates smoothly across the disc
	# instead of being computed only at four corners.
	mesh.subdivide_width = 8
	mesh.subdivide_depth = 8
	_disc.mesh = mesh
	_material = ShaderMaterial.new()
	_material.shader = FOG_SHADER
	_material.set_shader_parameter(&"fog_color", Color(COLOR.r, COLOR.g, COLOR.b, ALPHA_PER_TIER[0]))
	_material.set_shader_parameter(&"intensity", INTENSITY_PER_TIER[0])
	_disc.material_override = _material
	_disc.position.y = FOOT_OFFSET_Y
	add_child(_disc)


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = &"Spill"
	_light.light_color = COLOR
	_light.light_energy = LIGHT_ENERGY_PER_TIER[0]
	_light.omni_range = LIGHT_RANGE_PER_TIER[0]
	_light.omni_attenuation = 2.0
	_light.shadow_enabled = false
	_light.light_volumetric_fog_energy = 0.0
	_light.position = Vector3(0.0, 1.2, 0.0)
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
	if _disc != null:
		_disc.visible = on
		# Scale the disc to the per-tier radius. Mesh is 2x2 default, so
		# scale = radius (radius units → 2*radius wide, but disc fades
		# from centre so the visible diameter ≈ radius * 2 anyway).
		var r: float = RADIUS_PER_TIER[_tier]
		_disc.scale = Vector3(r, 1.0, r) if on else Vector3.ONE
	if _material != null:
		_material.set_shader_parameter(&"fog_color", Color(COLOR.r, COLOR.g, COLOR.b, ALPHA_PER_TIER[_tier]))
		_material.set_shader_parameter(&"intensity", INTENSITY_PER_TIER[_tier])
	if _light != null:
		_light.visible = on
		_light.light_energy = LIGHT_ENERGY_PER_TIER[_tier]
		_light.omni_range = LIGHT_RANGE_PER_TIER[_tier]
