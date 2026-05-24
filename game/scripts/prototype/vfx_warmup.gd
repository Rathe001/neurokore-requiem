class_name VfxWarmup
extends RefCounted

# Combat-VFX shader pre-compiler.
#
# Godot 4 compiles spatial shaders LAZILY on the rendering thread the
# first time a material using them is drawn. For combat VFX (blade
# slash, hammer crater, hammer impact, projectiles, etc.) that meant
# the FIRST swing / shot of a session stalled a frame while its shader
# compiled. User-perceived as "LMB feels laggy the first time."
#
# This module instantiates a tiny offscreen MeshInstance3D for each
# combat shader, drives one render pass, and frees the lot. The shader
# variants compile during the loading-screen window (PrototypeRoot._ready
# calls us before hide_loading), so the cost lands invisibly and the
# first in-combat use is hitch-free.
#
# Per-level cost: a few render slots for one frame, then garbage. Godot's
# shader cache persists across level loads so the second level's warmup
# is a no-op on the GPU side; we still build the quads but the cached
# binary is reused.
#
# Audio is already warmed at autoload init (WeaponSounds._ready calls
# _ensure_loaded synchronously). Particle scenes (FLIPBOOK_EXPLOSION_SCENE,
# PROJECTILE_SCENE) are skipped here — their _ready() side-effects
# (audio, tweens, timers) aren't safe to invoke off-stage. If hitches
# remain on first projectile, we'd add explicit material warming for
# those rather than scene instantiation.

# Spatial shaders that show up in combat. Includes the new
# hammer_crater shader plus everything player_combat / attack_indicator
# / projectile / cast-bar uses. UI-overlay shaders (chromatic_aberration,
# death_glitch, low_hp_warning, vignette, retro_filter) and structural
# scene shaders (displacement_floor, ground_grid, proximity_fade,
# outline_compositor, tech_door) are skipped — they're either always
# on-screen at level boot (so they compile naturally during the boot
# render) or they're CanvasItem shaders that compile under different
# code paths.
const _COMBAT_SHADERS: Array[String] = [
	"res://scripts/prototype/hammer_crater.gdshader",
	"res://scripts/prototype/hammer_impact.gdshader",
	"res://scripts/prototype/blade_slash.gdshader",
	"res://scripts/prototype/shockwave_bubble.gdshader",
	"res://scripts/prototype/lightning_arc.gdshader",
	"res://scripts/prototype/airstrike_marker.gdshader",
	"res://scripts/prototype/jet_flame.gdshader",
	"res://scripts/prototype/health_bar.gdshader",
	"res://scripts/prototype/tactical_overlay.gdshader",
	"res://scripts/prototype/puddle.gdshader",
	# Inverted-hull silhouette outline. Applied as material_overlay
	# whenever the player hovers an enemy or stands near an interactable
	# — every hover after the first is hitch-free thanks to this.
	"res://scripts/prototype/outline_hull.gdshader",
]

# Anchor 500m below the playable map so the warmup quads can't possibly
# end up on-camera even with the iso angle. Tiny mesh size (1cm²) keeps
# the per-draw cost negligible.
const _WARMUP_Y_OFFSET: float = -500.0
const _WARMUP_QUAD_SIZE: float = 0.01


## Build one ShaderMaterial per combat shader, render it once below the
## map, then free everything. Awaits two process frames so the GPU has
## a chance to compile + flush before we tear down. Safe to call from
## any Node — the warmup root parents under `parent`.
static func warmup(parent: Node) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var anchor := Node3D.new()
	anchor.name = "_VfxWarmup"
	anchor.position = Vector3(0.0, _WARMUP_Y_OFFSET, 0.0)
	parent.add_child(anchor)
	for path in _COMBAT_SHADERS:
		if not ResourceLoader.exists(path):
			continue
		var sh := load(path) as Shader
		if sh == null:
			continue
		# Per-instance QuadMesh — each gets its own ShaderMaterial set
		# on the mesh's `material` property (PrimitiveMesh.material).
		# Sharing the QuadMesh and routing through `material_override`
		# left surface_get_material(0) null on the shared resource, which
		# was triggering RenderingServer queries on a null Material RID
		# during shadow / dependency / animated-uniform passes:
		#   material_casts_shadows: Parameter "material" is null.
		#   material_is_animated: Parameter "material" is null.
		#   material_get_instance_shader_parameters: Parameter "material" is null.
		#   material_update_dependency: Parameter "material" is null.
		# Setting the material on the PrimitiveMesh directly gives the
		# surface a concrete Material so those queries land cleanly.
		var quad := QuadMesh.new()
		quad.size = Vector2(_WARMUP_QUAD_SIZE, _WARMUP_QUAD_SIZE)
		var mat := ShaderMaterial.new()
		mat.shader = sh
		quad.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		# cast_shadow off — no point burning shadow-atlas slots on a 1cm
		# quad below the map.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		anchor.add_child(mi)

	# Pre-compile the StandardMaterial3D variants the game spawns from
	# code at runtime. Each unique combination of shading_mode +
	# transparency + emission_enabled is its own shader variant; first
	# use compiles on the renderer thread and stalls a frame. Listing
	# the ones the level-up VFX, ring overlays, and energy pulses use
	# so those first-time spawns are hitch-free.
	# Format: each dict spawns a StandardMaterial3D with the flags +
	# attaches it to a tiny QuadMesh under the anchor.
	var standard_variants: Array[Dictionary] = [
		# Level-up VFX ring (prototype_player._play_levelup_vfx): unshaded
		# + alpha transparency + emission. The biggest single cause of
		# the "lag spike when I level up" report — first level-up of
		# each session compiled this variant.
		{&"unshaded": true, &"transparent": true, &"emission": true},
		# Energy pulse (PrototypeAttackIndicator.spawn_energy_pulse) —
		# same flag set plus blend_mode=ADD. Listed separately so we
		# compile both transparency-blend modes.
		{&"unshaded": true, &"transparent": true, &"emission": true, &"blend_add": true},
		# Beam glow / muzzle flare overlay variants — unshaded +
		# transparent without emission. Cheap to add; covers any UI/VFX
		# that doesn't need emission.
		{&"unshaded": true, &"transparent": true, &"emission": false},
	]
	for spec in standard_variants:
		var sm := StandardMaterial3D.new()
		if spec.get(&"unshaded", false):
			sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if spec.get(&"transparent", false):
			sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if spec.get(&"emission", false):
			sm.emission_enabled = true
			sm.emission = Color(1, 0.85, 0.4)
			sm.emission_energy_multiplier = 1.0
		if spec.get(&"blend_add", false):
			sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		sm.albedo_color = Color(1, 1, 1, 0.5)
		var quad2 := QuadMesh.new()
		quad2.size = Vector2(_WARMUP_QUAD_SIZE, _WARMUP_QUAD_SIZE)
		quad2.material = sm
		var mi2 := MeshInstance3D.new()
		mi2.mesh = quad2
		mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		anchor.add_child(mi2)

	# Two process frames: one for the render server to see the new
	# MeshInstance3Ds and queue their shaders for compile, one for the
	# compile to actually flush. Empirically this catches everything;
	# if we ever see a stutter that warmup didn't prevent, bump to 3.
	await parent.get_tree().process_frame
	await parent.get_tree().process_frame
	if is_instance_valid(anchor):
		anchor.queue_free()
