// Doomsayer aura fog sphere — a single SphereMesh enclosing the player.
// Fragment shader does silhouette fade (so the sphere reads as a soft
// fluffy ball, not a hard balloon) plus 3D fbm noise for the swirling
// vapor look. Wall clipping is delegated to a shadow-casting OmniLight3D
// at the sphere centre — the light's albedo wash on world surfaces is
// what actually communicates "the fog stops at the wall." This shader
// just provides the visible body of mist around the player.

shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, unshaded;

uniform vec4 fog_color : source_color = vec4(0.78, 0.35, 0.85, 1.0);
uniform float intensity : hint_range(0.0, 4.0) = 1.0;
// 3D noise field drift speed — small values feel like slow vapor.
uniform float drift_speed : hint_range(-1.0, 1.0) = 0.18;
// Larger noise_scale = finer detail; smaller = wide soft puffs. Tuned
// for the larger sphere radii (up to 9m at T3) — at this scale a noise
// cell is ~3m across, so we get a couple of soft puffs per visible
// volume instead of a chaotic cloud.
uniform float noise_scale : hint_range(0.1, 4.0) = 0.35;
// Higher core_softness = denser concentration in the centre, longer
// transparent tail at the edges. The front-facing fragments (NORMAL
// pointing at camera) are dense; the silhouette edges fade to nothing
// well before the geometric sphere edge. core_softness >= 3 hides the
// hard sphere outline by making the outer ~40% of radius effectively
// transparent.
uniform float core_softness : hint_range(0.5, 6.0) = 3.5;
// Soft-particles depth fade — fragments within this many world units
// of opaque scene geometry get faded out. Helps smooth where the
// sphere touches the floor / nearby objects.
uniform float depth_fade_distance : hint_range(0.0, 1.5) = 0.35;

uniform sampler2D depth_sampler : hint_depth_texture, repeat_disable, filter_nearest;

// Object-space position so noise moves WITH the sphere (an aura that
// follows the player feels right; world-space noise looks like the
// player is walking through static fog instead).
varying vec3 obj_pos;
varying vec3 view_pos;


// 3D value-noise hash. No texture sample, deterministic.
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Trilinear-interpolated 3D value noise.
float vnoise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float c000 = hash3(i + vec3(0.0, 0.0, 0.0));
	float c100 = hash3(i + vec3(1.0, 0.0, 0.0));
	float c010 = hash3(i + vec3(0.0, 1.0, 0.0));
	float c110 = hash3(i + vec3(1.0, 1.0, 0.0));
	float c001 = hash3(i + vec3(0.0, 0.0, 1.0));
	float c101 = hash3(i + vec3(1.0, 0.0, 1.0));
	float c011 = hash3(i + vec3(0.0, 1.0, 1.0));
	float c111 = hash3(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(c000, c100, f.x), mix(c010, c110, f.x), f.y),
		mix(mix(c001, c101, f.x), mix(c011, c111, f.x), f.y),
		f.z
	);
}

// 3-octave fractal Brownian motion. Output ~0..1.
float fbm3(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise3(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}


void vertex() {
	obj_pos = VERTEX;
	view_pos = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}


void fragment() {
	// Core-density term: dense at the centre (where NORMAL points
	// straight at camera), transparent at silhouette edges. abs() lets
	// back faces share the same falloff so cull_disabled doesn't show
	// a hard back-face seam. The visible result is a dense purple core
	// fading to nothing at the edges — also hides any geometric bleed
	// past walls because the wall-side silhouette is already invisible.
	float facing = abs(dot(NORMAL, VIEW));
	float core = pow(facing, core_softness);

	// 3D fbm in object space with vertical drift over time. Drifting
	// only on Y reads as rising vapour; drifting on all axes feels
	// like wind, which is wrong for an aura.
	vec3 sample_pos = obj_pos * noise_scale;
	sample_pos.y -= TIME * drift_speed;
	float n = fbm3(sample_pos);

	// Soft-particles depth fade — keeps the sphere from clipping
	// hard against the floor / other objects it intersects.
	float scene_depth = texture(depth_sampler, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_scene_depth = -view.z;
	float linear_self_depth = -view_pos.z;
	float depth_diff = linear_scene_depth - linear_self_depth;
	float depth_fade = clamp(depth_diff / max(depth_fade_distance, 0.001), 0.0, 1.0);

	float alpha = clamp(core * n * intensity * depth_fade, 0.0, 1.0);

	// Mild self-glow keeps the fog visible at the silhouette where
	// the OmniLight wash doesn't hit. Small enough that wall clipping
	// (which works via the OmniLight's shadows on world surfaces) is
	// still the dominant visual cue.
	ALBEDO = fog_color.rgb;
	EMISSION = fog_color.rgb * alpha * 0.4;
	ALPHA = alpha * fog_color.a;
}
