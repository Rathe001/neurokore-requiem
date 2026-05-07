shader_type canvas_item;

// Multi-mode screen filter. One shader, one fullscreen ColorRect, one
// overlay node — picks behavior at runtime via the `mode` uniform so
// flipping filters from the debug menu costs nothing more than a uniform
// write.
//
// Mode IDs are duplicated in retro_filter_overlay.gd as RetroMode.*
// constants. Keep the two in sync when adding/removing modes.
//   0  OFF            — passthrough
//   1  VHS            — chromatic split + scanlines + scanline jitter
//   2  SECURITY_CAM   — desaturated, scanlines, vignette, drop-frame
//   3  NIGHT_VISION   — green tint, brightness boost, grain
//   4  THERMAL        — color-remap by luminance (blue → red gradient)
//   5  CONCUSSED      — slow UV wobble + chromatic + heavy vignette
//   6  DRUNK          — sine UV warp + soft blur + sickly green tint
//   7  LOW_HP         — desaturate + pulsing red vignette
//   8  HALLUCINATION  — radial swirl + chromatic + breathing brightness
//   9  GLITCH         — horizontal slice displacement + channel drops
//   10 NOIR           — desaturate, crush contrast, vignette, grain
//   11 INVERTED       — flat color invert
//
// Godot's GDShader does NOT allow `return` inside fragment(); the whole
// shader is a straight-line if/else-if cascade that ends at one COLOR write.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform int mode = 0;
uniform float vhs_chroma = 0.004;

