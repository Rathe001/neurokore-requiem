shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.17, 0.18, 0.20);
uniform vec3 seam_color : source_color = vec3(0.03, 0.035, 0.04);
uniform vec3 accent_color : source_color = vec3(0.08, 0.09, 0.11);
uniform vec2 tiling = vec2(16.0, 2.0);
uniform float seam_width : hint_range(0.0, 0.1) = 0.03;
uniform float accent_band_pos : hint_range(0.0, 1.0) = 0.35;
uniform float accent_band_width : hint_range(0.0, 0.5) = 0.06;
uniform float panel_variation : hint_range(0.0, 0.1) = 0.025;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_seam : hint_range(0.0, 1.0) = 0.85;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 coord = UV * tiling;
	vec2 panel_id = floor(coord);
	vec2 cell = fract(coord);
	vec2 edge = min(cell, 1.0 - cell);
	float seam = 1.0 - smoothstep(0.0, seam_width, min(edge.x, edge.y));

	float band_edge = abs(cell.y - accent_band_pos);
	float band = 1.0 - smoothstep(accent_band_width * 0.5, accent_band_width, band_edge);

	float var = (hash(panel_id) - 0.5) * 2.0 * panel_variation;
	vec3 panel = base_color + vec3(var);
	panel = mix(panel, accent_color, band * 0.6);

	vec3 col = mix(panel, seam_color, seam);

	ALBEDO = col;
	METALLIC = metallic_val;
	ROUGHNESS = mix(roughness_base, roughness_seam, seam);
}
