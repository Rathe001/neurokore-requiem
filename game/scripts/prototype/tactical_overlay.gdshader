shader_type spatial;

// Tactical range overlay for SCANNER head mod. Draws two concentric
// rings on a horizontal PlaneMesh centered on the player:
//   inner (green, solid)  = weapon effective range (full damage)
//   outer (orange, dashed) = falloff boundary (2x range, 25% damage)
// Subtle scan-line flicker sells the holographic HUD aesthetic.

render_mode unshaded, depth_draw_never, cull_disabled, blend_mix;

uniform float inner_radius : hint_range(0.0, 1.0) = 0.5;
uniform float outer_radius : hint_range(0.0, 1.0) = 1.0;
uniform vec3 inner_color : source_color = vec3(0.2, 0.85, 0.4);
uniform vec3 outer_color : source_color = vec3(0.95, 0.6, 0.15);
// Toned-down defaults — previous values (thickness 0.008, max_alpha
// 0.45, intensity 2.0, scan_speed 2.0) HDR-bloomed bright green/orange
// over the play area and pulled focus from the gameplay. The current
// values keep the rings legible as a quiet reference but no longer
// dominate the frame.
uniform float ring_thickness : hint_range(0.001, 0.05) = 0.005;
uniform float max_alpha : hint_range(0.0, 1.0) = 0.18;
uniform float scan_speed : hint_range(0.0, 8.0) = 0.6;
uniform float dash_count : hint_range(4.0, 64.0) = 24.0;
uniform float intensity : hint_range(0.0, 4.0) = 0.9;

// World-space XZ rect of the room the player is currently standing in.
// Components: (min_x, min_z, max_x, max_z). Updated every frame by
// tactical_overlay.gd from ExplorationState.get_piece_aabb. Fragments
// whose world XZ falls outside the rect get discarded, clipping the
// rings to the room interior even when the PlaneMesh extends past
// the walls. A zero-area rect (when not in any registered piece)
// disables the clip.
uniform vec4 room_aabb = vec4(-9999.0, -9999.0, 9999.0, 9999.0);

// Local-space vertex position carried from vertex into fragment so we
// can transform it to world coords for the AABB clip. VERTEX in a
// fragment shader is view-space, not local, so a varying is required.
varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	// World XZ of THIS fragment via the model matrix. PlaneMesh's UV
	// runs along its local XZ so this matches the visible position.
	vec4 world = MODEL_MATRIX * vec4(v_local_pos, 1.0);
	if (world.x < room_aabb.x || world.z < room_aabb.y || world.x > room_aabb.z || world.z > room_aabb.w) {
		discard;
	}
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	if (r > 1.0) {
		discard;
	}

	// Inner ring — solid band.
	float inner_dist = abs(r - inner_radius);
	float inner_band = 1.0 - smoothstep(ring_thickness * 0.4, ring_thickness, inner_dist);

	// Outer ring — dashed via angular step function.
	float outer_dist = abs(r - outer_radius);
	float outer_band = 1.0 - smoothstep(ring_thickness * 0.4, ring_thickness, outer_dist);
	float angle = atan(uv.y, uv.x);
	float dash = step(0.5, fract(angle * dash_count / (2.0 * 3.14159265)));
	outer_band *= dash;

	// Scan-line flicker — horizontal lines scrolling upward.
	float scan = 0.85 + 0.15 * sin(uv.y * 40.0 + TIME * scan_speed);

	// Compose rings.
	vec3 color = inner_color * inner_band + outer_color * outer_band;
	float alpha = (inner_band + outer_band) * scan * max_alpha;

	ALBEDO = color * intensity;
	ALPHA = clamp(alpha, 0.0, max_alpha);
}
