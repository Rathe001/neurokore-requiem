shader_type spatial;

// Diamond-tread / catwalk floor variant. Same world-space tile foundation as
// tech_floor but with a repeating diamond stamp inside each tile and tighter
// seam grid — reads as utility walkway plating.

uniform vec3 base_color : source_color = vec3(0.10, 0.11, 0.13);
uniform vec3 seam_color : source_color = vec3(0.06, 0.07, 0.08);
uniform vec3 tread_color : source_color = vec3(0.16, 0.17, 0.19);
uniform float tile_size : hint_range(0.1, 10.0) = 1.0;
uniform float seam_width : hint_range(0.0, 0.1) = 0.035;
uniform float tread_count : hint_range(1.0, 8.0) = 4.0;
uniform float tread_size : hint_range(0.1, 0.5) = 0.32;
uniform float panel_variation : hint_range(0.0, 0.1) = 0.022;
// Specular-shimmer guards — see tech_wall_riveted. The grate's diamond
// pattern + previous metallic 0.55 made this the worst shimmer surface
// in the level; the high bump strength meant tiny normal perturbations
// produced large per-pixel specular swings under camera motion. Cut
// metallic and bump_strength aggressively here.
uniform float metallic_val : hint_range(0.0, 1.0) = 0.22;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.72;
uniform float roughness_seam : hint_range(0.0, 1.0) = 0.92;
uniform float bump_strength : hint_range(0.0, 5.0) = 0.70;
uniform float grit_strength : hint_range(0.0, 1.0) = 0.22;

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

	float d_seam = min(edge.x, edge.y);
	float aa_seam = fwidth(d_seam) * 1.5;
	float seam = 1.0 - smoothstep(0.0, max(seam_width, aa_seam), d_seam);

	// Diamond-plate tread pattern. Sample on a sub-grid inside each tile and
	// compute a rotated-square distance so the plate is unmistakably diamond.
	vec2 tread_coord = cell * tread_count;
	vec2 tread_cell = fract(tread_coord) - 0.5;
	// 45-degree rotated square — abs(x)+abs(y) is the L1 (taxicab) norm,
	// whose iso-contours are diamonds.
	float diamond_d = abs(tread_cell.x) + abs(tread_cell.y);
	float aa_tread = fwidth(diamond_d) * 1.5;
	float tread = 1.0 - smoothstep(tread_size - aa_tread, tread_size, diamond_d);
	tread *= 1.0 - seam;  // suppress treads that would overlap the seam

	float pvar = (hash(panel_id) - 0.5) * 2.0 * panel_variation;
	vec3 panel = base_color + vec3(pvar);

	vec3 col = mix(panel, seam_color, seam);
	col = mix(col, tread_color, tread * 0.85);

	float grit = vnoise(coord * 5.0) - 0.5;
	col += vec3(grit) * grit_strength * 0.04 * (1.0 - seam);

	float macro = vnoise(coord * 0.6) - 0.5;

	// Treads are RAISED (positive height); seams recessed.
	float h = -seam * 0.85 + tread * 0.6 + macro * 0.02;
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
	ROUGHNESS = mix(roughness_base, roughness_seam, max(seam, tread * 0.3));
	NORMAL = (VIEW_MATRIX * vec4(perturbed_world, 0.0)).xyz;
}
