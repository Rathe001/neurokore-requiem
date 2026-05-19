shader_type canvas_item;

uniform float border_width : hint_range(0.0, 8.0) = 2.0;
uniform float border_softness : hint_range(0.001, 0.1) = 0.01;
uniform vec4 border_color : source_color = vec4(0.15, 0.5, 0.15, 0.6);
uniform vec4 bg_color : source_color = vec4(0.04, 0.05, 0.04, 0.95);
uniform vec4 path_color : source_color = vec4(0.25, 0.28, 0.25, 1.0);
// Faded floor tint for "seen but not entered" pieces. Picked between
// bg_color and path_color so the eye reads three distinct states (void /
// previewed / explored) at a glance.
uniform vec4 seen_color : source_color = vec4(0.12, 0.14, 0.12, 1.0);
uniform float brightness_threshold : hint_range(0.0, 1.0) = 0.08;
uniform float brightness_smoothing : hint_range(0.01, 0.3) = 0.06;
// Texture luminance above this picks path_color (full), below picks
// seen_color (faded). Painter encodes state via per-pixel luminance: void=0,
// seen≈0.20, explored≈0.53.
uniform float seen_threshold : hint_range(0.0, 1.0) = 0.32;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

// UV panning for baked minimap: offset and scale control which portion of the
// full-map texture is visible inside the circle.
uniform vec2 uv_offset = vec2(0.0, 0.0);
uniform float uv_scale = 1.0;
// Rotates the SAMPLING direction inside the circle. The bake itself
// is top-down (axis-aligned room rectangles); rotating here lets us
// display an iso-aligned view (-PI/4 ≈ -45° matches the (4,14,4)
// game camera) without re-rasterizing. Pan still uses top-down world
// X/Z axes — the shader rotation only affects how the centered UV
// fans out around the player.
uniform float rotation_radians = 0.0;

// Standard Rec. 709 luminance weights.
const vec3 LUMINANCE_WEIGHTS = vec3(0.299, 0.587, 0.114);

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	// Hard circle clip.
	if (dist > 1.0) {
		discard;
	}

	// Remap UV through offset/scale so we pan across the baked texture.
	// Rotate the centered UV first so the visible world is iso-aligned;
	// uv_offset is added AFTER rotation so the player stays at the
	// circle's centre regardless of rotation.
	vec2 centered_uv = UV - 0.5;
	float rc = cos(rotation_radians);
	float rs = sin(rotation_radians);
	vec2 rotated_uv = vec2(rc * centered_uv.x - rs * centered_uv.y, rs * centered_uv.x + rc * centered_uv.y);
	vec2 map_uv = rotated_uv * uv_scale + 0.5 + uv_offset;

	// Sample the texture at the panned UV. Out-of-bounds shows bg_color.
	vec4 tex;
	if (map_uv.x < 0.0 || map_uv.x > 1.0 || map_uv.y < 0.0 || map_uv.y > 1.0) {
		tex = bg_color;
	} else {
		tex = texture(TEXTURE, map_uv);
	}

	float lum = dot(tex.rgb, LUMINANCE_WEIGHTS);
	// Two-stage gate: t_visible ramps bg→seen at brightness_threshold,
	// t_full ramps seen→path at seen_threshold. Pixels at low luminance
	// (~0.20) land in the seen band; high-luminance pixels (~0.53) reach
	// path_color.
	float t_visible = smoothstep(brightness_threshold, brightness_threshold + brightness_smoothing, lum);
	float t_full = smoothstep(seen_threshold, seen_threshold + brightness_smoothing, lum);
	vec3 final_rgb = mix(bg_color.rgb, seen_color.rgb, t_visible);
	final_rgb = mix(final_rgb, path_color.rgb, t_full);

	// Border ring.
	float border_t = smoothstep(1.0 - border_width * border_softness, 1.0, dist);
	final_rgb = mix(final_rgb, border_color.rgb, border_t);

	float base_alpha = mix(bg_color.a, 1.0, max(t_visible, border_t));
	COLOR = vec4(final_rgb, base_alpha * opacity);
}
