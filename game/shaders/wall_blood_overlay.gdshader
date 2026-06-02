// Wall blood overlay — Phase 2 (texture sampling test).
// Quad samples a SubViewport mask passed as `mask`. If the alpha is
// above threshold, paint the masked color (currently white test);
// otherwise paint a debug background (green) so we can visually see
// the quad and confirm sampling works.
//
// Production version will: discard where coverage is 0, blend a
// blood-red stain over the wall behind via screen_texture, drive
// roughness/metallic for the wet look. None of that yet — this is
// just the binding-and-sampling proof.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, unshaded;

uniform sampler2D mask : filter_linear, repeat_disable, hint_default_black;

void fragment() {
	float a = texture(mask, UV).a;
	if (a > 0.05) {
		// Stamp area — tint toward white so it's obvious.
		ALBEDO = vec3(1.0, 1.0, 1.0);
	} else {
		// Empty mask area — debug green background. If the whole quad
		// is green after reload, the SubViewport is empty (stamp wasn't
		// drawn). If a white circle is visible, the SubViewport content
		// IS reaching the shader sampler from within the same subtree.
		ALBEDO = vec3(0.0, 0.6, 0.2);
	}
}
