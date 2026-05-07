shader_type spatial;

// Textured wall shader — drop-in replacement for tech_wall.gdshader that
// samples a tileable albedo texture instead of computing the panel pattern
// procedurally. Keeps the camera-occlusion fade and triplanar projection
// logic intact so it slots into the existing wall geometry without other
// changes.
//
// Tint, metallic, and roughness are still tuned per-theme via uniforms;
// the texture provides surface detail (panels, bolts, grime) and the
// material settings push it toward the room's color identity.

global uniform vec3 player_world_pos;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
// World units per texture repeat. Lower = bigger panels on screen.
uniform vec2 tiling = vec2(0.5, 0.5);
uniform float metallic_val : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.55;
uniform bool fade_enabled = false;
uniform float fade_inner : hint_range(0.0, 5.0) = 1.0;
uniform float fade_outer : hint_range(0.0, 10.0) = 3.0;
uniform float fade_height : hint_range(0.0, 5.0) = 3.5;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Triplanar world-space projection — same selection as tech_wall.gdshader
	// so the texture wraps cleanly across face transitions.
	vec3 an = abs(world_normal);
	vec2 coord;
	if (an.y > max(an.x, an.z)) {
		coord = world_pos.xz * tiling;
	} else if (an.x > an.z) {
		coord = vec2(world_pos.z, world_pos.y) * tiling;
	} else {
		coord = vec2(world_pos.x, world_pos.y) * tiling;
	}

	vec3 col = texture(albedo_texture, coord).rgb * tint;

	// Camera-space line-of-sight occlusion fade — copied verbatim from
	// tech_wall.gdshader. Walls between camera and player ramp out via
	// dither discard so the player stays visible behind tall geometry.
	if (fade_enabled) {
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
	}

	ALBEDO = col;
	METALLIC = metallic_val;
	ROUGHNESS = roughness_val;
}
