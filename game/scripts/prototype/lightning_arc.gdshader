shader_type spatial;

// Adapted from the CC0 lightning shader at
// https://godotshaders.com/shader/lightning/ — original author's
// canvas_item version drew a vertical bolt; we reuse the same FBM /
// noise math on a 3D plane stretched between two world points so the
// arc reads as a chain link in iso view.
//
// The plane is laid flat (normal +Y world) and oriented so its local
// X axis spans the link's thickness and its local Z axis spans the
// link length. UV.x runs across thickness; we draw the bright bolt
// where UV.x is centered (abs(uv.x) low) and let the FBM displace
// the centerline to give the jagged-arc look.
//
// render_mode: unshaded so the arc isn't dimmed by lighting; default
// alpha-mix blend (no blend_add — blend_add was causing the arc to
// effectively disappear in some lighting / GPU combinations); depth_draw_never
// so transparent edges don't punch holes in geometry behind; cull_disabled
// so the arc reads from any camera angle.

render_mode unshaded, depth_draw_never, cull_disabled;

uniform vec3 effect_color: source_color = vec3(0.55, 0.85, 1.0);
// Original shader's defaults — 10 octaves give multi-scale detail
// from the coarse zigzag down to the finest tendril wiggles.
uniform int octave_count: hint_range(1, 20) = 10;
uniform float amp_start = 0.5;
uniform float amp_coeff = 0.5;
uniform float freq_coeff = 2.0;
// Original was 0.5 (slow water-like flow). 2.0 gives faster
// electric flicker without pushing into "frantic" territory.
uniform float speed = 2.0;
// Overall brightness multiplier. Tweens to 0 over the arc's lifetime
// so the spawned mesh fades out rather than vanishing in a frame.
uniform float intensity: hint_range(0.0, 5.0) = 1.0;
// World-space plane length (set by spawn_lightning_arc when the arc
// is created). The shader uses this to scale the FBM input along the
// plane's length axis so the noise pattern REPEATS per world unit
// instead of stretching across the full plane. Without this a 10m
// arc rendered the same low-frequency FBM as a 1m arc, just stretched
// horizontally — the bolt looked smeared on long links.
uniform float plane_length = 1.0;

float hash12(vec2 x) {
	return fract(cos(mod(dot(x, vec2(13.9898, 8.141)), 3.14)) * 43758.5453);
}

vec2 hash22(vec2 uv) {
	uv = vec2(dot(uv, vec2(127.1, 311.7)),
			  dot(uv, vec2(269.5, 183.3)));
	return 2.0 * fract(sin(uv) * 43758.5453123) - 1.0;
}

float noise(vec2 uv) {
	vec2 iuv = floor(uv);
	vec2 fuv = fract(uv);
	vec2 blur = smoothstep(0.0, 1.0, fuv);
	return mix(mix(dot(hash22(iuv + vec2(0.0, 0.0)), fuv - vec2(0.0, 0.0)),
				   dot(hash22(iuv + vec2(1.0, 0.0)), fuv - vec2(1.0, 0.0)), blur.x),
			   mix(dot(hash22(iuv + vec2(0.0, 1.0)), fuv - vec2(0.0, 1.0)),
				   dot(hash22(iuv + vec2(1.0, 1.0)), fuv - vec2(1.0, 1.0)), blur.x), blur.y) + 0.5;
}

float fbm(vec2 uv, int octaves) {
	float value = 0.0;
	float amplitude = amp_start;
	for (int i = 0; i < octaves; i++) {
		value += amplitude * noise(uv);
		uv *= freq_coeff;
		amplitude *= amp_coeff;
	}
	return value;
}

void fragment() {
	// Plane is vertical (standing up between source and target). UV.x
	// runs along the link length; UV.y runs across height. The bright
	// bolt centerline is horizontal (along uv.x), centered vertically,
	// so distance-from-bolt is measured in uv.y. FBM displacement on
	// TIME jiggles the centerline frame to frame for the jagged-arc
	// look.
	vec2 uv = 2.0 * UV - 1.0;
	// Scale the FBM input X axis by world-space plane length (in half-
	// units, since uv.x runs [-1, +1] across the full plane). This
	// makes the noise pattern repeat per world unit — a 10m arc gets
	// 10 noise cycles, a 1m arc gets 1, instead of every arc reading
	// as the same shape stretched to fit.
	vec2 fbm_input = vec2(uv.x * plane_length * 0.5, uv.y) + TIME * speed;
	uv += 2.0 * fbm(fbm_input, octave_count) - 1.0;
	float dist = abs(uv.y);
	// Original 1/dist falloff with the brightness floor raised. The
	// source shader hashed numerator from 0.0 to 0.05, which produced
	// dim-frame strobing where the bolt almost vanished — combined
	// with the small ceiling, the bolt never punched through bloom in
	// our scene. Bumped to mix(0.10, 0.25, hash) for a 5× brighter
	// peak with a guaranteed visible floor on every frame, plus a
	// 14× clamp ceiling so the centerline really pops in HDR.
	float numerator = mix(0.10, 0.25, hash12(vec2(TIME)));
	float brightness = numerator / max(dist, 0.005);
	brightness = clamp(brightness * intensity, 0.0, 14.0);
	// EMISSION pushed harder — multiplying by 1.5 over brightness
	// drives the hot core well into bloom range so the centerline
	// reads as a real light source against any background. ALBEDO
	// stays modest so the surrounding tendrils don't blow out.
	ALBEDO = effect_color * clamp(brightness * 0.4, 0.0, 1.0);
	EMISSION = effect_color * brightness * 1.5;
	ALPHA = clamp(brightness, 0.0, 1.0);
}
