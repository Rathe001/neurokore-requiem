shader_type spatial;

// Floor-painted ring for the 2H hammer step-2 finisher. Drawn on a
// horizontal PlaneMesh at the player's feet; the shader carves a ring
// out of UV space (annulus SDF) and tweens `progress` from 0 to 1 in
// the host code. Inner radius grows with progress so the ring sweeps
// outward, while a brightness window keeps the visible "line" thin.
//
// Why a shader rather than a mesh: a procedural ring lets us animate
// the radius + thickness + brightness via one uniform without
// rebuilding the mesh, AND naturally fades the trailing edge.

render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;

uniform vec3 ring_color : source_color = vec3(1.0, 0.7, 0.3);
uniform float intensity : hint_range(0.0, 8.0) = 3.0;
// 0..1 — drives ring expansion. Host tweens this over the duration.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
// How thick the visible ring is, in UV space (0..0.5 useful range).
uniform float thickness : hint_range(0.0, 0.5) = 0.06;
// Alpha-cap on the ring so it reads as a paint on the floor instead
// of a solid surface.
uniform float max_alpha : hint_range(0.0, 1.0) = 0.85;


void fragment() {
	// Remap UV to (-1..1) and compute distance from center.
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	// Mask the plane to the unit disc — anything outside is transparent.
	if (r > 1.0) {
		discard;
	}
	// Ring center radius grows with progress. At progress=0 the ring
	// is at the player's feet (r=0); at progress=1 it reaches the
	// plane edge (r=1).
	float ring_r = progress;
	float dist = abs(r - ring_r);
	// Anti-aliased band: 1 inside the line, 0 outside, soft edge over
	// `thickness` UV units on either side.
	float band = 1.0 - smoothstep(thickness * 0.4, thickness, dist);
	// Global fade — ring dims as it expands so the final stages of
	// the sweep don't pop at full brightness.
	float fade = 1.0 - smoothstep(0.6, 1.0, progress);

	float brightness = band * fade * intensity;
	ALBEDO = ring_color * brightness;
	ALPHA = clamp(brightness * max_alpha, 0.0, max_alpha);
}
