shader_type canvas_item;

uniform float border_width : hint_range(0.0, 8.0) = 2.0;
uniform float border_softness : hint_range(0.001, 0.1) = 0.01;
uniform vec4 border_color : source_color = vec4(0.15, 0.5, 0.15, 0.6);
uniform vec4 bg_color : source_color = vec4(0.04, 0.05, 0.04, 0.95);
uniform vec4 path_color : source_color = vec4(0.25, 0.28, 0.25, 1.0);
uniform float brightness_threshold : hint_range(0.0, 1.0) = 0.08;
uniform float brightness_smoothing : hint_range(0.01, 0.3) = 0.06;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

// Standard Rec. 709 luminance weights.
const vec3 LUMINANCE_WEIGHTS = vec3(0.299, 0.587, 0.114);

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	// Hard circle clip.
	if (dist > 1.0) {
		discard;
	}
	// Convert viewport texture to a simple floorplan:
	// dark background + light gray for visible surfaces.
	vec4 tex = COLOR;
	float lum = dot(tex.rgb, LUMINANCE_WEIGHTS);
	// Anything above the threshold is "walkable surface" -> path color.
	// Everything else is void -> background color.
	float t = smoothstep(brightness_threshold, brightness_threshold + brightness_smoothing, lum);
	vec3 final_rgb = mix(bg_color.rgb, path_color.rgb, t);

	// Border ring.
	float border_t = smoothstep(1.0 - border_width * border_softness, 1.0, dist);
	final_rgb = mix(final_rgb, border_color.rgb, border_t);

	float base_alpha = mix(bg_color.a, 1.0, max(t, border_t));
	COLOR = vec4(final_rgb, base_alpha * opacity);
}
