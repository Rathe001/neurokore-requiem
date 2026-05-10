shader_type spatial;

// Acid-pool surface — inspired by the Gerstner-wave water shader at
// https://godotshaders.com/shader/water-shader-3d-godot-4-3/ but
// simplified for a small in-engine pool: no caustics array, no foam
// textures, no screen-space refraction. The full ocean shader needed
// six external sampler resources we don't ship and was hugely
// overpowered for a 4-tile glowing pit. This keeps the visual idea
// (flowing displaced surface + animated ripple + emission glow) and
// drops everything that needed bespoke art.
//
// Tuned for the pit_ooze case: the pool is bright-emissive (acid),
// has gentle vertex displacement (couple cm of swell), and uses
// procedural FBM for the ripple texture so brightness flickers
// across the surface like sloshing fluid.

render_mode cull_disabled;

uniform vec3 acid_color : source_color = vec3(0.15, 0.85, 0.2);
// Emission strength — same role as StandardMaterial3D.
// emission_energy_multiplier; theme writes pit_ooze_energy into it.
uniform float emission_energy = 2.5;
// Vertex-wave parameters. amplitude in world units; speed scales TIME.
// Default amplitude is intentionally small (~3cm peaks) so the surface
// reads as fluid without breaching the rim of a shallow pit.
uniform float wave_speed = 1.0;
uniform float wave_amplitude = 0.04;
// Fragment-ripple parameters. ripple_scale = how dense the noise
// pattern is; ripple_speed = how fast it flows across the surface.
uniform float ripple_scale = 6.0;
uniform float ripple_speed = 0.35;
// Alpha — pit ooze is opaque by default; expose so a future translucent
// variant (poison cloud, glowing fog) can dial it down.
uniform float pool_alpha : hint_range(0.0, 1.0) = 1.0;


// ── Procedural noise (no texture inputs) ─────────────────────────────────

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	// 5 octaves instead of 4 — the extra high-frequency layer breaks
	// up the grid pattern that the low octaves alone would expose.
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}


// Domain-warped FBM. Standard FBM evaluates noise at a regular grid
// position which lets the underlying value-noise cells show through as
// blocky rectangles. Domain warping perturbs the input position with
// a second noise field before sampling — the cell boundaries get
// stretched into curving organic shapes that no longer read as a grid.
// This is the classic IQ-style warp; 3 noise calls per pixel.
float fbm_warped(vec2 p, float t) {
	vec2 q = vec2(
		fbm(p + vec2(t * 0.5, 0.0)),
		fbm(p + vec2(0.0, t * 0.5) + vec2(5.2, 1.3))
	);
	return fbm(p + q * 2.0);
}


// ── Gerstner wave (single-component) ─────────────────────────────────────
// params.xy = direction (will be normalized), params.z = steepness,
// params.w = wavelength. Same structure as the source shader, just
// dropped from 8 stacked waves to 3 to keep the per-vertex math cheap
// for a horde-density level builder.

vec3 gerstner_wave(vec4 params, vec2 pos, float time) {
	float steepness = params.z;
	float wavelength = max(params.w, 0.1);
	float k = 2.0 * PI / wavelength;
	float c = sqrt(9.81 / k);
	vec2 d = normalize(params.xy);
	float f = k * (dot(d, pos) - c * time);
	float a = steepness / k;
	return vec3(d.x * (a * cos(f)), a * sin(f), d.y * (a * cos(f)));
}


void vertex() {
	float time = TIME * wave_speed;
	vec3 disp = vec3(0.0);
	// Higher steepness + wavelength than the source's ocean numbers —
	// scaled for a small in-engine pool where 5–10cm of swell reads
	// as obvious surface motion at iso angles. The ocean shader's
	// 0.04 steepness gave millimeter-scale displacement that was
	// invisible at our camera distance.
	disp += gerstner_wave(vec4( 1.0,  0.5, 0.20, 1.0), VERTEX.xz, time);
	disp += gerstner_wave(vec4(-0.7,  1.0, 0.15, 1.4), VERTEX.xz, time);
	disp += gerstner_wave(vec4( 0.3, -0.9, 0.12, 0.7), VERTEX.xz, time);
	// Only Y — the gerstner wave's X/Z push is the orbital motion
	// real ocean surfaces have, but at our scale it just distorts the
	// pit rim. Pure vertical bob keeps the pool inside its hole.
	VERTEX.y += disp.y * wave_amplitude;
}


void fragment() {
	// Two animated layers of domain-warped FBM, flowing in different
	// directions. Domain warping is what kills the "moving squares"
	// look — the warp call perturbs the input before the final FBM
	// sample, so the underlying value-noise grid never shows through.
	vec2 uv = UV * ripple_scale;
	float t = TIME * ripple_speed;
	float n1 = fbm_warped(uv + vec2(t, t * 0.7), t);
	float n2 = fbm_warped(uv * 1.3 - vec2(t * 0.5, t), t * 0.8);
	float ripple = clamp((n1 + n2) * 0.5, 0.0, 1.0);

	// High-contrast peak curve. The previous build modulated emission
	// by [0.5, 1.3] which is only 2.6× contrast — the brightness from
	// emission_energy 2.5 then washed everything to a uniform glow.
	// pow(ripple, 2.5) gives a low baseline with bright hotspots:
	// most of the surface is dim, but the wave peaks pop bright.
	float peak = pow(ripple, 2.5);

	// Analytical normal from the WARPED noise gradient. Sampling the
	// warped variant for the normal too means surface highlights bend
	// along the same swirly contours as the brightness, instead of
	// the bright spots floating against a flat-shaded grid.
	float eps = 0.04;
	float dx = fbm_warped(uv + vec2(eps, 0.0), t) - fbm_warped(uv - vec2(eps, 0.0), t);
	float dy = fbm_warped(uv + vec2(0.0, eps), t) - fbm_warped(uv - vec2(0.0, eps), t);
	vec3 perturbed_normal = normalize(vec3(-dx * 5.0, 1.0, -dy * 5.0));

	// Albedo carries a dim base color so the surface isn't pure black
	// when the ripple is in a trough; lighting + normal-mapping
	// produces the visible specular variation that reads as wave
	// shape. Emission is the brightness modulator: a low baseline
	// (so the surface isn't washed out) plus peak hotspots scaled
	// by emission_energy. 13× contrast between trough and peak.
	ALBEDO = acid_color * 0.18;
	EMISSION = acid_color * (0.15 + peak * emission_energy * 0.6);
	NORMAL = perturbed_normal;
	METALLIC = 0.4;
	ROUGHNESS = 0.15;
	ALPHA = pool_alpha;
}
