shader_type spatial;

// Procedural explosion fireball — inspired by the flipbook particle
// shader at https://godotshaders.com/shader/3d-explosion-vfx/ but
// adapted to procedural noise so we don't need the source's seven
// sprite-sheet textures. The original was a GPUParticles3D system
// with pre-rendered explosion frames; this one paints the same look
// directly on a sphere mesh.
//
// Visual contract: a bright yellow-white core, fading through orange
// to dark red at the rim, with FBM turbulence breaking up the
// gradient so the surface boils like fire. Fresnel-based alpha at
// the silhouette so the explosion doesn't read as a solid sphere
// edge — it dissolves into the air. age uniform tweens 0→1 over
// the explosion's lifetime so the spawn function can fade it from
// fresh fireball to dispersing smoke.
//
// render_mode: unshaded so lighting doesn't dim the fireball;
// blend_mix with depth_draw_never so the explosion paints over
// the scene without occluding nearby walls/enemies; cull_disabled
// because the back face shows through during expansion.

render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform vec3 core_color : source_color = vec3(1.0, 0.95, 0.7);
uniform vec3 mid_color : source_color = vec3(1.0, 0.5, 0.10);
uniform vec3 outer_color : source_color = vec3(0.65, 0.15, 0.05);
uniform vec3 smoke_color : source_color = vec3(0.18, 0.16, 0.14);
// Overall brightness multiplier, tweened down by spawn_explosion as
// the fireball ages.
uniform float intensity : hint_range(0.0, 8.0) = 1.0;
// 0 = freshly detonated (fully bright), 1 = fully dispersing smoke.
// Drives the color shift toward smoke_color and the alpha falloff.
uniform float age : hint_range(0.0, 1.0) = 0.0;
// Density of the surface turbulence. Lower = bigger blobs of churn,
// higher = finer detail. 4.0 reads as "boiling fire" at typical
// blast radii (~3–5m).
uniform float noise_scale = 4.0;
// Speed of the time-based noise evolution. The original flipbook
// played 64 frames over the explosion's life; we approximate that
// "always-changing surface" via fast TIME stepping on the FBM input.
uniform float churn_speed = 3.0;


// ── Procedural noise (no texture inputs) ─────────────────────────────────

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			   mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}


void fragment() {
	// Fresnel: 0 facing camera, 1 at silhouette. Drives BOTH the radial
	// color gradient (center hot, rim dark) and the alpha (center
	// opaque, silhouette feathers to invisible).
	float fresnel = 1.0 - clamp(dot(normalize(VIEW), normalize(NORMAL)), 0.0, 1.0);
	float radial = smoothstep(0.0, 1.0, fresnel);

	// Two animated FBM layers in different directions for the
	// "boiling" look — same trick the acid pool uses, fewer octaves.
	vec2 uv = UV * noise_scale;
	float t = TIME * churn_speed;
	float n1 = fbm(uv + vec2(t, t * 0.7));
	float n2 = fbm(uv * 1.4 - vec2(t * 0.6, t));
	float turbulence = (n1 + n2) * 0.5;

	// Perturb the radial gradient with turbulence so the color
	// transitions don't read as smooth concentric rings — they
	// break up into churning hot spots and cooler patches.
	float gradient = clamp(radial - turbulence * 0.35, 0.0, 1.0);

	// 3-stop color ramp: core → mid → outer. Smoothstep ranges
	// give each band a soft edge instead of hard transitions.
	vec3 hot = mix(core_color, mid_color, smoothstep(0.0, 0.45, gradient));
	vec3 warm = mix(hot, outer_color, smoothstep(0.4, 0.85, gradient));

	// As age advances, drag the entire color toward smoke_color so
	// the explosion fades to dispersing dark smoke rather than just
	// vanishing. Same age value tweens the alpha down — the smoke
	// is visible briefly before it fully clears.
	vec3 final_color = mix(warm, smoke_color, age * age);

	// Alpha: opaque at center, transparent at rim, plus an overall
	// fade with age. The age-curve uses a 1-(1-x)^2 ease so the
	// alpha holds high during the bright phase and drops sharply
	// near the end (matches how a real explosion looks bright then
	// quickly clears).
	float age_fade = 1.0 - (age * age);
	float alpha = (1.0 - radial * 0.6) * age_fade;

	ALBEDO = vec3(0.0);
	EMISSION = final_color * intensity * (1.0 - age * 0.7);
	ALPHA = clamp(alpha, 0.0, 1.0);
}
