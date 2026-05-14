shader_type canvas_item;

// Low-HP warning vignette. Pulsing red on the screen periphery, scales by
// `intensity` so the effect ramps in as HP drops further past the warning
// threshold. No desaturation, no center coverage — the player still needs
// to see what's killing them.
//
// Driven by low_hp_warning_overlay.gd, which sets `intensity` from the
// health_changed signal: 0.0 above the warning threshold, ramping to 1.0
// at zero HP.
//
// Uses alpha blending instead of screen_texture so the overlay composes
// cleanly with other post-process overlays on the same canvas layer.

uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float pulse = 0.55 + 0.45 * sin(TIME * 3.5);
	// Distance to the nearest screen edge in UV space: 0 right at the edge,
	// 0.5 at the center. Using min-of-axes (not radial length) gives a
	// uniform-width rim instead of an elliptical vignette — covers a tight
	// band around the periphery and stays out of the play area entirely.
	float edge_dist = min(
		min(UV.x, 1.0 - UV.x),
		min(UV.y, 1.0 - UV.y)
	);
	// 0.12 = ~12% of the smaller screen dimension fades from full mask at
	// the edge to zero. Slightly wider than the original 0.10 to be more
	// visible at low intensities.
	float mask = 1.0 - smoothstep(0.0, 0.12, edge_dist);
	float strength = mask * pulse * intensity * 0.75;
	COLOR = vec4(0.70, 0.05, 0.05, strength);
}
