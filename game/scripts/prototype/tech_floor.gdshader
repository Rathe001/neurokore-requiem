shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.12, 0.13, 0.15);
uniform vec3 seam_color : source_color = vec3(0.02, 0.025, 0.03);
uniform vec3 bolt_color : source_color = vec3(0.05, 0.06, 0.07);
uniform float tile_size : hint_range(0.1, 10.0) = 1.5;  // world-space metres per tile
uniform float seam_width : hint_range(0.0, 0.1) = 0.025;
uniform float bolt_radius : hint_range(0.0, 0.1) = 0.04;
uniform float bolt_inset : hint_range(0.0, 0.3) = 0.12;
uniform float panel_variation : hint_range(0.0, 0.1) = 0.03;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.25;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.65;
uniform float roughness_seam : hint_range(0.0, 1.0) = 0.95;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 coord = world_pos.xz / tile_size;
	vec2 panel_id = floor(coord);
	vec2 cell = fract(coord);
	vec2 edge = min(cell, 1.0 - cell);
	float seam = 1.0 - smoothstep(0.0, seam_width, min(edge.x, edge.y));

	vec2 b = min(cell - bolt_inset, (1.0 - bolt_inset) - cell);
	float corner_d = min(length(vec2(max(-b.x, 0.0), max(-b.y, 0.0))), 1.0);
	float bolt = 1.0 - smoothstep(bolt_radius * 0.7, bolt_radius, corner_d);

	float var = (hash(panel_id) - 0.5) * 2.0 * panel_variation;
	vec3 panel = base_color + vec3(var);

	vec3 col = mix(panel, seam_color, seam);
	col = mix(col, bolt_color, bolt * (1.0 - seam));

	ALBEDO = col;
	METALLIC = metallic_val;
	ROUGHNESS = mix(roughness_base, roughness_seam, max(seam, bolt * 0.5));
}
