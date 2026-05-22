shader_type spatial;

// Tactical range overlay for SCANNER head mod. Draws two concentric
// rings on a horizontal PlaneMesh centered on the player:
//   inner (green, solid)  = weapon effective range (full damage)
//   outer (orange, dashed) = falloff boundary (2x range, 25% damage)
// Subtle scan-line flicker sells the holographic HUD aesthetic.

render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;

uniform float inner_radius : hint_range(0.0, 1.0) = 0.5;
uniform float outer_radius : hint_range(0.0, 1.0) = 1.0;
uniform vec3 inner_color : source_color = vec3(0.2, 0.85, 0.4);
uniform vec3 outer_color : source_color = vec3(0.95, 0.6, 0.15);
// Toned-down defaults — previous values (thickness 0.008, max_alpha
// 0.45, intensity 2.0, scan_speed 2.0) HDR-bloomed bright green/orange
// over the play area and pulled focus from the gameplay. The current
// values keep the rings legible as a quiet reference but no longer
// dominate the frame.
uniform float ring_thickness : hint_range(0.001, 0.05) = 0.005;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.18;
uniform float scan_speed : hint_range(0.0, 8.0) = 0.6;
uniform float dash_count : hint_range(4.0, 64.0) = 24.0;
uniform float intensity : hint_range(0.0, 4.0) = 0.9;

// Scene depth buffer. Used to clip overlay fragments that look past
// the overlay plane into the outer "void ground" mesh (y = -20,
// 20 m below the playable floor) instead of onto room floor (y = 0).
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// Max depth divergence (in clip-space units) between the overlay
// fragment and the scene behind it before we treat this pixel as
// "over the void." Co-planar overlay + floor gives depth_diff ≈ 0;
// pit floors a few meters below give a small positive diff; the
// 20 m drop to the void ground gives a noticeably larger diff.
const float TACTICAL_VOID_DIFF_THRESHOLD = 0.008;

void fragment() {
	// Compare scene depth at this screen pixel to the overlay's own
	// clip-space depth (FRAGCOORD.z is in [0,1], same convention as
	// the depth buffer). Co-planar floor → diff is essentially zero.
	// Void ground 20 m below → diff is large enough to discard.
	// abs() makes this convention-agnostic between reverse-Z (Vulkan/
	// Forward+) and forward-Z (legacy) — either direction of "scene
	// is farther than overlay" trips the discard.
	float scene_depth = texture(depth_texture, SCREEN_UV).x;
	if (abs(scene_depth - FRAGCOORD.z) > TACTICAL_VOID_DIFF_THRESHOLD) {
		discard;
	}
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r > 1.0) {
		discard;
	}

	// Inner ring — solid band.
	float inner_dist = abs(r - inner_radius);
	float inner_band = 1.0 - smoothstep(ring_thickness * 0.4, ring_thickness, inner_dist);

	// Outer ring — dashed via angular step function.
	float outer_dist = abs(r - outer_radius);
	float outer_band = 1.0 - smoothstep(ring_thickness * 0.4, ring_thickness, outer_dist);
	float angle = atan(uv.y, uv.x);
	float dash = step(0.5, fract(angle * dash_count / (2.0 * 3.14159265)));
	outer_band *= dash;

	// Scan-line flicker — horizontal lines scrolling upward.
	float scan = 0.85 + 0.15 * sin(uv.y * 40.0 + TIME * scan_speed);

	// Compose rings.
	vec3 color = inner_color * inner_band + outer_color * outer_band;
	float alpha = (inner_band + outer_band) * scan * max_alpha;

	ALBEDO = color * intensity;
	ALPHA = clamp(alpha, 0.0, max_alpha);
}
