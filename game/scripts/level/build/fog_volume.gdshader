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
render_mode unshaded, blend_mix, cull_back, depth_draw_never;

uniform vec3 fog_color : source_color = vec3(0.62, 0.66, 0.74);
uniform float density : hint_range(0.0, 8.0) = 1.4;
uniform float fog_top : hint_range(0.1, 5.0) = 0.5;
uniform float falloff : hint_range(0.5, 5.0) = 2.2;
uniform float noise_scale : hint_range(0.05, 2.0) = 0.45;
uniform float noise_speed : hint_range(0.0, 0.5) = 0.06;
uniform int march_steps : hint_range(4, 64) = 24;
uniform float march_step_size : hint_range(0.05, 0.5) = 0.12;
uniform float player_radius : hint_range(0.5, 5.0) = 1.6;
uniform float player_strength : hint_range(0.0, 1.0) = 0.85;

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
float sample_density_at(vec3 wp) {
	float y_t = clamp(wp.y / max(0.01, fog_top), 0.0, 1.0);
	float h = pow(1.0 - y_t, falloff);
	vec3 npos = wp * noise_scale + vec3(
		TIME * noise_speed,
		TIME * noise_speed * 0.3,
		TIME * noise_speed * 0.7);
	float n = fbm3(npos);
	vec3 to_player = wp - player_world_pos;
	to_player.y = 0.0;
	float player_t = smoothstep(0.0, player_radius, length(to_player));
	float pf = mix(1.0 - player_strength, 1.0, player_t);
	return h * (0.4 + 0.6 * n) * pf;
}

varying vec3 world_pos;
varying vec3 view_dir_ws;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_dir_ws = normalize(world_pos - CAMERA_POSITION_WORLD);
}

void fragment() {
	float accum = 0.0;
	float t = 0.0;
	for (int i = 0; i < march_steps; i++) {
		vec3 sp = world_pos + view_dir_ws * t;
		// Only early-out when the ray dips below the floor. The earlier
		// "break above fog_top" check killed the iso top-face entry entirely
		// (the camera enters the box at y > fog_top and immediately broke
		// before sampling), so the floor fog never rendered from above. The
		// height_factor inside sample_density_at returns 0 outside fog_top
		// anyway, so wasted steps above the fog band contribute nothing.
		if (sp.y < -0.05) {
			break;
		}
		accum += sample_density_at(sp) * march_step_size;
		t += march_step_size;
	}
	// Beer-Lambert-style alpha so dense regions read as solid without
	// hard-clipping at 1.0.
	float alpha = clamp(1.0 - exp(-accum * density), 0.0, 1.0);
	ALBEDO = fog_color;
	ALPHA = alpha;
}
