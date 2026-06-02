// Liquid surface shader — reads a SubViewport texture as a coverage mask
// and renders it as a PBR liquid with animated normals + Fresnel-driven
// specular highlights. The mask comes from a persistent
// render-target SubViewport into which the gameplay scripts stamp soft
// alpha blobs at world coordinates (LiquidLayer.stamp(...)). Overlapping
// stamps accumulate additively in the mask, producing seamless merged
// surfaces with no per-stamp silhouette edges.
//
// One shader covers all fluid types — uniforms drive the look so blood,
// oil, water, etc. share a single renderer.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// SubViewport coverage mask. Alpha = liquid presence (0 = none, 1 = full).
// Sampled with linear filtering so stamps' soft alpha blends smoothly
// where they overlap.
uniform sampler2D liquid_mask : hint_default_black, filter_linear, repeat_disable;

// Procedural noise driving the animated surface normal — sampled at two
// frequencies + drifting offsets so the surface shimmers like water.
uniform sampler2D surface_noise : hint_normal, filter_linear, repeat_enable;

// Per-fluid look. Fresh = freshly-spilled color; dried = aged color.
// Aging is currently a global tween (uniform-driven) rather than per-
// pixel timestamp; that's a Phase 2 upgrade if we want crime-scene
// realism where individual pools age independently.
uniform vec4 fresh_color : source_color = vec4(0.62, 0.04, 0.04, 1.0);
uniform vec4 dried_color : source_color = vec4(0.28, 0.08, 0.08, 1.0);
uniform float age : hint_range(0.0, 1.0) = 0.0;

// Surface look knobs. Roughness is the BIG one for the "wet" read —
// 0.2-0.4 gives glossy reflection, 0.8+ goes matte.
uniform float roughness : hint_range(0.0, 1.0) = 0.32;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.45;
uniform float noise_scale : hint_range(0.5, 32.0) = 6.0;
uniform float noise_drift_speed : hint_range(0.0, 1.0) = 0.04;

// Alpha gate. Mask values below this discard the fragment — keeps the
// floor plane invisible where there's no liquid. 0.04 is just above
// the noise floor of the SubViewport additive blend.
uniform float coverage_threshold : hint_range(0.0, 0.5) = 0.04;

// How sharply the visible edge falls off after the threshold.
// 0 = hard binary edge, higher = softer feather.
uniform float edge_softness : hint_range(0.0, 0.3) = 0.05;

void fragment() {
	float coverage = texture(liquid_mask, UV).a;
	if (coverage < coverage_threshold) {
		discard;
	}
	// Smooth edge from coverage_threshold up to threshold + softness.
	float edge_alpha = smoothstep(coverage_threshold, coverage_threshold + edge_softness, coverage);

	// Two-octave animated noise → perturbed normal.
	// Drift at different speeds so the two layers never cleanly align,
	// keeping the surface non-repetitive.
	vec2 n_uv1 = UV * noise_scale + vec2(TIME * noise_drift_speed, TIME * noise_drift_speed * 0.7);
	vec2 n_uv2 = UV * noise_scale * 2.3 + vec2(TIME * noise_drift_speed * -0.5, TIME * noise_drift_speed * 0.9);
	vec3 n1 = texture(surface_noise, n_uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(surface_noise, n_uv2).rgb * 2.0 - 1.0;
	vec3 n_mixed = normalize(n1 * 0.6 + n2 * 0.4);
	NORMAL_MAP = vec3(n_mixed.xy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_strength;

	// Albedo lerps from fresh → dried over the global age uniform.
	vec3 albedo = mix(fresh_color.rgb, dried_color.rgb, age);
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = edge_alpha;
}
