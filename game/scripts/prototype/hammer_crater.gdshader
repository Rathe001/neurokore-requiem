shader_type spatial;

// Hammer-strike crater (translucent-diffused variant). The previous
// version painted opaque dark over the floor; this one samples the
// scene at a high mipmap level (= blurred copy of whatever's below
// the crater in screen space) and composites the dark tint + rim
// glow on top. Reads as a heat-haze ring where the floor texture
// underneath softens / refracts, rather than a solid scorched patch.
//
// Vertex displacement is unchanged — the rim still pushes up so the
// silhouette is visible from the iso camera. ALPHA is capped low so
// most of the floor shows through.

render_mode blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float age : hint_range(0.0, 1.0) = 0.0;
uniform float radius : hint_range(0.1, 6.0) = 1.5;
uniform vec3 interior_color : source_color = vec3(0.05, 0.04, 0.03);
uniform vec3 rim_color : source_color = vec3(0.14, 0.12, 0.10);
uniform vec3 rim_glow_color : source_color = vec3(1.0, 0.5, 0.18);
uniform float rim_height : hint_range(0.0, 0.4) = 0.12;
uniform float rim_inner : hint_range(0.3, 0.95) = 0.68;
uniform float rim_outer : hint_range(0.4, 1.0) = 0.95;
// Mip level to sample for the diffuse blur. Higher = softer / more
// blurred. 3.0 ≈ a strong heat-haze look without losing all detail.
uniform float diffuse_mip : hint_range(0.0, 6.0) = 3.0;
// Maximum alpha at peak (age = 0). Drops further as age advances.
uniform float max_alpha : hint_range(0.0, 1.0) = 0.35;
// How much of the dark tint blends OVER the blurred scene under the
// crater. 0 = pure blur (very subtle); 1 = pure dark (back to opaque).
uniform float dark_mix : hint_range(0.0, 1.0) = 0.45;

void vertex() {
	float r = length(VERTEX.xz) / radius;
	float rim_peak = (rim_inner + rim_outer) * 0.5;
	float up = smoothstep(rim_inner, rim_peak, r);
	float down = smoothstep(rim_peak, rim_outer, r);
	float rim = up - down;
	VERTEX.y += rim * rim_height;
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	if (r > 0.995) {
		discard;
	}

	float rim_peak = (rim_inner + rim_outer) * 0.5;
	float rim_band = smoothstep(rim_inner * 0.9, rim_peak, r) - smoothstep(rim_peak, rim_outer, r);
	float interior_mask = 1.0 - smoothstep(rim_inner * 0.6, rim_inner, r);

	// Blurred copy of the scene beneath the crater (in screen space).
	// textureLod with diffuse_mip pulls from the auto-generated mipmap
	// chain — no extra render pass needed.
	vec3 blurred = textureLod(screen_texture, SCREEN_UV, diffuse_mip).rgb;

	// Compose: tint mixes rim_color → interior_color radially, then the
	// whole thing blends over the blurred scene via dark_mix. Low
	// dark_mix = mostly blur showing through, high = darker scorched
	// look. Default 0.45 leaves the floor texture clearly readable.
	vec3 tint = mix(rim_color, interior_color, interior_mask);
	vec3 col = mix(blurred, tint, dark_mix);

	// Heat glow on the rim — boosted (vs the opaque version's 2.5) to
	// punch through the lowered alpha; otherwise the rim's hot-iron
	// look would wash out at this transparency.
	float heat = (1.0 - age);
	heat = heat * heat;
	vec3 emit = rim_glow_color * rim_band * heat * 4.5;

	// Alpha tapers off as age advances toward 1.0.
	float alpha = (1.0 - smoothstep(0.6, 1.0, age)) * max_alpha;

	ALBEDO = col;
	EMISSION = emit;
	ALPHA = alpha;
	METALLIC = 0.0;
	ROUGHNESS = 0.85;
}
