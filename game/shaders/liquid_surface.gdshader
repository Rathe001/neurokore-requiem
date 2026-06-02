// Liquid surface shader — multiply-blend pass that DARKENS the floor
// beneath the liquid rather than painting over it. This is what real
// blood does: it absorbs into the surface, tinting whatever's there,
// not replacing it. The previous mix-blend version read as red paint
// because it overwrote the floor color entirely.
//
// One shader covers all fluid types — uniforms drive the look so
// blood, oil, water, etc. share a single renderer.
//
// Wet specular highlight is a separate concern. blend_mul doesn't
// participate in PBR lighting, so this shader is matte-only. A future
// second-pass overlay (additive spec on top of the stain) can add the
// wet read without breaking the multiply.
shader_type spatial;
// depth_draw_never: this is a multiply pass, we don't want to write
// the plane into the depth buffer (would block things drawn after it).
// Default depth TEST stays on so walls / characters / items in front
// of the floor plane occlude it properly — without depth test the
// plane was rendering over the entire scene.
render_mode blend_mul, depth_draw_never, cull_back, unshaded;

// SubViewport coverage mask. Alpha = liquid presence (0 = none, 1 = full).
uniform sampler2D liquid_mask : hint_default_black, filter_linear, repeat_disable;

// Per-fluid look. In multiply blending, these values get multiplied
// against the floor color underneath. Lower values = darker stain.
// Fresh blood = deeper red multiplier; dried = even darker, less
// saturated.
uniform vec4 fresh_color : source_color = vec4(0.50, 0.08, 0.08, 1.0);
uniform vec4 dried_color : source_color = vec4(0.22, 0.06, 0.06, 1.0);
uniform float age : hint_range(0.0, 1.0) = 0.0;

// Below this coverage value the pixel is discarded (no effect on floor).
uniform float coverage_threshold : hint_range(0.0, 0.5) = 0.04;
// How quickly the multiply fades in at the edge. Hard edge = 0.0,
// soft = 0.2+. Soft hides the boundary of overlapping stamps.
uniform float edge_softness : hint_range(0.0, 0.5) = 0.10;
// Caps the additive coverage mask. Without this, heavy stamp overlap
// pushes alpha well past 1.0 and the stain math gets weird.
uniform float coverage_cap : hint_range(1.0, 4.0) = 1.0;

void fragment() {
	float raw_coverage = texture(liquid_mask, UV).a;
	if (raw_coverage < coverage_threshold) {
		discard;
	}
	float coverage = min(raw_coverage, coverage_cap);
	// Smooth fade from threshold to threshold + softness — keeps edges
	// from hard-popping where the mask alpha just crosses threshold.
	float effect_strength = smoothstep(coverage_threshold, coverage_threshold + edge_softness, coverage);

	vec3 stain_color = mix(fresh_color.rgb, dried_color.rgb, age);
	// In blend_mul, ALBEDO is the per-channel multiplier applied to
	// what's already in the framebuffer (the floor). Lerp from white
	// (no effect = floor stays unchanged) to stain_color (full darken)
	// based on how strongly this pixel is covered. Result: the floor
	// gradually darkens toward red as you approach the pool's
	// interior, like blood soaked into the surface.
	ALBEDO = mix(vec3(1.0), stain_color, effect_strength);
	ALPHA = 1.0;
}
