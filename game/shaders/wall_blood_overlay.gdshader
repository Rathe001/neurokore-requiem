// Wall blood overlay — Phase 4 (discard where mask is empty, PBR shaded).
// Where the mask is empty, discard so the wall behind shows through.
// Where stamped, paint blood-red with PBR shading so the overlay
// inherits scene lighting — dark areas (outside the player's lit
// zone) end up dark instead of showing solid red against the void.
// Production version will multiply-stain over screen_texture + tune
// roughness for wet sheen.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D mask : filter_linear, repeat_disable, hint_default_black;

void fragment() {
	float a = texture(mask, UV).a;
	if (a < 0.05) {
		discard;
	}
	ALBEDO = vec3(0.7, 0.08, 0.08);
	ROUGHNESS = 0.4;
	METALLIC = 0.0;
}
