shader_type canvas_item;

// Death-screen glitch effect. Horizontal slice displacement, occasional
// channel drops, and rare bright tear lines. Tuned subtly — the death
// screen's red overlay sits on top, so the glitch reads as movement and
// distortion behind the UI, not as a foreground effect.
//
// Driven by death_glitch_overlay.gd. The overlay sits at CanvasLayer 100
// (below the DeathScreen at 110), and the death screen's red tint is
// translucent, so the glitch reads through the tint underneath the UI.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
// 0 = passthrough, 1 = full glitch. The final result is mixed back over
// the unmodified screen at this ratio, so a lower value pulls every
// glitch artifact (slice offsets, channel drops, tear lines) closer to
// the original frame.
uniform float intensity : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	vec3 original = texture(screen_texture, SCREEN_UV).rgb;
	vec2 uv = SCREEN_UV;
	// 30 horizontal bands, re-seeded ~6× per second.
	float band = floor(uv.y * 30.0);
	float seed_t = floor(TIME * 6.0);
	float band_seed = fract(sin(band * 12.34 + seed_t) * 43758.5453);
	float offset = 0.0;
	if (band_seed > 0.88) {
		offset = (band_seed - 0.88) * 0.25 - 0.015;
	}
	uv.x += offset;
	vec3 col = texture(screen_texture, uv).rgb;
	// Channel drops: ~4% of bands lose red, dimmer than before.
	float ch_drop = fract(sin(band * 7.123 + floor(TIME * 9.0)) * 43758.5453);
	if (ch_drop > 0.96) {
		col.r *= 0.2;
	}
	// Tear lines: rare, dimmer (gray instead of pure white), thinner.
	float tear_t = floor(TIME * 2.0);
	float tear_active = fract(sin(tear_t * 5.67) * 43758.5453);
	if (tear_active > 0.88) {
		float tear_y = fract(sin(tear_t * 99.0) * 43758.5453);
		if (abs(uv.y - tear_y) < 0.0025) {
			col = vec3(0.65);
		}
	}
	// Mix the glitched result back over the original screen so the effect
	// is present but not dominant. Lowering `intensity` pulls every glitch
	// artifact closer to passthrough.
	col = mix(original, col, intensity);
	COLOR = vec4(col, 1.0);
}
