shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, blend_mix;

uniform vec4 back_color : source_color = vec4(0.12, 0.14, 0.18, 1.0);
uniform vec4 border_color : source_color = vec4(0.02, 0.03, 0.05, 1.0);
uniform float border_thickness = 0.08;
// Instance uniforms so each enemy can have its own fill (charmed pets
// override to green, hostiles use the red default) and fill ratio
// without needing a separate material per body.
instance uniform float fill_ratio = 1.0;
instance uniform vec4 fill_color : source_color = vec4(1.0, 0.28, 0.32, 1.0);

void vertex() {
	mat4 billboard = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
	vec3 scale = vec3(
		length(MODEL_MATRIX[0].xyz),
		length(MODEL_MATRIX[1].xyz),
		length(MODEL_MATRIX[2].xyz)
	);
	MODELVIEW_MATRIX = billboard * mat4(
		vec4(scale.x, 0.0, 0.0, 0.0),
		vec4(0.0, scale.y, 0.0, 0.0),
		vec4(0.0, 0.0, scale.z, 0.0),
		vec4(0.0, 0.0, 0.0, 1.0)
	);
}

void fragment() {
	bool in_border = UV.x < border_thickness * 0.5
		|| UV.x > 1.0 - border_thickness * 0.5
		|| UV.y < border_thickness
		|| UV.y > 1.0 - border_thickness;
	vec4 color;
	if (in_border) {
		color = border_color;
	} else if (UV.x < border_thickness * 0.5 + (1.0 - border_thickness) * fill_ratio) {
		color = fill_color;
	} else {
		color = back_color;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
