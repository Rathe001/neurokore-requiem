// Hammer crater — floor-distortion variant.
//
// Earlier iterations textured the mesh with the source PBR albedo (an
// orange dry-hills colour map). Even with a radial vignette, the bright
// distinct colour read as a "sticker on the floor" rather than damage
// inflicted on the surface itself. This version drops the orange
// entirely: ALBEDO is sampled from the SCREEN_TEXTURE under the
// fragment, so the floor's own texture colour comes through the crater.
// The crater's NORMAL map and ROUGHNESS map are still applied on top,
// so the lighting computes against the distorted surface and you get
// proper highlights / shadows / bump — the floor texture appears
// indented and disturbed but the colour palette stays consistent with
// the surrounding ground.
//
// A subtle `tint` × `tint_mix` modulates the sampled floor toward a
// scorched darker shade so the crater still reads as damage, not just
// a normal-map decal.
//
// fade_radius is set per-spawn by PrototypeAttackIndicator.spawn_hammer_crater
// (= measured half-footprint of the mesh AABB after the inner glb
// transforms are accounted for). `fade` is the lifetime-tween driver
// (1 = full opacity → 0 = invisible).

shader_type spatial;
// depth_draw_never is required for SCREEN_TEXTURE sampling — if we wrote
// depth, the crater would clip itself out of the screen-texture pass
// (which only includes pre-transparent geometry) and we'd sample whatever
// was BEHIND the crater (skybox / dark void below the floor) instead of
// the floor pixel underneath.
render_mode blend_mix, depth_draw_never, cull_back;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D roughness_tex : hint_roughness_r, filter_linear_mipmap;
// Scorch tint multiplied into the sampled floor color. Warm
// burnt-sienna picks up contrast against the floor's cool palette.
uniform vec3 tint : source_color = vec3(0.75, 0.45, 0.25);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.55;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float fade_radius : hint_range(0.5, 100.0) = 20.0;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.45;
uniform float vignette_end : hint_range(0.0, 1.0) = 0.85;
// Roughness boost — matte against polished floor.
uniform float roughness_boost : hint_range(0.0, 1.0) = 0.45;
// Normal-map exaggeration. Default 1.0 = use the source asset's
// normal at native intensity. We push this above 1.0 so the
// crater's sculpted bump (rim, depression, debris) generates
// stronger highlights and shadows under world lighting — that's
// where the readability of the impact comes from. No emissive rim
// (the orange-ring iteration read as a separate VFX).
uniform float normal_strength : hint_range(0.5, 5.0) = 3.0;

// Model-local vertex position carried into fragment — needed because
// the built-in VERTEX in fragment() is in VIEW space, not model space.
// See godot4-shader-gotchas memory for the full trap list.
varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	vec3 floor_color = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	vec3 nrm = texture(normal_tex, UV).xyz;
	float rough = texture(roughness_tex, UV).r;

	// Local-space radial fade. Mesh origin = centre (Blender export
	// convention), so r = 0 at centre, r = 1 at fade_radius units out
	// in the XZ plane of the mesh's own coordinate frame.
	float r = length(v_local_pos.xz) / max(fade_radius, 0.001);
	float mask = 1.0 - smoothstep(vignette_start, vignette_end, r);

	// Mix the sampled floor toward the scorch tint. Output reads as
	// the floor's own palette warmed and dimmed by the impact, with
	// no separate VFX color layered on top.
	ALBEDO = mix(floor_color, floor_color * tint, tint_mix);
	NORMAL_MAP = nrm;
	// NORMAL_MAP_DEPTH > 1 exaggerates the crater's sculpted bump —
	// the rim and depression cast stronger shadows and catch more
	// light, so the impact silhouette is visible from the iso camera
	// even on dark floor. This replaces the emissive-rim approach,
	// which read as a separate orange ring rather than as the crater
	// itself.
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = clamp(rough + roughness_boost, 0.0, 1.0);
	METALLIC = 0.0;
	ALPHA = mask * fade;
}
