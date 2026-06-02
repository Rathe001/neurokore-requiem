// Wall blood overlay — Phase 5 (world-position UV).
// Two masks: mask_x covers ±X-facing walls (indexed by (z, y)),
// mask_z covers ±Z-facing walls (indexed by (x, y)). Wall's world
// normal picks which mask to sample. A single stamp at world (x, y, z)
// thus lands on exactly the wall at that position — not on every
// wall like the Phase 4 local-UV test did.
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

uniform sampler2D mask_x : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D mask_z : filter_linear, repeat_disable, hint_default_black;
uniform float world_extent_xz : hint_range(8.0, 200.0) = 40.0;
uniform float wall_height : hint_range(1.0, 16.0) = 4.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Branch on which world axis the wall's normal aligns with —
	// horizontal-X-facing walls sample mask_x with the wall's Z and Y;
	// horizontal-Z-facing walls sample mask_z with X and Y.
	float a;
	float half_h = 0.5;
	if (abs(v_world_normal.x) > abs(v_world_normal.z)) {
		vec2 uv = vec2(
			v_world_pos.z / world_extent_xz + half_h,
			1.0 - v_world_pos.y / wall_height
		);
		a = texture(mask_x, uv).a;
	} else {
		vec2 uv = vec2(
			v_world_pos.x / world_extent_xz + half_h,
			1.0 - v_world_pos.y / wall_height
		);
		a = texture(mask_z, uv).a;
	}
	if (a < 0.05) {
		discard;
	}
	ALBEDO = vec3(0.7, 0.08, 0.08);
	ROUGHNESS = 0.4;
	METALLIC = 0.0;
}
