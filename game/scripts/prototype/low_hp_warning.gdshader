shader_type canvas_item;

// Low-HP warning vignette. Pulsing red on the screen periphery, scales by
// `intensity` so the effect ramps in as HP drops further past the warning
// threshold. No desaturation, no center coverage — the player still needs
// to see what's killing them.
//
// Driven by low_hp_warning_overlay.gd, which sets `intensity` from the
// health_changed signal: 0.0 above the warning threshold, ramping to 1.0
// at zero HP.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;
	float pulse = 0.55 + 0.45 * sin(TIME * 3.5);
	// Distance to the nearest screen edge in UV space: 0 right at the edge,
	// 0.5 at the center. Using min-of-axes (not radial length) gives a
	// uniform-width rim instead of an elliptical vignette — covers a tight
	// band around the periphery and stays out of the play area entirely.
	float edge_dist = min(
		min(SCREEN_UV.x, 1.0 - SCREEN_UV.x),
		min(SCREEN_UV.y, 1.0 - SCREEN_UV.y)
	);
	// 0.10 = ~10% of the smaller screen dimension fades from full mask at
	// the edge to zero. Visible-red coverage works out to ~12% of screen.
	float mask = 1.0 - smoothstep(0.0, 0.10, edge_dist);
	float strength = mask * pulse * intensity * 0.65;
	col = mix(col, vec3(0.70, 0.05, 0.05), strength);
	COLOR = vec4(col, 1.0);
}
