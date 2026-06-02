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

// Two-color density gradient driving realism.
//   fresh_color  = THIN/edge tint  (pinkish red, translucent perimeter)
//   dried_color  = DENSE/center tint (near-black burgundy, opaque core)
// The shader interpolates between them by the mask's local coverage
// value, so the same blob naturally reads pink-stained at the edges
// and dark/almost-opaque at the center — matching how real blood
// pools concentrate (cf. reference photos: thin perimeter, near-black
// dense pool surface). `age` desaturates the dense color further as
// the pool dries.
uniform vec4 fresh_color : source_color = vec4(0.55, 0.15, 0.16, 1.0);
uniform vec4 dried_color : source_color = vec4(0.08, 0.02, 0.03, 1.0);
uniform float age : hint_range(0.0, 1.0) = 0.0;
// Shapes the thin→dense ramp. >1 keeps more of the splat in the thin
// tint band (only the densest core goes dark); <1 pulls dense color
// out earlier. 1.6 reads well across stamp sizes.
uniform float density_power : hint_range(0.3, 4.0) = 1.6;
// Where on the ramp [threshold..density_full] we hit "fully dense."
// Lowering pulls the dark center into smaller blobs; raising keeps
// edges pink across more of the stamp area.
uniform float density_full : hint_range(0.2, 2.0) = 0.7;
// Maximum opacity that dense regions reach. Even the densest pool
// keeps a hint of translucency at this cap so the wet sheen reads
// through. 0.92 ≈ "almost opaque, barely-there base material peek."
uniform float density_opacity_max : hint_range(0.4, 1.0) = 0.92;

// Wet-look knobs. The surface normal is STATIC (no time-driven drift)
// because real spilled blood doesn't ripple — the visible shimmer
// comes from camera + light angle changes hitting the static
// noise-perturbed surface, not from animated waves.
uniform float roughness : hint_range(0.0, 1.0) = 0.22;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.08;
uniform float noise_scale : hint_range(0.5, 32.0) = 5.0;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.55;
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
// Base solid opacity floor — even very thin edges get this minimum
// blend toward blood tint so they aren't pure multiply (which can
// disappear over dark surfaces). Dense areas scale UP from here
// toward density_opacity_max.
uniform float solid_opacity : hint_range(0.0, 1.0) = 0.10;

void fragment() {
	float raw_coverage = texture(liquid_mask, UV).a;
	if (raw_coverage < coverage_threshold) {
		discard;
	}
	float coverage = min(raw_coverage, coverage_cap);
	// Smooth alpha falloff at the perimeter (hides the discard
	// boundary and gives the edge a pink-translucent halo).
	float alpha = smoothstep(coverage_threshold, coverage_threshold + edge_softness, coverage);
	// Density factor — 0 at the splat edge, 1 in the saturated core.
	// Drives both the color ramp (thin→dense) and the opacity ramp
	// (translucent→nearly opaque).
	float density = pow(
		smoothstep(coverage_threshold, density_full, coverage),
		density_power
	);

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
	ROUGHNESS = mix(0.65, roughness, density);
	METALLIC = 0.0;
	SPECULAR = specular_intensity * mix(0.4, 1.0, density);
	ALPHA = alpha;
}
