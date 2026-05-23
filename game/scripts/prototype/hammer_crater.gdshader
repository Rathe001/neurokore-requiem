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
// burnt-sienna — picks up contrast against the cyberpunk floor's
// cool blue-grey palette. Going darker than the floor (the previous
// near-black attempt) made the crater disappear; the floor is
// already dark, so dark scorch = invisible. Warm tones cut through.
uniform vec3 tint : source_color = vec3(0.85, 0.55, 0.32);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.6;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float fade_radius : hint_range(0.5, 100.0) = 20.0;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.45;
uniform float vignette_end : hint_range(0.0, 1.0) = 0.85;
// Roughness boost — matte against polished floor; the specular
// contrast at the edge also helps the silhouette read.
uniform float roughness_boost : hint_range(0.0, 1.0) = 0.45;
// Soft warm edge highlight. Kept low so it reads as a subtle hot
// outline on the scorch (not the bright orange RING that the
// previous tune accidentally created — which looked identical to
// the spawn_hammer_impact shockwave and read as "no crater here,
// just the old VFX"). rim_width controls the falloff radius.
uniform vec3 rim_color : source_color = vec3(1.0, 0.55, 0.20);
uniform float rim_intensity : hint_range(0.0, 6.0) = 0.7;
uniform float rim_width : hint_range(0.02, 0.40) = 0.22;

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

	// Mix the sampled floor toward the scorch tint. Output is darker /
	// warmer than surrounding floor but unmistakably still the floor's
	// own texture and palette.
	ALBEDO = mix(floor_color, floor_color * tint, tint_mix);
	NORMAL_MAP = nrm;
	ROUGHNESS = clamp(rough + roughness_boost, 0.0, 1.0);
	METALLIC = 0.0;
	ALPHA = mask * fade;

	// Hot rim band: peaks just inside the alpha-fade edge, falls off
	// on both sides. Picked up by the env's bloom (intensity > 1.0)
	// for a glow halo. Couples to `fade` so the heat dies down as
	// the crater ages.
	float rim_centre = (vignette_start + vignette_end) * 0.5;
	float rim_band = smoothstep(rim_centre - rim_width, rim_centre, r) *
	                 (1.0 - smoothstep(rim_centre, rim_centre + rim_width * 0.5, r));
	EMISSION = rim_color * rim_band * rim_intensity * fade;
}
