shader_type spatial;

// Spatial-distortion blade-slash for 1H melee. Same arc geometry as
// the previous procedural-glow version, but the surface refracts the
// scene behind it via SCREEN_TEXTURE sampling rather than emitting a
// flat band of light. Reads as "the air gets cut" rather than "the
// air glows briefly."
//
// UV remapped to (-1..1) on both axes:
//   x = along the slash length (taper at ±1 endpoints)
//   y = perpendicular to the slash arc (distance from the centerline)
//
// The host script tweens `intensity` 0 → 1 → 0 across the slash
// duration; both distortion amount and the thin fringe scale with it
// so the effect grows in and out smoothly.

render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, blend_mix;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec3 fringe_color : source_color = vec3(1.0, 0.95, 0.85);
uniform float intensity : hint_range(0.0, 20.0) = 5.0;
// Curvature pulls the arc's midpoint away from a straight line.
uniform float curvature = 0.28;
// Half-thickness of the warped band around the arc, in UV space.
uniform float thickness = 0.18;
// Width of the bright core inside the warped band.
uniform float core_thickness = 0.05;
// Max screen-UV distance pixels get pushed at the centerline.
uniform float distortion_strength : hint_range(0.0, 0.2) = 0.045;
// Strength of chromatic aberration — splits R / G / B channels by the
// distortion amount so the cut reads as a lens-y warp instead of a
// uniform smear. 0 = no aberration, 1 = strong.
uniform float chromatic : hint_range(0.0, 1.0) = 0.55;

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float arc_y = curvature * (1.0 - uv.x * uv.x);
	float signed_dist = uv.y - arc_y;
	float dist = abs(signed_dist);
	float side = sign(signed_dist);

	// Same arc + taper mask as the old glow shader.
	float core = 1.0 - smoothstep(0.0, core_thickness, dist);
	float halo = 1.0 - smoothstep(0.0, thickness, dist);
	float taper = 1.0 - smoothstep(0.7, 1.0, abs(uv.x));
	float arc_mask = halo * taper;

	// Distortion: push the screen-UV outward from the arc centerline.
	// "Outward" is the direction of `side` along V — the arc gets a
	// pinch perpendicular to itself, refracting the scene visibly.
	float push = arc_mask * distortion_strength * clamp(intensity * 0.4, 0.0, 1.0);
	vec2 distort_dir = vec2(0.0, -side);
	vec2 base_uv = SCREEN_UV + distort_dir * push;

	// Chromatic aberration on the refraction. R and B are nudged in
	// opposite horizontal directions by a fraction of `push` so the
	// warped scene fringes apart slightly — sells the "energy blade"
	// without needing a bright glow.
	vec3 sampled;
	if (chromatic > 0.01) {
		float ca = chromatic * push * 0.5;
		sampled.r = textureLod(screen_texture, base_uv + vec2(ca, 0.0), 0.0).r;
		sampled.g = textureLod(screen_texture, base_uv, 0.0).g;
		sampled.b = textureLod(screen_texture, base_uv - vec2(ca, 0.0), 0.0).b;
	} else {
		sampled = textureLod(screen_texture, base_uv, 0.0).rgb;
	}

	// Thin highlight along the cut so the slash silhouette stays
	// visible against featureless surfaces (where pure refraction
	// wouldn't be noticeable). Scales with intensity so it appears
	// at the swing's peak and fades with the rest of the effect.
	float fringe = core * taper * intensity * 0.18;
	vec3 col = sampled + fringe_color * fringe;

	// Opacity cap — keep the distortion barely visible so it reads as
	// a hint of air-cut rather than a glowing arc. 0.06 = ~6% alpha
	// at the densest part of the swing; the world behind still shows
	// through at near-full brightness.
	ALBEDO = col;
	ALPHA = clamp(arc_mask * intensity * 0.85 + fringe * 0.4, 0.0, 0.06);
}
