shader_type spatial;

global uniform vec3 player_world_pos;

uniform vec3 base_color : source_color = vec3(0.17, 0.18, 0.20);
uniform vec3 seam_color : source_color = vec3(0.10, 0.11, 0.12);
uniform vec3 accent_color : source_color = vec3(0.12, 0.13, 0.14);
uniform vec2 tiling = vec2(2.0, 0.5);
uniform float seam_width : hint_range(0.0, 0.1) = 0.045;
uniform float accent_band_pos : hint_range(0.0, 1.0) = 0.35;
uniform float accent_band_width : hint_range(0.0, 0.5) = 0.06;
uniform float panel_variation : hint_range(0.0, 0.1) = 0.025;
uniform float metallic_val : hint_range(0.0, 1.0) = 0.35;
uniform float roughness_base : hint_range(0.0, 1.0) = 0.55;
uniform float roughness_seam : hint_range(0.0, 1.0) = 0.85;
uniform float bump_strength : hint_range(0.0, 5.0) = 0.9;
uniform float grit_strength : hint_range(0.0, 1.0) = 0.20;
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

	// Analytic anti-aliasing: widen the smoothstep transition so it always
	// spans at least one screen pixel. Without this, sub-pixel seams flicker
	// and create moiré patterns that scroll as the camera moves.
	float d_seam = min(edge.x, edge.y);
	float aa_seam = fwidth(d_seam) * 1.5;
	float seam = 1.0 - smoothstep(0.0, max(seam_width, aa_seam), d_seam);

	float band_edge = abs(cell.y - accent_band_pos);
	float aa_band = fwidth(band_edge) * 1.5;
	float band_w = max(accent_band_width, aa_band);
	float band = 1.0 - smoothstep(band_w * 0.5, band_w, band_edge);

	float pvar = (hash(panel_id) - 0.5) * 2.0 * panel_variation;
	vec3 panel = base_color + vec3(pvar);
	panel = mix(panel, accent_color, band * 0.6);

	vec3 col = mix(panel, seam_color, seam);

	// Procedural wear overlay — color-only. Frequency intentionally low so
	// individual flecks are large enough to not alias / shimmer when the
	// camera moves past them. Keep this OUT of the height field.
	float grit = vnoise(coord * 3.5) - 0.5;
	col += vec3(grit) * grit_strength * 0.05 * (1.0 - seam);

	// Low-frequency macro variation: broad surface wobble so panels don't read
	// as perfectly flat planes. Smooth, so derivatives stay well-behaved.
	float macro = vnoise(coord * 0.45) - 0.5;

	// ── Procedural bump via Mikkelsen-style screen derivatives ────────────
	// Height field: seams deeply recessed, accent band slightly raised,
	// gentle macro relief. Macro contribution is small to avoid specular
	// highlights drifting as the camera moves.
	float h = -seam * 0.9 + band * 0.18 + macro * 0.025;
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

	// Camera-space line-of-sight occlusion fade.
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
	ROUGHNESS = mix(roughness_base, roughness_seam, seam);
	NORMAL = (VIEW_MATRIX * vec4(perturbed_world, 0.0)).xyz;
}
