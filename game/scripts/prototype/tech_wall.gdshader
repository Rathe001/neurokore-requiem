shader_type spatial;

global uniform vec3 player_world_pos;

uniform vec3 base_color : source_color = vec3(0.17, 0.18, 0.20);
uniform vec3 seam_color : source_color = vec3(0.03, 0.035, 0.04);
uniform vec3 accent_color : source_color = vec3(0.08, 0.09, 0.11);
uniform vec2 tiling = vec2(2.0, 0.5);
uniform float seam_width : hint_range(0.0, 0.1) = 0.03;
uniform float accent_band_pos : hint_range(0.0, 1.0) = 0.35;
uniform float accent_band_width : hint_range(0.0, 0.5) = 0.06;
uniform float panel_variation : hint_range(0.0, 0.1) = 0.025;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_seam : hint_range(0.0, 1.0) = 0.85;
uniform float fade_inner : hint_range(0.0, 5.0) = 1.0;
uniform float fade_outer : hint_range(0.0, 10.0) = 3.0;
uniform float fade_height : hint_range(0.0, 5.0) = 3.5;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Triplanar world-space projection — select axes based on face normal.
	vec3 an = abs(world_normal);
	vec2 coord;
	if (an.y > max(an.x, an.z)) {
		coord = world_pos.xz * tiling.x;
	} else if (an.x > an.z) {
		coord = vec2(world_pos.z * tiling.x, world_pos.y * tiling.y);
	} else {
		coord = vec2(world_pos.x * tiling.x, world_pos.y * tiling.y);
	}
	vec2 panel_id = floor(coord);
	vec2 cell = fract(coord);
	vec2 edge = min(cell, 1.0 - cell);
	float seam = 1.0 - smoothstep(0.0, seam_width, min(edge.x, edge.y));

	float band_edge = abs(cell.y - accent_band_pos);
	float band = 1.0 - smoothstep(accent_band_width * 0.5, accent_band_width, band_edge);

	float pvar = (hash(panel_id) - 0.5) * 2.0 * panel_variation;
	vec3 panel = base_color + vec3(pvar);
	panel = mix(panel, accent_color, band * 0.6);

	vec3 col = mix(panel, seam_color, seam);

	// Camera-space line-of-sight occlusion fade.
	// Only fade the upper portion of walls that sit between the camera
	// and the player. The lower wall stays solid so light cannot bleed through.
	vec3 player_view = (VIEW_MATRIX * vec4(player_world_pos, 1.0)).xyz;
	vec3 frag_view = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	float in_front = smoothstep(-0.5, 0.0, frag_view.z - player_view.z);
	vec2 ss_offset = frag_view.xy - player_view.xy;
	float ss_dist = length(ss_offset);
	float proximity_fade = smoothstep(fade_inner, fade_outer, ss_dist);
	float height_mask = smoothstep(fade_height - 0.3, fade_height, world_pos.y);
	float fade = mix(1.0, mix(1.0, proximity_fade, height_mask), in_front);

	// Dithered discard — each pixel is fully opaque or gone.
	// Prevents double-rendering when overlapping walls both fade.
	if (fade < 1.0) {
		float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (fade < noise) {
			discard;
		}
	}

	ALBEDO = col;
	METALLIC = metallic_val;
	ROUGHNESS = mix(roughness_base, roughness_seam, seam);
}
