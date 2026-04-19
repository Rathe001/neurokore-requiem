shader_type spatial;

uniform vec3 albedo_color : source_color = vec3(0.025, 0.03, 0.04);
uniform vec3 grid_color : source_color = vec3(0.1, 0.55, 0.75);
uniform float grid_emission : hint_range(0.0, 10.0) = 2.0;
uniform float metallic : hint_range(0.0, 1.0) = 0.65;
uniform float roughness : hint_range(0.0, 1.0) = 0.12;
uniform float plane_size = 60.0;
uniform float fade_start : hint_range(0.0, 0.5) = 0.15;
uniform float fade_end : hint_range(0.0, 0.8) = 0.5;

void fragment() {
	vec2 coord = UV * plane_size;
	vec2 grid = abs(fract(coord) - 0.5);
	vec2 d = fwidth(coord) * 1.5;
	vec2 line_mask = smoothstep(0.5 - d, 0.5, grid);
	float line = max(line_mask.x, line_mask.y);

	float dist = length(UV - vec2(0.5));
	float radial = 1.0 - smoothstep(fade_start, fade_end, dist);
	line *= radial;

	ALBEDO = albedo_color;
	EMISSION = grid_color * grid_emission * line;
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
