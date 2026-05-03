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
// transparent tail at the edges. Pushed very high so the visible mass
// collapses to a tight glowing core inside the geometric sphere —
// reads as "energy radiating from the body" rather than "player
// inside a bubble." With softness=14 the visible alpha is essentially
// zero outside the inner ~20% of the geometric radius.
uniform float core_softness : hint_range(0.5, 24.0) = 14.0;
// Silhouette discard — fragments where the surface normal is near
// perpendicular to the view direction (i.e., the silhouette/outline
// of the geometric sphere) get discarded entirely. Without this, even
// the tiny alpha at the silhouette + bright emission paints a faint
// arch outlining the sphere's geometric shape (the "bubble edge"
// the user kept seeing). Higher value = more aggressive hiding.
uniform float silhouette_discard : hint_range(0.0, 0.5) = 0.18;
// Soft-particles depth fade — fragments within this many world units
// of opaque scene geometry get faded out. Helps smooth where the
// sphere touches the floor / nearby objects.
uniform float depth_fade_distance : hint_range(0.0, 1.5) = 0.35;
// Void-clip distance — when the scene depth at a fragment is THIS
// many world units BEYOND the fragment (i.e., nothing nearby behind
// it, suggesting a void / off-the-map area), fade to zero. Stops the
// sphere from rendering over open space past the room boundary.
uniform float void_clip_distance : hint_range(1.0, 30.0) = 6.0;
uniform float void_fade_softness : hint_range(0.5, 8.0) = 2.5;

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
	// a hard back-face seam.
	float facing = abs(dot(NORMAL, VIEW));
	// Hard cutoff at the silhouette — without this, even a tiny core
	// value at the geometric edge combined with bright emission paints
	// a visible arch outlining the sphere's shape. discard ensures the
	// outline is genuinely invisible regardless of intensity tuning.
	if (facing < silhouette_discard) {
		discard;
	}
	float core = pow(facing, core_softness);

	// 3D fbm in object space with vertical drift over time. Drifting
	// only on Y reads as rising vapour; drifting on all axes feels
	// like wind, which is wrong for an aura.
	vec3 sample_pos = obj_pos * noise_scale;
	sample_pos.y -= TIME * drift_speed;
	float n = fbm3(sample_pos);

	// Sample scene depth once and reuse for both fades.
	float scene_depth = texture(depth_sampler, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_scene_depth = -view.z;
	float linear_self_depth = -view_pos.z;
	float depth_diff = linear_scene_depth - linear_self_depth;

	// Soft-particles depth fade — fragments inside / very close to
	// opaque geometry fade out so we don't get hard contact lines.
	float depth_fade = clamp(depth_diff / max(depth_fade_distance, 0.001), 0.0, 1.0);

	// Void clip — when the scene geometry is far BEYOND this fragment
	// (depth_diff large positive), the fragment is hovering over open
	// space past the room edge. Fade to zero so the sphere doesn't
	// bleed past room boundaries / over pits. Smoothstep for a soft
	// transition rather than a hard cut.
	float void_fade = 1.0 - smoothstep(void_clip_distance, void_clip_distance + void_fade_softness, depth_diff);

	float alpha = clamp(core * n * intensity * depth_fade * void_fade, 0.0, 1.0);

	// Strong emission gives the "radiating energy" feel — the visible
	// core glows brightly, then drops off fast. The OmniLight handles
	// the wider purple wash on world surfaces (with proper wall
	// shadows); this mesh just provides the glowing body the player
	// can see has energy bleeding off it. Emission scaled down a bit
	// (was 1.4) since the silhouette_discard now hides the outline,
	// removing the need for emission to mask it via brightness.
	ALBEDO = fog_color.rgb;
	EMISSION = fog_color.rgb * alpha * 0.9;
	ALPHA = alpha * fog_color.a;
}
