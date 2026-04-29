shader_type spatial;

// Riveted-plate wall variant. Same triplanar foundation as tech_wall but with
// taller, narrower panels divided by vertical channels and a row of rivet
// dimples down each seam — reads as utility / corridor cladding rather than
// the broad room panels of tech_wall.

global uniform vec3 player_world_pos;

uniform vec3 base_color : source_color = vec3(0.18, 0.19, 0.22);
uniform vec3 seam_color : source_color = vec3(0.08, 0.09, 0.10);
uniform vec3 rivet_color : source_color = vec3(0.10, 0.11, 0.13);
uniform vec3 accent_color : source_color = vec3(0.13, 0.14, 0.16);
uniform vec2 tiling = vec2(1.4, 0.45);
uniform float seam_width : hint_range(0.0, 0.1) = 0.05;
uniform float rivet_radius : hint_range(0.0, 0.1) = 0.03;
uniform float rivet_spacing : hint_range(0.05, 0.5) = 0.14;
uniform float panel_variation : hint_range(0.0, 0.1) = 0.022;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.4;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_seam : hint_range(0.0, 1.0) = 0.85;
uniform float bump_strength : hint_range(0.0, 5.0) = 1.0;
uniform float grit_strength : hint_range(0.0, 1.0) = 0.18;
uniform bool fade_enabled = false;
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

	// Vertical seams dominate (wider gap), horizontal seams quieter — gives
	// the cladding-strip read.
	float aa_v = fwidth(cell.x) * 1.5;
	float vert_d = min(cell.x, 1.0 - cell.x);
	float vseam = 1.0 - smoothstep(0.0, max(seam_width, aa_v), vert_d);

	float aa_h = fwidth(cell.y) * 1.5;
	float horiz_d = min(cell.y, 1.0 - cell.y);
	float hseam = 1.0 - smoothstep(0.0, max(seam_width * 0.5, aa_h), horiz_d);

	float seam = max(vseam, hseam * 0.6);

	// Rivets along the vertical seams. Snap y to a discrete row, drop a
	// dimple on the seam line. Two columns per panel (one on each side).
	float row = floor(cell.y / rivet_spacing + 0.5);
	float rivet_y = row * rivet_spacing - cell.y;
	float left_x = cell.x;
	float right_x = 1.0 - cell.x;
	float side_x = min(left_x, right_x);
	float rivet_d = length(vec2(side_x, rivet_y));
	float aa_rivet = fwidth(rivet_d) * 1.5;
	float rivet = 1.0 - smoothstep(rivet_radius - aa_rivet, rivet_radius, rivet_d);
	rivet *= step(0.05, side_x);  // suppress rivet right on the seam itself

	float pvar = (hash(panel_id) - 0.5) * 2.0 * panel_variation;
	vec3 panel = base_color + vec3(pvar);

	// Subtle vertical accent stripe down the centre of each panel.
	float accent_d = abs(cell.x - 0.5);
	float accent = 1.0 - smoothstep(0.04, 0.06, accent_d);
	panel = mix(panel, accent_color, accent * 0.4);

	vec3 col = mix(panel, seam_color, seam);
	col = mix(col, rivet_color, rivet * (1.0 - seam));

	float grit = vnoise(coord * 4.0) - 0.5;
	col += vec3(grit) * grit_strength * 0.05 * (1.0 - seam);

	float macro = vnoise(coord * 0.5) - 0.5;

	float h = -seam * 0.85 - rivet * 0.35 + macro * 0.025;
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
	ROUGHNESS = mix(roughness_base, roughness_seam, max(seam, rivet * 0.5));
	NORMAL = (VIEW_MATRIX * vec4(perturbed_world, 0.0)).xyz;
}
