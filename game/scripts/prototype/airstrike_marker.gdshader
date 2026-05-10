shader_type spatial;

// Floor-painted X for the RPG Tactical Strike. Drawn on a horizontal
// PlaneMesh (UV.x and UV.y span 0..1 across the plane), with the two
// diagonals of the X computed as the SDF |x - y| and |x + y - 1|.
// Reads as a target paint from any camera angle because it's flat on
// the floor (PlaneMesh's default orientation is the X-Z plane), not a
// 3D box that catches iso-camera perspective.

render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec3 marker_color : source_color = vec3(1.0, 0.25, 0.05);
uniform float intensity : hint_range(0.0, 5.0) = 1.4;
uniform float bar_width : hint_range(0.0, 0.5) = 0.08;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.30;


void fragment() {
	vec2 uv = UV;
	// Distance from the two diagonals in UV space.
	float d1 = abs(uv.x - uv.y);            // line through (0,0)-(1,1)
	float d2 = abs(uv.x + uv.y - 1.0);      // line through (0,1)-(1,0)
	float d = min(d1, d2);
	// Anti-aliased threshold: 1 inside the bar, 0 outside, soft edge
	// across `bar_width * 0.5` for sub-pixel AA without a derivative.
	float mask = 1.0 - smoothstep(bar_width * 0.5, bar_width, d);
	// Fade the X tails at the plane's borders so the strokes don't
	// terminate in hard rectangles — they should taper into the floor.
	float edge_x = smoothstep(0.0, 0.06, uv.x) * smoothstep(0.0, 0.06, 1.0 - uv.x);
	float edge_y = smoothstep(0.0, 0.06, uv.y) * smoothstep(0.0, 0.06, 1.0 - uv.y);
	mask *= edge_x * edge_y;

	ALBEDO = marker_color * intensity;
	ALPHA = mask * max_alpha;
}
