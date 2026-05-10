shader_type spatial;

// Procedural blade-slash mark for 1H melee hits. Draws a tapered,
// gently curved arc on a flat plane oriented to face the camera —
// reads as a sword cut sweeping through the air, not a rectangle.
//
// UVs are remapped to (-1..1) on both axes:
//   x = along the slash length (taper at ±1 endpoints)
//   y = perpendicular to the slash (distance from arc)
//
// Host code is expected to fade `intensity` from full to 0 over the
// slash duration; alpha follows automatically via the same uniform.

render_mode unshaded, depth_draw_never, cull_disabled, blend_add;

uniform vec3 slash_color : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 core_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 20.0) = 5.0;
// Curvature pulls the arc's midpoint away from a straight line. 0.0
// = perfectly straight; ~0.3 = gentle saber arc.
uniform float curvature = 0.28;
// Half-thickness of the glowing band around the arc, in UV space.
uniform float thickness = 0.18;
// Width of the bright core inside the halo.
uniform float core_thickness = 0.05;


void fragment() {
	// Remap UV to (-1..1) on both axes so endpoint logic is symmetric.
	vec2 uv = UV * 2.0 - 1.0;
	// Arc y-coordinate at this x: parabolic bow that's 0 at x=±1 and
	// reaches `curvature` at x=0. Flipping the sign inverts the bow.
	float arc_y = curvature * (1.0 - uv.x * uv.x);
	float dist = abs(uv.y - arc_y);

	// Two falloff regions: bright "core" at the cut centerline plus
	// a wider, dimmer "halo" around it for the motion-glow feel.
	float core = 1.0 - smoothstep(0.0, core_thickness, dist);
	float halo = 1.0 - smoothstep(0.0, thickness, dist);

	// Endpoint taper — the slash should thin out toward the ends so
	// it reads as a swept arc, not a fixed rectangle of constant width.
	// Smoothstep from 0.7 → 1.0 in |x| pulls the alpha down at the tips.
	float taper = 1.0 - smoothstep(0.7, 1.0, abs(uv.x));

	float brightness = (halo + core * 1.5) * taper * intensity;
	vec3 col = mix(slash_color, core_color, smoothstep(0.0, 1.5, core * intensity));

	ALBEDO = col;
	EMISSION = col * brightness;
	ALPHA = clamp(brightness * 0.6, 0.0, 1.0);
}
