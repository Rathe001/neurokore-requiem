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
// Scorch tint multiplied into the sampled floor color. Pushed to a
// near-black so the crater reads as a clearly burned patch — the
// earlier warm-grey tint blended in too well and the impact was
// invisible against the dark floor texture.
uniform vec3 tint : source_color = vec3(0.18, 0.13, 0.10);
uniform float tint_mix : hint_range(0.0, 1.0) = 0.65;
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float fade_radius : hint_range(0.5, 100.0) = 20.0;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.45;
uniform float vignette_end : hint_range(0.0, 1.0) = 0.85;
// Strong roughness boost so the scorched zone reads as matte/charred
// against the polished, reflective surrounding floor — the contrast in
// specular response by itself draws the eye.
uniform float roughness_boost : hint_range(0.0, 1.0) = 0.55;
// Hot rim — emissive band just inside the alpha-fade edge that reads
// as "recently struck." Multiplied by `fade` so the heat cools off as
// the crater ages, then ramps to nothing right when the crater
// vanishes. Width is the radial UV-distance over which the band
// peaks; intensity goes above 1.0 so the level's bloom env amp picks
// it up and the rim glows.
uniform vec3 rim_color : source_color = vec3(1.0, 0.45, 0.15);
uniform float rim_intensity : hint_range(0.0, 6.0) = 2.5;
uniform float rim_width : hint_range(0.02, 0.30) = 0.12;

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
