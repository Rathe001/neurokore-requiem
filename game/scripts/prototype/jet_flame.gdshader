shader_type spatial;

// Continuous-channel flame visual for the Energy Accelerator's stream
// LMB. Adapted from https://godotshaders.com/shader/futuristic-jet-thruster/
// — replaces the FastNoiseLite texture sampler with built-in FBM so the
// material has zero external dependencies.
//
// Mesh expectation: a stretched cylinder/cone with its long axis on
// local Y. UV.x is the radial coordinate (0..1 across circumference);
// UV.y is along the length (0 = base, 1 = tip). Time-scrolling UV.y
// produces the outward-flow look of a continuous jet.

render_mode unshaded, depth_draw_opaque, cull_disabled, blend_mix;

uniform vec3 flame_color : source_color = vec3(1.0, 0.5, 0.1);
uniform vec3 inner_color : source_color = vec3(1.0, 0.95, 0.7);
uniform float scroll_speed = 3.0;
uniform float noise_scale = 3.5;
uniform float intensity : hint_range(0.0, 5.0) = 1.5;


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
	// Mesh orientation note: CylinderMesh UVs map UV.y=0 at the top
	// (mesh +Y) and UV.y=1 at the bottom (mesh -Y). This shader's
	// host mounts the cylinder so mesh -Y is at the muzzle (narrow,
	// player chest) and mesh +Y is at the far end (wide, where the
	// hit cone lands). So in shader space:
	//   UV.y = 1.0  →  muzzle (narrow, hot)
	//   UV.y = 0.0  →  far tip (wide, cooling)
	// The whole shader is written against this convention; flipping
	// it on the host side breaks animation flow + brightness.
	vec2 uv = UV * noise_scale;
	// `+= TIME * scroll_speed` makes the noise pattern flow toward
	// LOWER UV.y, which on this mesh = toward the far tip. The flame
	// reads as ejected outward from the muzzle.
	uv.y += TIME * scroll_speed;
	float n = (fbm(uv) + fbm(uv * 1.7 + vec2(5.2, 1.3))) * 0.5;

	// Radial: bright on the centerline, fades to edges. UV.x runs 0..1
	// around the circumference; 0.5 is the visible centerline.
	float radial = 1.0 - smoothstep(0.0, 1.0, abs(UV.x - 0.5) * 2.0);
	// Length fade: brightest at the muzzle (UV.y near 1), cooling
	// toward the tip (UV.y near 0). Power curve front-loads the
	// brightness so the muzzle reads as the heat source instead of
	// a uniform ramp.
	float length_fade = pow(UV.y, 1.4);

	float brightness = radial * length_fade * (n * 1.4 + 0.2);
	brightness = clamp(brightness * intensity, 0.0, 1.5);

	// Hot core uses inner_color where brightness is high; body uses
	// the elemental flame_color where brightness is low. Smoothstep
	// gives a soft falloff between the two.
	float core_blend = smoothstep(0.4, 1.0, brightness);
	vec3 col = mix(flame_color, inner_color, core_blend);

	ALBEDO = col * brightness * 1.8;
	ALPHA = clamp(brightness, 0.0, 1.0);
}
