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

// Two-color density gradient driving realism.
//   fresh_color  = THIN/edge tint  (dark burgundy stain, translucent)
//   dried_color  = DENSE/center tint (near-black, opaque core)
// The shader interpolates between them by mask coverage so the same
// blob reads as a translucent dark stain at the edges and an opaque
// near-black core. Thin color is intentionally darker than reference
// "fresh blood" pink — that pink only appears in real life where the
// blood is VERY thin (a fine spray); for stained surfaces it reads as
// dark red, not bright pink. `age` desaturates dense further as the
// pool dries.
uniform vec4 fresh_color : source_color = vec4(0.32, 0.08, 0.10, 1.0);
uniform vec4 dried_color : source_color = vec4(0.06, 0.015, 0.025, 1.0);
uniform float age : hint_range(0.0, 1.0) = 0.0;
// Shapes the thin→dense ramp.
uniform float density_power : hint_range(0.3, 4.0) = 0.9;
// Coverage value at which we hit "fully dense". Raised vs. 0.85 to
// widen the blend zone — the dense/thin transition is now spread
// across more pixels so the boundary reads as a smooth gradient
// rather than a visible shoulder.
uniform float density_full : hint_range(0.2, 2.0) = 1.25;
// Maximum opacity that dense regions reach. Even the densest pool
// keeps a hint of translucency at this cap so the wet sheen reads
// through. 0.92 ≈ "almost opaque, barely-there base material peek."
uniform float density_opacity_max : hint_range(0.4, 1.0) = 0.92;
// Alpha floor at the thinnest visible edge. Raised from 0.0 so small
// per-hit droplets (which never accumulate enough coverage to reach
// dense) stay readable. Combined with the now-darker fresh_color,
// thin areas read as faint dark stain rather than the bright pink
// ring the previous palette produced at higher alpha floors.
uniform float alpha_min : hint_range(0.0, 0.5) = 0.32;

// Wet-look knobs. The surface normal is STATIC (no time-driven drift)
// because real spilled blood doesn't ripple — the visible shimmer
// comes from camera + light angle changes hitting the static
// noise-perturbed surface, not from animated waves.
// normal_strength + specular dialed down so highlights read as a
// subtle wet sheen instead of glass-bright reflections.
uniform float roughness : hint_range(0.0, 1.0) = 0.26;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.04;
uniform float noise_scale : hint_range(0.5, 32.0) = 5.0;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.35;
// Brightness bias on the multiplied result. Pure mul (1.0×) leaves
// the stain very dark in shadowed rooms; bumping slightly above 1
// lifts the stain into visible-red territory without losing the
// "absorbed into the surface" read.
uniform float stain_brightness : hint_range(0.5, 3.0) = 2.0;

// Coverage gating. Threshold kept low so small droplet stamps
// (per-hit spray) aren't entirely eaten — at 0.04 a 5-10px stamp
// only kept its center pixel, making individual drops invisible.
uniform float coverage_threshold : hint_range(0.0, 0.5) = 0.015;
// Wider edge softness now that we want a perceptible pink translucent
// halo at the perimeter (the lighter edges visible in reference photos).
uniform float edge_softness : hint_range(0.0, 0.3) = 0.08;
uniform float coverage_cap : hint_range(1.0, 4.0) = 1.0;
// Base solid opacity at the thinnest edge. 0 = pure multiply-stain
// at the perimeter (wall texture fully shows through, just blood-
// tinted). Dense areas scale UP from here toward density_opacity_max.
uniform float solid_opacity : hint_range(0.0, 1.0) = 0.0;

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
	// Noise modulation, gated by inverse density: edges (density < ~0.4)
	// get the full ±strength variation for organic mottled silhouettes;
	// dense core (density > ~0.85) gets almost none so it reads as a
	// smooth continuous dark pool rather than a stippled dot pattern.
	float noise = texture(shape_noise, UV * shape_noise_scale).r;
	float edge_factor = 1.0 - smoothstep(0.4, 0.85, density);
	float effective_strength = shape_noise_strength * edge_factor;
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

	// Two-octave STATIC noise → perturbed normal for the wet shimmer.
	// No TIME term — spilled blood doesn't ripple. The shimmer comes
	// from the camera/lights hitting the static perturbed normal.
	vec2 n_uv1 = UV * noise_scale;
	vec2 n_uv2 = UV * noise_scale * 2.3 + vec2(13.7, 5.1);
	vec3 n1 = texture(surface_noise, n_uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(surface_noise, n_uv2).rgb * 2.0 - 1.0;
	vec3 n_mixed = normalize(n1 * 0.6 + n2 * 0.4);
	NORMAL_MAP = vec3(n_mixed.xy * 0.5 + 0.5, 1.0);
	// Dense areas read wetter (more normal perturbation = more
	// visible specular highlights). Thin edges damp the sheen so
	// they don't look like polished plastic.
	NORMAL_MAP_DEPTH = normal_strength * mix(0.3, 1.0, density);

	ALBEDO = stained;
	// Edges feel drier/matte (high roughness), dense centers slick
	// (low roughness). Matches real wet pools — thin film is barely
	// glossy, deep pool reflects strongly.
	ROUGHNESS = mix(0.75, roughness, density);
	METALLIC = 0.0;
	SPECULAR = specular_intensity * mix(0.15, 1.0, density);
	// ALPHA is density-driven so thin/pink areas fade to transparent
	// and dense/dark areas stay opaque. `alpha` (the smoothstep) gates
	// the perimeter anti-aliasing — without it, the discard threshold
	// would pop as a hard 1-pixel line.
	ALPHA = alpha * mix(alpha_min, 1.0, density);
}
