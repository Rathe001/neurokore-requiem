shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// Floor puddle. Procedural irregular blob masked out of a flat plane with an
// alpha-cut falloff, low roughness so room lights catch as sharp speculars,
// subtle procedural ripple normals to read as water rather than mirror.
//
// Reflections: there's no per-room ReflectionProbe yet, so reflections are
// limited to direct light specular and whatever ambient the SDFGI / sky
// contributes. The "wet" read comes mostly from contrast between dark albedo
// and concentrated highlights.

uniform vec3 water_color : source_color = vec3(0.02, 0.03, 0.04);
uniform vec3 tint_color : source_color = vec3(0.04, 0.06, 0.08);
uniform float metallic_val : hint_range(0.0, 1.0) = 0.0;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.04;
uniform float ripple_strength : hint_range(0.0, 2.0) = 0.35;
uniform float ripple_scale : hint_range(0.5, 20.0) = 6.0;
uniform float ripple_speed : hint_range(0.0, 2.0) = 0.15;
uniform float blob_softness : hint_range(0.05, 0.5) = 0.22;
uniform float edge_dark : hint_range(0.0, 1.0) = 0.6;
uniform float seed : hint_range(0.0, 100.0) = 0.0;

varying vec3 world_pos;
varying vec3 local_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	local_pos = VERTEX;
}

void fragment() {
	// Mesh is a unit-ish plane; UV maps to local XZ in [-0.5, 0.5] range
	// (PlaneMesh subdivision = 0). Convert to a centred blob coordinate.
	vec2 p = UV - vec2(0.5);
	float r = length(p);

	// Blob mask: noise distorts the radius so the silhouette is irregular,
	// then a soft falloff produces the cut. seed shifts the noise so adjacent
	// puddles on the same floor look different.
	vec2 noise_uv = p * 4.0 + vec2(seed, seed * 0.7);
	float wobble = fbm(noise_uv) - 0.5;
	float effective_r = r + wobble * 0.18;
	float mask = 1.0 - smoothstep(0.5 - blob_softness, 0.5, effective_r);

	if (mask < 0.01) {
		discard;
	}

	// Slow ripple normal — two crossed sin waves at different frequencies
	// driven by TIME. Cheap, no normal-map sampling.
	float t = TIME * ripple_speed;
	vec2 rp = world_pos.xz * ripple_scale;
	float r1 = sin(rp.x * 1.0 + t * 1.3);
	float r2 = sin(rp.y * 1.1 - t * 0.9);
	float r3 = sin((rp.x + rp.y) * 0.7 + t * 0.6);
	vec2 ripple = vec2(
		(r1 + r3 * 0.5),
		(r2 + r3 * 0.5)
	) * ripple_strength * 0.05;

	// Tangent-space perturbation: tilt the up-normal by the ripple gradient.
	vec3 n = normalize(vec3(-ripple.x, 1.0, -ripple.y));

	// Albedo darkens toward the edge so the rim reads as wetter ground rather
	// than a hard cutout.
	float edge_falloff = smoothstep(0.5, 0.5 - blob_softness * 1.4, effective_r);
	vec3 col = mix(water_color * (1.0 - edge_dark), water_color, edge_falloff);
	col = mix(col, tint_color, 0.4);

	ALBEDO = col;
	METALLIC = metallic_val;
	ROUGHNESS = roughness_val;
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ALPHA = mask;
}
