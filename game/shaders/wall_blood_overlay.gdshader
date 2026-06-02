// Wall blood overlay — Phase 6.6 (multiply-stain + emission for visibility).
// Two masks: mask_x covers ±X-facing walls (indexed by (z, y)),
// mask_z covers ±Z-facing walls (indexed by (x, y)). Wall's world
// normal picks which mask to sample.
//
// Visibility tweaks vs Phase 5:
// - Multiply-stain over screen_texture (matches floor liquid_surface
//   look) — bright walls become bright red, dark walls become red-
//   tinted dark instead of black.
// - stain_brightness boost lifts the multiplied result so the stain
//   reads as visible blood even on the dim industrial walls.
// - Small emission so blood is faintly visible in pitch-black corners.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D mask_x : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D mask_z : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float world_extent_xz : hint_range(8.0, 200.0) = 40.0;
uniform float wall_height : hint_range(1.0, 16.0) = 4.0;
// Match liquid_surface.gdshader's defaults so floor and wall blood
// read as the same material — same tint, same brightness curve, same
// roughness for the wet sheen. No emission: floor blood doesn't glow,
// neither should walls.
uniform vec3 blood_tint : source_color = vec3(0.55, 0.10, 0.10);
uniform float stain_brightness : hint_range(0.5, 4.0) = 2.0;
// Higher threshold than the previous 0.015. The lower value let very
// faint cumulative coverage (drip tails, edge fall-off from many
// overlapping stamps) render as visible blood — once combined with
// solid_opacity boosting toward pure tint, those faint areas painted
// the wall in horizontal bars wherever stamps had clustered along a
// single mask row. 0.08 keeps real splatter coverage visible while
// gating the trail-end haze that was producing the strip artifact.
uniform float coverage_threshold : hint_range(0.0, 0.5) = 0.08;
uniform float edge_softness : hint_range(0.0, 0.3) = 0.06;
uniform float blood_roughness : hint_range(0.0, 1.0) = 0.22;
// Same uniform as liquid_surface.gdshader (keep in sync so floor +
// wall blood read as the same material): blends from pure multiply-
// stain (0.0) toward solid painted tint (1.0). Dense blood reads as
// painted; edges stay translucent. 0.12 is a subtle lift — enough to
// pull dense blood out of "faint shadow" territory without overriding
// the surface texture.
uniform float solid_opacity : hint_range(0.0, 1.0) = 0.12;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float a;
	float half_h = 0.5;
	if (abs(v_world_normal.x) > abs(v_world_normal.z)) {
		vec2 uv = vec2(
			v_world_pos.z / world_extent_xz + half_h,
			1.0 - v_world_pos.y / wall_height
		);
		a = texture(mask_x, uv).a;
	} else {
		vec2 uv = vec2(
			v_world_pos.x / world_extent_xz + half_h,
			1.0 - v_world_pos.y / wall_height
		);
		a = texture(mask_z, uv).a;
	}
	if (a < coverage_threshold) {
		discard;
	}
	float blood_alpha = smoothstep(coverage_threshold, coverage_threshold + edge_softness, min(a, 1.0));
	// Sample the wall behind this fragment via screen-space — the
	// overlay quad sits ~5mm in front of the wall, so SCREEN_UV reads
	// the wall pixel underneath. Multiply-stain darkens that to blood
	// red while preserving the wall's panel detail / shadow / etc.
	vec3 behind = texture(screen_tex, SCREEN_UV).rgb;
	vec3 stained = behind * blood_tint * stain_brightness;
	// Blend toward solid blood color so dense areas read as opaque
	// blood paint rather than a faint tint over the wall texture.
	// Same opacity term as the floor shader uses.
	stained = mix(stained, blood_tint, solid_opacity);
	ALBEDO = stained;
	ROUGHNESS = blood_roughness;
	METALLIC = 0.0;
	ALPHA = blood_alpha;
}
