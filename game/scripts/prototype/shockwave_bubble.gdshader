shader_type spatial;

// Refraction-based shockwave bubble: a translucent expanding shell that bends
// the screen image behind it, similar to the heat-ripple compression wave a
// bomb produces in real life. No color tint — just distortion + a faint
// Fresnel rim that reads the leading edge of the wavefront.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float distortion : hint_range(0.0, 0.5) = 0.10;
uniform float chroma : hint_range(0.0, 0.05) = 0.014;
uniform float intensity : hint_range(0.0, 1.0) = 1.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.25;
uniform float rim_alpha_max : hint_range(0.0, 1.0) = 0.30;
uniform float body_alpha : hint_range(0.0, 1.0) = 0.02;

void fragment() {
	// Offset the screen sample by the surface normal projected into screen
	// space. Curvature gives stronger offsets at grazing angles, mimicking
	// light bending through compressed air.
	vec2 offset = NORMAL.xy * distortion * intensity;
	vec2 uv = clamp(SCREEN_UV + offset, vec2(0.0), vec2(1.0));

	// Per-channel UV offset → chromatic aberration along the wavefront.
	float a = chroma * intensity;
	vec3 col;
	col.r = texture(screen_tex, clamp(uv + vec2(a, 0.0), vec2(0.0), vec2(1.0))).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, clamp(uv - vec2(a, 0.0), vec2(0.0), vec2(1.0))).b;

	// Fresnel-like rim — the leading shell brightens at grazing angles, so
	// the wavefront reads as a visible boundary rather than just a haze.
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, 3.0);

	ALBEDO = col + vec3(rim * rim_strength * intensity);
	ALPHA = mix(body_alpha, rim_alpha_max, rim) * intensity;
}
