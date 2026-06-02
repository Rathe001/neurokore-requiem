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
render_mode blend_mix, depth_draw_never, cull_back;

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

// Two-color density gradient. Pushed almost to black — the user
// wants pools that read as "almost black, just barely red." Even
// these tiny RGB values amplify visibly through PBR diffuse +
// specular on lit floor.
//   fresh_color  = THIN/edge tint (very dark red-brown stain)
//   dried_color  = DENSE/center tint (near-black, faintest red hint)
// "Almost black, barely red" — confirmed via the #000000 diagnostic
// that the visible blood color now sources cleanly from these
// uniforms (the previous "bright red even at near-black" was the
// render_priority sort bug, fixed in liquid_layer.gd).
// Very small RGB values now produce subtle dark stains, not the
// amplified pink wash the broken sort order was producing.
//   fresh_color = THIN/edge tint (dark blood, faint red hint)
//   dried_color = DENSE/core tint (near-black, barely-there red)
uniform vec4 fresh_color : source_color = vec4(0.14, 0.030, 0.042, 1.0);
uniform vec4 dried_color : source_color = vec4(0.062, 0.013, 0.020, 1.0);
uniform float age : hint_range(0.0, 1.0) = 0.0;
// Shapes the thin→dense ramp.
uniform float density_power : hint_range(0.3, 4.0) = 0.9;
// Coverage value at which we hit "fully dense". Wide blend zone so
// the thin/dense gradient is spread across many pixels and reads as
// a smooth darkening rather than a visible shoulder.
uniform float density_full : hint_range(0.2, 2.0) = 1.6;
// Maximum opacity that dense regions reach. Dense core fully opaque
// so the visible color is exactly the painted blood (no floor
// texture bleeding through the densest blood patches).
uniform float density_opacity_max : hint_range(0.4, 1.0) = 0.98;
// Alpha floor at thinnest visible edge. Raised so even the thin
// perimeter reads as substantially opaque — pools should look like
// continuous blood, not translucent wash through which the floor
// pattern is clearly visible.
uniform float alpha_min : hint_range(0.0, 1.0) = 0.88;

// Wet-look knobs back to PBR-driven. Dense core glossy (catches
// nearby lights as wet sheen) but the very dark ALBEDO above means
// PBR diffuse can't amplify the blood into bright red.
uniform float roughness : hint_range(0.0, 1.0) = 0.22;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.06;
uniform float noise_scale : hint_range(0.5, 32.0) = 5.0;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.40;
// Brightness bias on the multiplied result. Dropped to 0.25 — the
// multiply-stain (lit floor × red tint) was lifting the perimeter
// into visible red despite the very dark colors. At 0.25 the
// multiply contribution is barely perceptible; the visible blood
// color comes almost entirely from the painted solid color below.
uniform float stain_brightness : hint_range(0.0, 3.0) = 0.25;

// Coverage gating. Threshold kept low so small droplet stamps
// (per-hit spray) aren't entirely eaten — at 0.04 a 5-10px stamp
// only kept its center pixel, making individual drops invisible.
uniform float coverage_threshold : hint_range(0.0, 0.5) = 0.015;
// Wider edge softness now that we want a perceptible pink translucent
// halo at the perimeter (the lighter edges visible in reference photos).
uniform float edge_softness : hint_range(0.0, 0.3) = 0.08;
uniform float coverage_cap : hint_range(1.0, 4.0) = 1.0;
// Base solid opacity. Pushed further up: even the thinnest edge is
// mostly painted solid (= our near-black blood color) rather than
// multiply-stain (= lit floor lifted by red tint). Dense core goes
// nearly fully painted.
uniform float solid_opacity : hint_range(0.0, 1.0) = 0.65;

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

	// Two-octave noise normal map for the wet-sheen surface
	// perturbation. PBR specular hits this perturbed surface at the
	// camera angle, giving small bright glints over the dense core.
	vec2 n_uv1 = UV * noise_scale;
	vec2 n_uv2 = UV * noise_scale * 2.3 + vec2(13.7, 5.1);
	vec3 n1 = texture(surface_noise, n_uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(surface_noise, n_uv2).rgb * 2.0 - 1.0;
	vec3 n_mixed = normalize(n1 * 0.6 + n2 * 0.4);
	NORMAL_MAP = vec3(n_mixed.xy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_strength * mix(0.0, 1.0, density);

	ALBEDO = stained;
	// Edges very matte (no spec pickup → can't brighten under
	// overhead lights), dense core glossy (catches nearby lights).
	ROUGHNESS = mix(0.92, roughness, density);
	METALLIC = 0.0;
	SPECULAR = specular_intensity * mix(0.0, 1.0, density);
	// ALPHA density-driven: thin areas fade transparent, dense areas
	// opaque. Perimeter smoothstep gates the discard anti-aliasing.
	ALPHA = alpha * mix(alpha_min, 1.0, density);
}
