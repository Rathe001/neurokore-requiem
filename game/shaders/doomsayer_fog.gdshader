// Doomsayer aura fog disc — a single PlaneMesh laid flat on the floor
// around the player. fbm noise is sampled in radial UV space, rotated
// over time, and faded out at the disc's edge so the boundary isn't
// visible. Soft-particles depth fade clips against world geometry so
// the disc doesn't paint over walls / pits / step heights.
//
// Inspired by godotshaders.com/shader/spinning-fog-circle.

shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// Color tint of the fog. Alpha modulates the maximum density.
uniform vec4 fog_color : source_color = vec4(0.78, 0.35, 0.85, 1.0);
// Overall density — driven by the perk tier from the GD side.
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
// Rotation speed of the inner noise field, in radians per second.
uniform float spin_speed : hint_range(-2.0, 2.0) = 0.25;
// Larger noise_scale = finer detail; smaller = wide soft puffs.
uniform float noise_scale : hint_range(0.5, 8.0) = 2.5;
// 0 = sharp circle edge, 1 = fades from the centre.
uniform float edge_softness : hint_range(0.0, 1.0) = 0.55;
// Inner cutoff so the very centre doesn't read as a solid disc.
uniform float center_clear : hint_range(0.0, 0.6) = 0.10;
// Soft-particles fade range — fragments within this many world units
// of opaque scene geometry get faded out so the disc doesn't paint
// across walls or step edges.
uniform float depth_fade_distance : hint_range(0.0, 2.0) = 0.4;

uniform sampler2D depth_sampler : hint_depth_texture, repeat_disable, filter_nearest;

// View-space position from vertex stage — used in fragment for the
// soft-particles depth comparison (VERTEX itself is vertex-only in
// Godot 4, so we have to pass it as a varying).
varying vec3 view_pos;


// 2D value-noise hash — fast, no texture sampling, deterministic.
float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise — bilinear interpolation between integer-cell hashes.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 4-octave fractal Brownian motion. Output range roughly 0..1.
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}


void vertex() {
	view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	// Radial UV centred on (0,0). dist = 0 at centre, ~1 at the disc edge
	// (assuming the PlaneMesh has UVs in 0..1).
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 2.0;

	// Rotate the noise sample around the centre. Two layers spin opposite
	// directions for a swirling-vapor feel — single-direction rotation
	// reads as a turntable, not a cloud.
	float a1 = TIME * spin_speed;
	float a2 = TIME * spin_speed * -0.6;
	mat2 rot1 = mat2(vec2(cos(a1), -sin(a1)), vec2(sin(a1), cos(a1)));
	mat2 rot2 = mat2(vec2(cos(a2), -sin(a2)), vec2(sin(a2), cos(a2)));
	float n1 = fbm(rot1 * uv * noise_scale);
	float n2 = fbm(rot2 * uv * noise_scale * 1.7 + vec2(11.3, 5.7));
	float n = n1 * 0.65 + n2 * 0.35;

	// Radial falloff: clear inner disc + soft outer edge. center_clear
	// keeps the player's own footprint readable.
	float inner = smoothstep(center_clear, center_clear + 0.05, dist);
	float outer = 1.0 - smoothstep(1.0 - edge_softness, 1.0, dist);
	float radial = inner * outer;

	// Soft-particles depth fade — sample the scene depth at this fragment
	// and fade alpha as we approach opaque geometry. This is what stops
	// the disc from painting across walls / step edges.
	float scene_depth = texture(depth_sampler, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_scene_depth = -view.z;
	float linear_self_depth = -view_pos.z;
	float depth_diff = linear_scene_depth - linear_self_depth;
	float depth_fade = clamp(depth_diff / max(depth_fade_distance, 0.001), 0.0, 1.0);

	float alpha = clamp(n * radial * intensity * depth_fade, 0.0, 1.0);

	ALBEDO = fog_color.rgb;
	// Self-emission so the fog reads in dark zones — proximity lighting
	// will still dim it via the standard render path. Scaled down so the
	// whole effect doesn't blow out at high tier.
	EMISSION = fog_color.rgb * alpha * 0.6;
	ALPHA = alpha * fog_color.a;
}
