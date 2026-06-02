// Wall blood overlay — Phase 4 (discard where mask is empty).
// Same sampling path as Phase 2, but instead of painting a debug
// background where the mask is empty, the fragment DISCARDs so the
// wall underneath shows through. Only stamped regions paint blood
// red. Production version will multiply-stain over screen_texture
// + drive PBR for wet look — for now solid red proves the pipeline.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded;

uniform sampler2D mask : filter_linear, repeat_disable, hint_default_black;

void fragment() {
	float a = texture(mask, UV).a;
	if (a < 0.05) {
		// Wall behind shows through.
		discard;
	}
	ALBEDO = vec3(0.7, 0.08, 0.08);
}
