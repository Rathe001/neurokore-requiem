// Liquid surface shader. Single pass that does BOTH:
//   (1) Multiplies the floor color underneath to produce a realistic
//       stain (blood darkens what's there rather than painting over),
//       via hint_screen_texture sampling.
//   (2) Adds PBR lighting on top so the surface reads as wet — low
//       roughness + animated noise normal gives a glistening highlight
//       that responds to scene lights.
//
// One shader covers all fluid types — uniforms drive the look so
// blood, oil, water, etc. share a single renderer.
shader_type spatial;
// `unshaded` bypasses PBR direct-light contributions so the floor
// blood's perceived brightness is exactly what ALBEDO outputs,
// independent of overhead lighting. Wet-sheen highlights are faked
// in fragment via noise sampling (since spec/roughness no-op here).
// Natural light response still comes through via the multiply-stain
// of SCREEN_TEX (which samples the already-lit floor underneath).
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

// What the shader needs to read:
// - liquid_mask:    the SubViewport coverage texture (where & how much liquid)
// - screen_tex:     what's already in the framebuffer where this fragment lands
//                   (= the floor + anything else rendered before this plane)
// - surface_noise:  procedural normal map for the wet-shimmer ripple
uniform sampler2D liquid_mask : hint_default_black, filter_linear, repeat_disable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D surface_noise : hint_normal, filter_linear, repeat_enable;
// Raw (non-normalmap) noise used to modulate density at the edges
// so blob silhouettes aren't smooth circles. shape_noise_scale kept
// low so the noise reads as large organic patches, not fine dots.
// Modulation strength is GATED by inverse density in fragment so
// the dense core stays smooth (continuous blood) while edges break
// up into organic mottled shapes.
uniform sampler2D shape_noise : hint_default_white, filter_linear, repeat_enable;
uniform float shape_noise_scale : hint_range(1.0, 64.0) = 5.0;
uniform float shape_noise_strength : hint_range(0.0, 1.0) = 0.55;

// Two-color density gradient. Kept narrow in value so thin → dense
// blends as a smooth darkening rather than a perceptible color jump.
//   fresh_color  = THIN/edge tint (already dark blood, just slightly
//                  more saturated than dense — reads as continuation,
//                  not a separate "halo" color)
//   dried_color  = DENSE/center tint (near-black core)
uniform vec4 fresh_color : source_color = vec4(0.18, 0.05, 0.07, 1.0)
;
uniform vec4 dried_color : source_color = vec4(0.05, 0.012, 0.020, 1.0);
uniform float age : hint_range(0.0, 1.0) = 0.0;
// Shapes the thin→dense ramp.
uniform float density_power : hint_range(0.3, 4.0) = 0.9;
// Coverage value at which we hit "fully dense". Wide blend zone so
// the thin/dense gradient is spread across many pixels and reads as
// a smooth darkening rather than a visible shoulder.
uniform float density_full : hint_range(0.2, 2.0) = 1.6;
// Maximum opacity that dense regions reach. Floor pool needs to
// read as substantially opaque blood at the core (matching how the
// wall blood already presents), so this is held high. Below 0.85
// the lit floor texture started bleeding through the dense core and
// reading as orange-red wash, not blood.
uniform float density_opacity_max : hint_range(0.4, 1.0) = 0.90;
// Alpha floor at thinnest visible edge. Floor pool reads as
// substantially opaque — even thin perimeter areas hide the floor
// pattern underneath, presenting as continuous blood rather than
// translucent wash. Required by the higher overhead light intensity.
uniform float alpha_min : hint_range(0.0, 0.5) = 0.70;

// Fake wet sheen — sampled from a high-frequency shape_noise pass,
// gated by density so only the dense core shows glints. Additive
// white-ish bumps on top of the dark painted blood ALBEDO. Pattern-
// based (no PBR specular) so the look is consistent regardless of
// overhead lighting.
uniform float sheen_intensity : hint_range(0.0, 0.5) = 0.18;
uniform float sheen_threshold : hint_range(0.3, 0.95) = 0.72;
// Kept for legacy material bindings — no-op under render_mode unshaded.
uniform float roughness : hint_range(0.0, 1.0) = 0.45;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.03;
uniform float noise_scale : hint_range(0.5, 32.0) = 5.0;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.18;
// Brightness bias on the multiplied result. Cranked all the way
// down: the floor was still reading pinkish because lit overhead
// surface × red tint × brightness amplified into bright red even
// at 0.95. 0.5 makes the multiply-stain barely brighten the
// underlying floor; the visible blood color now comes mostly from
// the painted solid_opacity blend below, not from the multiply.
uniform float stain_brightness : hint_range(0.5, 3.0) = 0.5;

