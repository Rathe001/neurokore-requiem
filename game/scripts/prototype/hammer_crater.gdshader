shader_type spatial;

// Hammer-strike crater. Subdivided PlaneMesh whose vertices are
// displaced in the vertex stage to form a raised rim sitting above
// the floor; the interior stays flat (just above the floor surface)
// and is rendered with a dark scorched albedo so the eye reads it
// as a depression even though geometrically it's only the rim that's
// 3D. Re-using the floor's own surface for the "depth" sidesteps
// having to punch a hole in the world geometry.
//
// `age` is tweened 0 → 1 over the lifetime by the spawning script;
// the rim's heat glow fades with age and the whole crater fades to
// transparent.
//
// `radius` matches the world-space half-width of the PlaneMesh so
// the rim placement is independent of the per-strike size.

render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform float age : hint_range(0.0, 1.0) = 0.0;
uniform float radius : hint_range(0.1, 6.0) = 1.5;
uniform vec3 interior_color : source_color = vec3(0.04, 0.03, 0.025);
uniform vec3 rim_color : source_color = vec3(0.14, 0.12, 0.10);
uniform vec3 rim_glow_color : source_color = vec3(1.0, 0.5, 0.18);
uniform float rim_height : hint_range(0.0, 0.4) = 0.12;
// Inner radius (UV space [0..1]) at which the rim band starts.
uniform float rim_inner : hint_range(0.3, 0.95) = 0.68;
uniform float rim_outer : hint_range(0.4, 1.0) = 0.95;

void vertex() {
	// VERTEX is in mesh local space; PlaneMesh lies in the XZ plane.
	// Distance from mesh centre, normalised by radius so r is in [0, 1]
	// across the mesh.
	float r = length(VERTEX.xz) / radius;
	// Rim band: smoothstep up to rim_peak, smoothstep back down to 0.
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

	// Three zones along radius:
	//   r < rim_inner    → dark interior (charred ground)
	//   rim_inner..rim_outer → raised rim band
	//   r > rim_outer    → tapers to discard at 0.995
	float rim_peak = (rim_inner + rim_outer) * 0.5;
	float rim_band = smoothstep(rim_inner * 0.9, rim_peak, r) - smoothstep(rim_peak, rim_outer, r);
	float interior_mask = 1.0 - smoothstep(rim_inner * 0.6, rim_inner, r);

	vec3 col = mix(rim_color, interior_color, interior_mask);
	// Subtle radial cracks via a cheap sin pattern keyed to angle.
	// Cracks darken the interior, sell the impact damage.
	float angle = atan(UV.y - 0.5, UV.x - 0.5);
	float crack = 0.5 + 0.5 * sin(angle * 6.0);
	crack *= step(0.7, crack);  // sparser bright lines
	col *= 1.0 - (1.0 - interior_mask) * 0.0 - interior_mask * crack * 0.4;

	// Heat glow on the rim, fades hot → cold across the lifetime.
	float heat = (1.0 - age);
	heat = heat * heat;  // sharper falloff so it cools quickly
	vec3 emit = rim_glow_color * rim_band * heat * 2.5;

	// Slow alpha fade so the crater lingers after the heat dies down.
	float alpha = 1.0 - smoothstep(0.6, 1.0, age);

	ALBEDO = col;
	EMISSION = emit;
	ALPHA = alpha;
	METALLIC = 0.0;
	ROUGHNESS = 0.85;
}
