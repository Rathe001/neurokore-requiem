shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.12, 0.13, 0.15);
uniform vec3 seam_color : source_color = vec3(0.07, 0.08, 0.09);
uniform vec3 bolt_color : source_color = vec3(0.09, 0.10, 0.11);
uniform float tile_size : hint_range(0.1, 10.0) = 1.5;  // world-space metres per tile
uniform float seam_width : hint_range(0.0, 0.1) = 0.04;
uniform float bolt_radius : hint_range(0.0, 0.1) = 0.04;
uniform float bolt_inset : hint_range(0.0, 0.3) = 0.12;
uniform float panel_variation : hint_range(0.0, 0.1) = 0.03;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.25;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.65;
uniform float roughness_seam : hint_range(0.0, 1.0) = 0.95;
uniform float bump_strength : hint_range(0.0, 5.0) = 1.1;
uniform float grit_strength : hint_range(0.0, 1.0) = 0.25;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 coord = world_pos.xz / tile_size;
	vec2 panel_id = floor(coord);
	vec2 cell = fract(coord);
	vec2 edge = min(cell, 1.0 - cell);

	// Analytic anti-aliasing: widen the smoothstep transition so it always
	// spans at least one screen pixel. Without this, sub-pixel seams flicker
	// and produce moiré patterns that scroll as the camera moves.
	float d_seam = min(edge.x, edge.y);
	float aa_seam = fwidth(d_seam) * 1.5;
	float seam = 1.0 - smoothstep(0.0, max(seam_width, aa_seam), d_seam);

	vec2 b = min(cell - bolt_inset, (1.0 - bolt_inset) - cell);
	float corner_d = min(length(vec2(max(-b.x, 0.0), max(-b.y, 0.0))), 1.0);
	float aa_bolt = fwidth(corner_d) * 1.5;
	float bolt_band = max(bolt_radius * 0.3, aa_bolt);
	float bolt = 1.0 - smoothstep(bolt_radius - bolt_band, bolt_radius, corner_d);

	float pvar = (hash(panel_id) - 0.5) * 2.0 * panel_variation;
	vec3 panel = base_color + vec3(pvar);

	vec3 col = mix(panel, seam_color, seam);
	col = mix(col, bolt_color, bolt * (1.0 - seam));

	// Per-tile wear overlay — color-only. Low frequency so flecks are large
	// enough not to alias / shimmer as the camera moves. Keep OUT of height.
	float grit = vnoise(coord * 4.0) - 0.5;
	col += vec3(grit) * grit_strength * 0.045 * (1.0 - seam);

	// Low-frequency macro variation: smooth large-scale wear so tiles don't
	// look like glass plates. Smooth, so derivatives stay well-behaved.
	float macro = vnoise(coord * 0.5) - 0.5;

	// ── Procedural bump via Mikkelsen-style screen derivatives ────────────
	// Seams: recessed grooves. Bolts: small pits. Macro: gentle surface relief.
	// Macro contribution is small to avoid specular drift while moving.
	float h = -seam * 0.9 - bolt * 0.5 + macro * 0.02;
	vec3 dpdx = dFdx(world_pos);
	vec3 dpdy = dFdy(world_pos);
	float dhdx = dFdx(h);
	float dhdy = dFdy(h);
	vec3 r1 = cross(dpdy, world_normal);
	vec3 r2 = cross(world_normal, dpdx);
	float det = dot(dpdx, r1);
	vec3 perturbed_world = world_normal;
	if (abs(det) > 1e-6) {
		vec3 grad = (dhdx * r1 + dhdy * r2) / det;
		perturbed_world = normalize(world_normal - grad * bump_strength);
	}

	ALBEDO = col;
	METALLIC = metallic_val;
	ROUGHNESS = mix(roughness_base, roughness_seam, max(seam, bolt * 0.5));
	NORMAL = (VIEW_MATRIX * vec4(perturbed_world, 0.0)).xyz;
}
