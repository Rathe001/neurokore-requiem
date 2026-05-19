// Mesh-based ground fog. A transparent BoxMesh per room hosts this shader;
// each fragment raymarches through the box from the front face inward,
// accumulating 3D noise density. Walls and pillars get drawn first into the
// opaque pass, write to depth, then transparent depth-test culls any fog
// fragment that's behind an opaque surface — geometric containment with no
// volumetric-fog "halo through walls" failure mode that pushed us off the
// FogVolume path.
//
// Three contributions per ray sample:
//   1. Height-based density falloff — fog hugs the floor.
//   2. Animated 3D fBM noise — billowing wisps rather than uniform haze.
//   3. Player parting — global shader uniform `player_world_pos` (set every
//      frame by PrototypePlayer) carves a soft cylinder of reduced density
//      around the player so the fog visibly opens up where they walk.

shader_type spatial;
// Dropped `unshaded`: with it, the fog rendered as a uniform gradient
// and looked artificial. Without it, the room's ceiling fluorescents
// tint and brighten the fog directly — bright under lit fixtures,
// dimmer in shadowed corners, color-shifted toward each room's
// LightColor. We override NORMAL to world-up below so the lighting is
// driven by overhead lights regardless of which face of the box this
// fragment lives on (otherwise the box's vertical side faces would
// catch sideways light and read as walls again).
//
// cull_disabled (was cull_back): when the camera is inside the box —
// crouched FPS, camera at 0.7m, box extends 0.02m–0.92m — every face is
// back-facing from inside, so cull_back rendered nothing. Disabling
// culling renders both faces; the visible inner faces from a crouched
// view give the player a tinted-around-them haze.
render_mode blend_mix, cull_disabled, depth_draw_never;

uniform vec3 fog_color : source_color = vec3(0.62, 0.66, 0.74);
uniform float density : hint_range(0.0, 8.0) = 2.8;
uniform float fog_top : hint_range(0.05, 5.0) = 0.65;
uniform float falloff : hint_range(0.5, 6.0) = 2.4;
uniform float noise_scale : hint_range(0.05, 2.0) = 0.55;
uniform float noise_speed : hint_range(0.0, 0.5) = 0.11;
uniform int march_steps : hint_range(4, 64) = 24;
uniform float march_step_size : hint_range(0.05, 0.5) = 0.08;
// Noise threshold for the "sparse wisps" look. Anything below this value
// contributes zero density — only the noise peaks survive, so the floor
// reads as patchy wisps drifting across clear ground instead of a
// uniform blanket. wisp_softness widens the smoothstep band so the wisp
// edges feather instead of being hard-clipped.
// Threshold against the RIDGE field (post-1-abs(2n-1) transform), which
// has values concentrated in the upper half. 0.75 keeps only the
// thin filament cores; lower it for thicker streaks, raise toward
// 0.9 for only the wispiest threads.
uniform float wisp_threshold : hint_range(0.0, 1.0) = 0.75;
uniform float wisp_softness : hint_range(0.01, 0.5) = 0.12;
uniform float player_radius : hint_range(0.5, 5.0) = 1.6;
uniform float player_strength : hint_range(0.0, 1.0) = 0.85;
// Hard cap on the final alpha. Lowered to keep the wisp-mode look
// atmospheric — a wisp peak should suggest mist drifting, not read as
// a solid puff. Crank back up to ~0.5 for thicker ground fog.
uniform float max_alpha : hint_range(0.0, 1.0) = 0.22;
// Half-extents of the BoxMesh in local XZ. Set per-instance by the builder
// via set_instance_shader_parameter — drives the edge fade so each room's
// fog blends out at its boundary instead of having a hard rectangular
// edge.
instance uniform vec2 box_half_extents_xz = vec2(2.0, 2.0);
// Width of the soft edge-fade band in world units. Outside this distance
// from the box edge the fog is full strength; right at the edge alpha is
// zero, smoothstep in between.
uniform float edge_fade : hint_range(0.05, 2.0) = 0.7;
// Faint self-emission so wisps don't go fully black in unlit corners.
// Scales with the wisp density so it only brightens the wisps themselves,
// not the clear ground between them.
uniform float emission_floor : hint_range(0.0, 0.5) = 0.02;

global uniform vec3 player_world_pos;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(
			mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
			mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x),
			f.y),
		mix(
			mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
			mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x),
			f.y),
		f.z);
}

float fbm3(vec3 p) {
	return vnoise3(p) * 0.55
		+ vnoise3(p * 2.13 + 7.7) * 0.30
		+ vnoise3(p * 4.71 + 13.1) * 0.15;
}

