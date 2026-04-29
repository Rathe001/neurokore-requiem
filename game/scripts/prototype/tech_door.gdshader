shader_type spatial;

// Sliding blast-door panel. Drives detailing off mesh-local position so the
// pattern stays welded to the slab as it slides — unlike tech_wall, which
// uses world-space triplanar and would scroll across a moving door.

global uniform vec3 player_world_pos;

uniform vec3 base_color : source_color = vec3(0.19, 0.21, 0.24);
uniform vec3 frame_color : source_color = vec3(0.09, 0.10, 0.12);
uniform vec3 accent_color : source_color = vec3(0.27, 0.30, 0.34);
uniform vec3 hazard_color : source_color = vec3(0.85, 0.65, 0.10);
uniform float metallic_val : hint_range(0.0, 1.0) = 0.5;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.55;
uniform float bump_strength : hint_range(0.0, 5.0) = 1.0;
uniform float panel_count : hint_range(1.0, 6.0) = 3.0;
uniform float hazard_visibility : hint_range(0.0, 1.0) = 1.0;
uniform bool fade_enabled = false;
uniform float fade_inner : hint_range(0.0, 5.0) = 1.0;
uniform float fade_outer : hint_range(0.0, 10.0) = 3.0;
uniform float fade_height : hint_range(0.0, 5.0) = 3.5;

varying vec3 world_pos;
varying vec3 local_pos;
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
	local_pos = VERTEX;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Mesh-local axes — door is 0.4 (X) × 4.5 (Y) × 4 (Z). Normalize to ±1.
	float ny = clamp(local_pos.y / 2.25, -1.0, 1.0);
	float nz = clamp(local_pos.z / 2.0, -1.0, 1.0);

	// Vertical center seam where the two halves of a sliding door meet.
	float seam_dist = abs(nz);
	float center_seam = 1.0 - smoothstep(0.0, 0.025, seam_dist);

	// Recessed border around the active panel surface — frames the slab.
	float border = max(abs(ny), abs(nz));
	float frame = smoothstep(0.86, 0.94, border);

	// Horizontal panel divisions across each half. panel_count controls how
	// many sub-panels per half (default 3).
	float panel_pattern = abs(fract(ny * panel_count * 0.5) - 0.5) * 2.0;
	float panel_seam = smoothstep(0.86, 0.96, panel_pattern) * (1.0 - frame);

	// Hazard chevrons along the top edge of the door, between the frame band
	// and the upper recess. Diagonal stripes give a sci-fi airlock read.
	float top_band = smoothstep(0.74, 0.78, ny) - smoothstep(0.84, 0.86, ny);
	float chevron_pos = local_pos.z * 1.4 + abs(local_pos.y - 1.85) * 4.0;
	float stripe = step(0.5, fract(chevron_pos * 0.6));
	float hazard = top_band * stripe * (1.0 - frame) * hazard_visibility;

	// Stable hash grunge — fract(sin(...)) keyed off mesh-local cells so it
	// rides with the slab instead of shimmering when it moves.
	vec2 hash_coord = floor(vec2(local_pos.y * 14.0, local_pos.z * 14.0));
	float grunge = (hash(hash_coord) - 0.5) * 0.06;

	vec3 col = base_color + vec3(grunge);
	col = mix(col, accent_color * 0.85, panel_seam);
	col = mix(col, frame_color * 0.6, frame);
	col = mix(col, frame_color * 0.4, center_seam);
	col = mix(col, hazard_color, hazard);

	// Procedural bump via screen-space derivatives — recess seams, frame,
	// and panel divisions; macro wobble keeps the panel face from looking
	// flat under the spotlight.
	float macro = vnoise(vec2(local_pos.y, local_pos.z) * 1.5) - 0.5;
	float h = -frame * 0.85 - center_seam * 0.65 - panel_seam * 0.35 + macro * 0.04;
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

	// Camera-space line-of-sight occlusion fade so the door dithers out when
	// the player is hidden behind it. Mirrors tech_wall's behaviour.
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
	METALLIC = metallic_val * (1.0 - frame * 0.5);
	ROUGHNESS = mix(roughness_val, 0.85, frame + center_seam);
	NORMAL = (VIEW_MATRIX * vec4(perturbed_world, 0.0)).xyz;
}
