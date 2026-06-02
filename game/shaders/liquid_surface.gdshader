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

// Per-fluid look — multiplied against the floor underneath. Lower
// values = darker stain. Fresh blood = deep red multiplier; dried =
// even darker, less saturated.
uniform vec4 fresh_color : source_color = vec4(0.50, 0.10, 0.10, 1.0);
uniform vec4 dried_color : source_color = vec4(0.22, 0.07, 0.07, 1.0);
uniform float age : hint_range(0.0, 1.0) = 0.0;

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
uniform float stain_brightness : hint_range(0.5, 3.0) = 1.6;

// Coverage gating.
uniform float coverage_threshold : hint_range(0.0, 0.5) = 0.04;
uniform float edge_softness : hint_range(0.0, 0.3) = 0.08;
uniform float coverage_cap : hint_range(1.0, 4.0) = 1.0;

void fragment() {
	float raw_coverage = texture(liquid_mask, UV).a;
	if (raw_coverage < coverage_threshold) {
		discard;
	}
	float coverage = min(raw_coverage, coverage_cap);
	// Smooth alpha falloff at the perimeter (hides the discard
	// boundary which would otherwise pop as a hard line).
	float alpha = smoothstep(coverage_threshold, coverage_threshold + edge_softness, coverage);

	// Sample the floor underneath this fragment via screen-space and
	// multiply by the stain color. Result is a realistic absorbed
	// stain (the floor's tile pattern + lighting + shadows all show
	// through, just tinted blood-red).
	vec3 behind = texture(screen_tex, SCREEN_UV).rgb;
	vec3 stain_color = mix(fresh_color.rgb, dried_color.rgb, age);
	vec3 stained = behind * stain_color * stain_brightness;

	// Two-octave STATIC noise → perturbed normal for the wet shimmer.
	// No TIME term — spilled blood doesn't ripple. The shimmer comes
	// from the camera/lights hitting the static perturbed normal.
	vec2 n_uv1 = UV * noise_scale;
	vec2 n_uv2 = UV * noise_scale * 2.3 + vec2(13.7, 5.1);
	vec3 n1 = texture(surface_noise, n_uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(surface_noise, n_uv2).rgb * 2.0 - 1.0;
	vec3 n_mixed = normalize(n1 * 0.6 + n2 * 0.4);
	NORMAL_MAP = vec3(n_mixed.xy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_strength;

	// Output. ALBEDO is the stained-floor color (gets lit by PBR).
	// ROUGHNESS + SPECULAR + METALLIC drive the wet read.
	ALBEDO = stained;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = specular_intensity;
	ALPHA = alpha;
}
