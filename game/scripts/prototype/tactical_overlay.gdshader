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

// Scene depth buffer + matrices for reconstructing world position from
// depth. Used to clip overlay fragments that sit over the outer "void
// ground" mesh (which lives at y = -20, well below the room floor at
// y = 0) — depth-only checks don't work because that ground IS opaque
// geometry, it's just way below the playable surface.
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

// World Y threshold: pixels whose reconstructed scene-depth world Y
// reads below this are considered "outside the level" and clipped.
// Room floors sit at y = 0, the outer void ground at y = -20, so
// anything more than ~2m below the floor is void territory.
const float TACTICAL_FLOOR_Y_THRESHOLD = -2.0;

void fragment() {
	// Reconstruct the world-space point this overlay fragment is
	// looking at. Godot 4 / Vulkan: depth_texture returns reverse-Z
	// values in [0, 1]; NDC X/Y in [-1, 1]. Multiplying by 2.0 - 1.0
	// on XY remaps SCREEN_UV to NDC; depth stays in [0, 1] for the
	// inverse-projection step.
	float scene_depth = texture(depth_texture, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	vec4 world = INV_VIEW_MATRIX * vec4(view.xyz, 1.0);
	if (world.y < TACTICAL_FLOOR_Y_THRESHOLD) {
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