// Density at an arbitrary world-space sample point inside the fog box.
// Result is in [0, 1] — caller integrates it along the view ray.
//
// Three transforms to get smoke-like long thin wisps instead of fBM
// blob-clouds:
//   1. Anisotropic stretch — sample with vec3(0.35, 1.0, 1.5) scale, so
//      features are ~4× longer along world X than world Z. The "long
//      thin" axis is X (the same axis the time drift flows down), giving
//      wind-blown smoke streaks.
//   2. Domain warping — distort the sample position by a second
//      lower-frequency fBM. Without this, the stretched noise reads as
//      parallel straight lines; with it the streaks curve and tangle
//      like actual smoke.
//   3. Ridge transform — `1 - abs(2n - 1)` converts the noise's smooth
//      blobs into thin peaked ridges. The resulting field looks like
//      filaments rather than puffs.
float sample_density_at(vec3 wp) {
	float y_t = clamp(wp.y / max(0.01, fog_top), 0.0, 1.0);
	float h = pow(1.0 - y_t, falloff);
	vec3 base = wp * vec3(0.35, 1.0, 1.5) * noise_scale;
	vec3 anim = vec3(
		TIME * noise_speed,
		TIME * noise_speed * 0.25,
		TIME * noise_speed * 0.4);
	vec3 p = base + anim;
	// Domain warp: 3 fBM samples at lower frequency give per-component
	// offset to the actual lookup, bending the streaks.
	vec3 warp = vec3(
		fbm3(p * 0.55),
		fbm3(p * 0.55 + vec3(7.2, 1.3, 4.7)),
		fbm3(p * 0.55 + vec3(2.9, 5.4, 8.1)));
	float n = fbm3(p + (warp - 0.5) * 1.6);
	// Ridge transform: collapse smooth blobs into thin filaments.
	float ridge = 1.0 - abs(n * 2.0 - 1.0);
	float wisp = smoothstep(wisp_threshold, wisp_threshold + wisp_softness, ridge);
	vec3 to_player = wp - player_world_pos;
	to_player.y = 0.0;
	float player_t = smoothstep(0.0, player_radius, length(to_player));
	float pf = mix(1.0 - player_strength, 1.0, player_t);
	return h * wisp * pf;
}

varying vec3 world_pos;
varying vec2 local_xz;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// VERTEX is in box-local coordinates, ranging from -size/2 to +size/2
	// because we never apply additional scale to the MeshInstance3D.
	local_xz = VERTEX.xz;
}

void fragment() {
	// Compute view direction per-fragment instead of interpolating from
	// vertex output — the previous setup interpolated view_dir_ws across
	// the BoxMesh's quad triangles, which made the diagonal triangle seam
	// visible as a line across the fog surface from above.
	vec3 view_dir_ws = normalize(world_pos - CAMERA_POSITION_WORLD);
	// Per-pixel jitter for the raymarch start. Without this, adjacent
	// pixels sample density at the same depths along their rays, and the
	// step boundaries become visible as concentric / diagonal banding
	// across the fog surface. Offsetting each pixel's first sample by a
	// hash of its screen UV decorrelates the steps and the bands dissolve
	// into film-grain-like noise.
	float jitter = fract(sin(dot(SCREEN_UV, vec2(12.9898, 78.233))) * 43758.5453);
	float t = jitter * march_step_size;
	float accum = 0.0;
	for (int i = 0; i < march_steps; i++) {
		vec3 sp = world_pos + view_dir_ws * t;
		// Only early-out when the ray dips below the floor. height_factor
		// inside sample_density_at returns 0 outside fog_top so wasted
		// steps above the fog band contribute nothing — we just keep
		// marching until we exit the bottom.
		if (sp.y < -0.05) {
			break;
		}
		accum += sample_density_at(sp) * march_step_size;
		t += march_step_size;
	}
	// Beer-Lambert alpha, then clamped by max_alpha so edge-on views can't
	// produce wall-opaque results.
	float alpha = clamp(1.0 - exp(-accum * density), 0.0, 1.0);
	// Soft fade at the box edges so fog blends out instead of stopping at
	// a hard rectangle. Distance from the local XZ position to the nearest
	// box edge; smoothstep brings alpha to 0 as the fragment approaches.
	vec2 dist_xz = box_half_extents_xz - abs(local_xz);
	float edge_t = smoothstep(0.0, edge_fade, min(dist_xz.x, dist_xz.y));
	ALBEDO = fog_color;
	// Force the fragment's lighting normal to world-up regardless of which
	// face of the BoxMesh it lives on. Without this, side faces would
	// catch sideways light and read as lit vertical walls; with it every
	// fog pixel responds to overhead fluorescents the way a horizontal
	// layer of mist would. NORMAL in the fragment shader is view-space,
	// so we apply VIEW_MATRIX to the world-up vector.
	NORMAL = mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0);
	// Pure diffuse — fog has no specular highlights.
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	// Baseline emission scaled by the same density. Keeps the fog faintly
	// visible everywhere the room itself is, then naturally fades to
	// black as the room's floor fades into the void.
	EMISSION = fog_color * emission_floor * alpha;
	ALPHA = alpha * max_alpha * edge_t;
}