// Coverage gating. Threshold kept low so small droplet stamps
// (per-hit spray) aren't entirely eaten — at 0.04 a 5-10px stamp
// only kept its center pixel, making individual drops invisible.
uniform float coverage_threshold : hint_range(0.0, 0.5) = 0.015;
// Wider edge softness now that we want a perceptible pink translucent
// halo at the perimeter (the lighter edges visible in reference photos).
uniform float edge_softness : hint_range(0.0, 0.3) = 0.08;
uniform float coverage_cap : hint_range(1.0, 4.0) = 1.0;
// Base solid opacity. Pushed up so even thin floor areas are mostly
// painted solid blood color (which is our actual dark blood) rather
// than multiply-stain (which the PBR pipeline re-lights into pink).
// Dense areas go nearly fully painted.
uniform float solid_opacity : hint_range(0.0, 1.0) = 0.45;

void fragment() {
	float raw_coverage = texture(liquid_mask, UV).a;
	if (raw_coverage < coverage_threshold) {
		discard;
	}
	float coverage = min(raw_coverage, coverage_cap);
	// Smooth alpha falloff at the perimeter (hides the discard
	// boundary and gives the edge a translucent halo).
	float alpha = smoothstep(coverage_threshold, coverage_threshold + edge_softness, coverage);
	// Density factor — 0 at the splat edge, 1 in the saturated core.
	// Modulated by a spatial noise so the thin/dense transition is
	// mottled rather than a smooth circle. Same noise drives the same
	// fragment every frame (static UV), so the organic shape is
	// stable, not flickering.
	float density = pow(
		smoothstep(coverage_threshold, density_full, coverage),
		density_power
	);
	// Two-octave noise modulation for watercolor-style internal
	// variation. Low-frequency layer gives large organic patches; the
	// high-frequency layer (×3.7) adds the fine marbled detail that
	// real pooled blood shows. Combined 70/30.
	float noise_lo = texture(shape_noise, UV * shape_noise_scale).r;
	float noise_hi = texture(shape_noise, UV * shape_noise_scale * 3.7 + vec2(7.3, 2.1)).r;
	float noise = noise_lo * 0.7 + noise_hi * 0.3;
	// Edge-gated: full noise at edges (mottled silhouette), but a
	// small NON-ZERO baseline in the dense core so the inside isn't
	// perfectly flat — gives the pool the watercolor-pigment marbling
	// look rather than a flat solid disk.
	float edge_factor = 1.0 - smoothstep(0.3, 0.95, density);
	float core_floor = 0.18;  // baseline modulation even in dense core
	float effective_strength = shape_noise_strength
		* (core_floor + (1.0 - core_floor) * edge_factor);
	float shape_mod = mix(1.0 - effective_strength, 1.0 + effective_strength, noise);
	density = clamp(density * shape_mod, 0.0, 1.0);

	// Color: thin (pinkish-red) at the edge → dense (near-black
	// burgundy) at the core. Age desaturates further as it dries.
	vec3 blood_color = mix(fresh_color.rgb, dried_color.rgb, density);
	blood_color *= mix(1.0, 0.7, age);

	// Multiply-stain pass: blood color × floor underneath. Edges
	// thus tint the floor pink rather than painting over it.
	vec3 behind = texture(screen_tex, SCREEN_UV).rgb;
	vec3 stained_mul = behind * blood_color * stain_brightness;
	// Opacity ramps with density — edges keep the multiply-stain
	// character, dense centers become nearly opaque painted blood.
	float opacity_here = mix(solid_opacity, density_opacity_max, density);
	vec3 stained = mix(stained_mul, blood_color, opacity_here);

	// Fake wet sheen — high-frequency shape_noise sample produces
	// small bright glints on the dense core. Pure additive contrib
	// independent of scene lighting; the visual cue for "wet slick"
	// under unshaded mode where PBR specular is unavailable.
	float sheen_n = max(
		texture(shape_noise, UV * shape_noise_scale * 2.7).r,
		texture(shape_noise, UV * shape_noise_scale * 6.3 + vec2(11.1, 4.7)).r
	);
	float sheen = smoothstep(sheen_threshold, 0.98, sheen_n) * density;
	stained += vec3(sheen * sheen_intensity);

	ALBEDO = stained;
	// ALPHA is density-driven so thin/pink areas fade to transparent
	// and dense/dark areas stay opaque. `alpha` (the smoothstep) gates
	// the perimeter anti-aliasing — without it, the discard threshold
	// would pop as a hard 1-pixel line.
	ALPHA = alpha * mix(alpha_min, 1.0, density);
}
