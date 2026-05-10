shader_type canvas_item;

// Fullscreen vignette overlay drawn on a ColorRect that fills the
// viewport. Darkens the screen toward the corners — frames the action
// and adds the cinematic "this is a game, not a window" sell.
//
// `strength` is the darkness floor at the corners (0 = no vignette,
// ~0.5 = heavy noir frame). `softness` controls the falloff distance;
// smaller = sharper edge ring, larger = gentle gradient inward.

uniform float strength : hint_range(0.0, 1.0) = 0.45;
uniform float softness : hint_range(0.0, 1.0) = 0.55;
uniform vec3 tint : source_color = vec3(0.0, 0.0, 0.02);


void fragment() {
	// UV is 0..1 across the screen. Remap to (-1..1) so center is 0.
	vec2 uv = UV * 2.0 - 1.0;
	// Slight elliptical weighting — pull the corners darker than the
	// top/bottom edges, which reads more "lens" than circular falloff.
	uv.x *= 1.05;
	float d = length(uv);
	// Smoothstep gives a soft inner→outer gradient. `softness` is the
	// distance from the corner inward at which the vignette starts.
	float v = smoothstep(1.0 - softness, 1.4, d) * strength;
	COLOR = vec4(tint, v);
}
