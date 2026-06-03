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
// Scorch tint multiplied into the sampled floor color. Much darker
// burnt-charred tone now (was 0.75/0.45/0.25 "burnt sienna") so the
// pit reads as scorched/burned, not just lightly tinted.
uniform vec3 tint : source_color = vec3(0.22, 0.13, 0.07);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.90;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float fade_radius : hint_range(0.5, 100.0) = 20.0;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.45;
uniform float vignette_end : hint_range(0.0, 1.0) = 0.85;
// Roughness boost — matte against polished floor.
uniform float roughness_boost : hint_range(0.0, 1.0) = 0.55;
// Normal-map exaggeration. > 1 amplifies the crater's sculpted bump
// for stronger highlights/shadows under world lighting.
uniform float normal_strength : hint_range(0.5, 6.0) = 4.5;
// Hot-rim emission: scorching glow at the slope between center and
// edge. Reads as "the impact JUST happened — the floor is still
// glowing where the hammer struck." Tied to the lifetime fade so it
// dims as the crater ages.
uniform vec3 rim_emission_color : source_color = vec3(1.4, 0.45, 0.10);
uniform float rim_emission_strength : hint_range(0.0, 5.0) = 1.8;
// Screen-space refraction — distorts the floor texture sample by
// the crater's surface normal. Sells real depth by making the floor
// tiles visibly bend through the rim/depression slopes.
uniform float distort_strength : hint_range(0.0, 0.30) = 0.14;
// Center darkening — multiplies ALBEDO down inside the crater
// interior. 0.85 makes the pit read almost-black against the floor.
uniform float center_darken : hint_range(0.0, 1.0) = 0.85;

// Model-local vertex position carried into fragment — needed because
// the built-in VERTEX in fragment() is in VIEW space, not model space.
// See godot4-shader-gotchas memory for the full trap list.
varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	vec3 nrm_raw = texture(normal_tex, UV).xyz;
	float rough = texture(roughness_tex, UV).r;

	// Screen-space refraction — offset the floor-color sample by the
	// crater's surface slope, so the floor visibly bends through the
	// rim/depression. nrm_raw is in [0,1] tangent space; decoding to
	// [-1,1] gives a signed XY direction we can shove SCREEN_UV by.
	// Reading screen_texture at the offset position pulls the floor
	// pixel that "should" be visible at that slope, which the eye
	// parses as a real indentation. Outside the alpha-fade edge the
	// distortion fades to zero so the surrounding floor stays
	// undisturbed.
	vec2 nrm_decoded = nrm_raw.xy * 2.0 - 1.0;
	float r = length(v_local_pos.xz) / max(fade_radius, 0.001);
	float mask = 1.0 - smoothstep(vignette_start, vignette_end, r);
	vec2 distort_uv = nrm_decoded * distort_strength * mask;
	vec3 floor_color = textureLod(screen_texture, SCREEN_UV + distort_uv, 0.0).rgb;

	// Mix the (refracted) floor toward the scorch tint, then apply a
	// radial darkening that's strongest at the centre and fades to no
	// effect by the rim. The center dimming gives the depression a
	// pit-shadow look that the eye reads as depth — independent of
	// the normal-map shading.
	vec3 albedo = mix(floor_color, floor_color * tint, tint_mix);
	float centre_factor = 1.0 - smoothstep(0.0, vignette_start, r);
	albedo *= mix(1.0, 1.0 - center_darken, centre_factor);

	ALBEDO = albedo;
	NORMAL_MAP = nrm_raw;
	// NORMAL_MAP_DEPTH > 1 exaggerates the crater's sculpted bump —
	// the rim and depression cast stronger shadows and catch more
	// light. Combined with the refraction above, the crater reads as
	// a real 3D depression instead of a flat decal.
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = clamp(rough + roughness_boost, 0.0, 1.0);
	METALLIC = 0.0;
	// Hot-rim emission band — peak between the dark center and the
	// fading perimeter, where the impact's "scorched edge" lives in
	// reference imagery. Falls off symmetrically on both sides so
	// it doesn't bleed into the center darken or past the vignette.
	float rim_lo = vignette_start * 0.55;
	float rim_hi = vignette_start;
	float rim_band = smoothstep(rim_lo, rim_hi, r)
		* (1.0 - smoothstep(rim_hi, vignette_end, r));
	EMISSION = rim_emission_color * rim_emission_strength * rim_band * fade;
	ALPHA = mask * fade;
}