float luminance(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

vec3 thermal_map(float t) {
	// Stepped gradient: dark blue → cyan → green → yellow → red → white-hot.
	vec3 c0 = vec3(0.02, 0.02, 0.30);
	vec3 c1 = vec3(0.00, 0.45, 0.85);
	vec3 c2 = vec3(0.05, 0.85, 0.20);
	vec3 c3 = vec3(1.00, 0.95, 0.10);
	vec3 c4 = vec3(1.00, 0.20, 0.00);
	vec3 c5 = vec3(1.00, 1.00, 1.00);
	if (t < 0.20) return mix(c0, c1, t / 0.20);
	if (t < 0.40) return mix(c1, c2, (t - 0.20) / 0.20);
	if (t < 0.60) return mix(c2, c3, (t - 0.40) / 0.20);
	if (t < 0.80) return mix(c3, c4, (t - 0.60) / 0.20);
	return mix(c4, c5, (t - 0.80) / 0.20);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec3 col = vec3(0.0);

	if (mode == 0) {
		col = texture(screen_texture, uv).rgb;
	} else if (mode == 1) {
		// VHS — slow horizontal jitter + RGB split + scanlines.
		float roll = sin((uv.y + TIME * 0.05) * 80.0) * 0.0015;
		uv.x += roll;
		float r = texture(screen_texture, uv + vec2(vhs_chroma, 0.0)).r;
		float g = texture(screen_texture, uv).g;
		float b = texture(screen_texture, uv - vec2(vhs_chroma, 0.0)).b;
		col = vec3(r, g, b);
		float scan = sin(uv.y * res.y * 3.14159);
		col *= mix(1.0, scan * scan, 0.35);
	} else if (mode == 2) {
		// SECURITY CAMERA — quantized "frame" updates, mostly grayscale,
		// scanlines, vignette, grain, occasional micro-jitter on Y.
		float frame = floor(TIME * 6.0);
		float jitter_seed = fract(sin(frame * 12.345) * 43758.5453);
		uv.y += (jitter_seed - 0.5) * 0.0025;
		col = texture(screen_texture, uv).rgb;
		float lum = luminance(col);
		col = mix(vec3(lum), col, 0.18) * 0.85;
		float n = rand(uv * res + vec2(frame, 0.0)) * 0.10;
		col += n - 0.05;
		float scan = sin(uv.y * res.y * 1.5);
		col *= 0.85 + 0.15 * scan;
		float v = 1.0 - smoothstep(0.4, 1.0, length(uv - 0.5) * 1.4);
		col *= v;
	} else if (mode == 3) {
		// NIGHT VISION — luminance pushed into the green channel,
		// midtones boosted, grainy, soft circular vignette.
		col = texture(screen_texture, uv).rgb;
		float lum = pow(luminance(col), 0.6);
		col = vec3(0.04, lum * 1.35, 0.08);
		float n = rand(uv * res + vec2(TIME * 50.0, 0.0)) * 0.14;
		col += vec3(0.0, n - 0.07, 0.0);
		float v = 1.0 - smoothstep(0.5, 1.0, length(uv - 0.5) * 1.3);
		col *= v;
	} else if (mode == 4) {
		// THERMAL — luminance → false-color gradient. Detail is intentionally
		// crushed: thermal cameras don't see textures, only heat.
		col = texture(screen_texture, uv).rgb;
		float lum = clamp(luminance(col), 0.0, 1.0);
		col = thermal_map(lum);
	} else if (mode == 5) {
		// CONCUSSED — slow low-frequency wobble, slight RGB split, heavy
		// vignette. Reads as "I just got hit hard."
		float wob_x = sin(TIME * 1.2 + uv.y * 5.0) * 0.005;
		float wob_y = cos(TIME * 0.9 + uv.x * 5.0) * 0.005;
		uv += vec2(wob_x, wob_y);
		float r = texture(screen_texture, uv + vec2(0.003, 0.0)).r;
		float g = texture(screen_texture, uv).g;
		float b = texture(screen_texture, uv - vec2(0.003, 0.0)).b;
		col = vec3(r, g, b);
		float v = 1.0 - smoothstep(0.30, 0.95, length(uv - 0.5) * 1.4);
		col *= v;
	} else if (mode == 6) {
		// DRUNK / POISONED — sine UV warp, 5-tap blur, sickly green tint.
		float wx = sin(uv.y * 12.0 + TIME * 1.5) * 0.008;
		float wy = cos(uv.x * 8.0 + TIME * 1.2) * 0.008;
		uv += vec2(wx, wy);
		vec3 c0 = texture(screen_texture, uv).rgb;
		vec3 c1 = texture(screen_texture, uv + vec2(0.003, 0.0)).rgb;
		vec3 c2 = texture(screen_texture, uv - vec2(0.003, 0.0)).rgb;
		vec3 c3 = texture(screen_texture, uv + vec2(0.0, 0.003)).rgb;
		vec3 c4 = texture(screen_texture, uv - vec2(0.0, 0.003)).rgb;
		col = (c0 + c1 + c2 + c3 + c4) / 5.0;
		col = mix(col, col * vec3(0.7, 1.10, 0.6), 0.5);
	} else if (mode == 7) {
		// LOW HP / BLEED-OUT — desaturate scene, pulse red on the edges.
		col = texture(screen_texture, uv).rgb;
		float lum = luminance(col);
		col = mix(vec3(lum), col, 0.30);
		float pulse = 0.5 + 0.5 * sin(TIME * 2.5);
		float d = length(uv - 0.5) * 2.0;
		float redmask = smoothstep(0.4, 1.2, d) * (0.5 + 0.5 * pulse);
		col = mix(col, vec3(0.6, 0.0, 0.0), redmask * 0.7);
	} else if (mode == 8) {
		// HALLUCINATION — radial-swirl UV warp + chromatic separation +
		// breathing brightness. Designed to feel actively wrong.
		vec2 c = uv - 0.5;
		float r_dist = length(c);
		float angle = atan(c.y, c.x);
		angle += sin(r_dist * 8.0 - TIME * 0.8) * 0.15;
		vec2 swirl = vec2(cos(angle), sin(angle)) * r_dist + 0.5;
		uv = mix(uv, swirl, 0.4);
		float chroma = 0.008 + 0.004 * sin(TIME * 0.7);
		float r = texture(screen_texture, uv + vec2(chroma, chroma)).r;
		float g = texture(screen_texture, uv + vec2(-chroma, 0.0)).g;
		float b = texture(screen_texture, uv + vec2(0.0, -chroma)).b;
		col = vec3(r, g, b);
		col *= 0.85 + 0.15 * sin(TIME * 1.8);
	} else if (mode == 9) {
		// GLITCH — quantize Y into bands; high-seed bands shift
		// horizontally; some bands drop the red channel; rare bright
		// horizontal tear line on a slow timer.
		float band = floor(uv.y * 30.0);
		float band_seed = fract(sin(band * 12.34 + floor(TIME * 8.0)) * 43758.5453);
		float offset = 0.0;
		if (band_seed > 0.85) {
			offset = (band_seed - 0.85) * 0.4 - 0.03;
		}
		uv.x += offset;
		col = texture(screen_texture, uv).rgb;
		float ch_drop = fract(sin(band * 7.123 + floor(TIME * 12.0)) * 43758.5453);
		if (ch_drop > 0.95) {
			col.r = 0.0;
		}
		float tear_t = floor(TIME * 3.0);
		float tear_active = fract(sin(tear_t * 5.67) * 43758.5453);
		if (tear_active > 0.90) {
			float tear_y = fract(sin(tear_t * 99.0) * 43758.5453);
			if (abs(uv.y - tear_y) < 0.0035) {
				col = vec3(1.0);
			}
		}
	} else if (mode == 10) {
		// NOIR — full desaturate, contrast crush, vignette, fine grain.
		col = texture(screen_texture, uv).rgb;
		float lum = smoothstep(0.10, 0.90, luminance(col));
		col = vec3(lum);
		float n = rand(uv * res + vec2(TIME, 0.0)) * 0.06;
		col += n - 0.03;
		float v = 1.0 - smoothstep(0.35, 1.0, length(uv - 0.5) * 1.3);
		col *= v;
	} else if (mode == 11) {
		// INVERTED — flat color invert.
		col = 1.0 - texture(screen_texture, uv).rgb;
	}

	COLOR = vec4(col, 1.0);
}
