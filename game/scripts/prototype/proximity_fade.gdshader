shader_type spatial;

global uniform vec3 player_world_pos;

uniform vec3 base_color : source_color = vec3(0.55, 0.65, 0.75);
uniform vec3 emission_color : source_color = vec3(0.55, 0.65, 0.75);
uniform float emission_energy : hint_range(0.0, 5.0) = 0.6;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.6;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.4;
uniform float fade_inner : hint_range(0.0, 5.0) = 1.0;
uniform float fade_outer : hint_range(0.0, 10.0) = 3.0;
uniform float fade_height : hint_range(0.0, 5.0) = 3.5;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 player_view = (VIEW_MATRIX * vec4(player_world_pos, 1.0)).xyz;
	vec3 frag_view = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	float in_front = smoothstep(-0.5, 0.0, frag_view.z - player_view.z);
	vec2 ss_offset = frag_view.xy - player_view.xy;
	float ss_dist = length(ss_offset);
	float proximity_fade = smoothstep(fade_inner, fade_outer, ss_dist);
	float height_mask = smoothstep(fade_height - 0.3, fade_height, world_pos.y);
	float fade = mix(1.0, mix(1.0, proximity_fade, height_mask), in_front);

	if (fade < 1.0) {
		float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (fade < noise) {
			discard;
		}
	}

	ALBEDO = base_color;
	EMISSION = emission_color * emission_energy;
	METALLIC = metallic_val;
	ROUGHNESS = roughness_val;
}
