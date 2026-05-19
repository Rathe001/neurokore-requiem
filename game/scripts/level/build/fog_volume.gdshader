// Volumetric ground-fog shader for per-room FogVolume nodes. Rendered by
// Godot's volumetric fog pass — completely contained by the FogVolume's
// box bounds (no escape possible, by design of the volumetric pipeline).
//
// Three things going on per voxel:
//   1. Height-based density falloff — fog hugs the floor.
//   2. Animated 3D fBM noise — gives the "dry-ice billowing" look rather
//      than uniform density.
//   3. Player parting — global shader uniform `player_world_pos` (set
//      every frame by PrototypePlayer) carves a soft cylinder of reduced
//      density around the player. Fog visibly opens up where they walk.

shader_type fog;

uniform float density_strength : hint_range(0.0, 8.0) = 3.5;
uniform float fog_top : hint_range(0.1, 5.0) = 1.4;
uniform float falloff : hint_range(0.5, 5.0) = 1.6;
uniform float noise_scale : hint_range(0.05, 2.0) = 0.45;
uniform float noise_speed : hint_range(0.0, 0.5) = 0.07;
uniform vec3 fog_color : source_color = vec3(0.72, 0.76, 0.82);
uniform float player_radius : hint_range(0.5, 5.0) = 1.6;
uniform float player_strength : hint_range(0.0, 1.0) = 0.9;

global uniform vec3 player_world_pos;

// 3D value-noise primitives.

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

void fog() {
	vec3 wp = WORLD_POSITION;

	// Height falloff — density 1 at the floor, ramps to 0 above fog_top.
	// The FogVolume's box `position.y` is the centre of the volume; we
	// assume the volume's bottom face sits at world y = 0 (per the builder).
	float y_t = clamp(wp.y / max(0.01, fog_top), 0.0, 1.0);
	float height_factor = pow(1.0 - y_t, falloff);

	// 3D fBM scrolling slowly through space + time → billowing wisps.
	vec3 npos = wp * noise_scale + vec3(
		TIME * noise_speed,
		TIME * noise_speed * 0.3,
		TIME * noise_speed * 0.7);
	float n = fbm3(npos);

	// Player parting — soft cylinder of reduced density, ignoring vertical
	// separation so the player carves through fog regardless of stance.
	vec3 to_player = wp - player_world_pos;
	to_player.y = 0.0;
	float player_t = smoothstep(0.0, player_radius, length(to_player));
	float player_factor = mix(1.0 - player_strength, 1.0, player_t);

	DENSITY = density_strength * height_factor * (0.45 + 0.55 * n) * player_factor;
	ALBEDO = fog_color;
}
