shader_type spatial;

// Flat energy fan for the Energy Accelerator's channeled stream.
// Mesh: pizza-slice triangle fan in the XY plane. UV.x = 0..1 across
// the arc (0.5 = centerline), UV.y = 1 at muzzle apex, 0 at far tip.
// Renders as a ground-hugging energy wash visible from the iso camera.

render_mode unshaded, depth_draw_opaque, cull_disabled, blend_mix;

uniform vec3 flame_color : source_color = vec3(1.0, 0.5, 0.1);
uniform vec3 inner_color : source_color = vec3(1.0, 0.95, 0.7);
uniform float scroll_speed = 4.0;
uniform float noise_scale = 4.0;
uniform float intensity : hint_range(0.0, 5.0) = 1.5;
// Wall clip: fraction of the fan to hide from the tip inward.
// 0.0 = no clip (full range), 1.0 = fully clipped. Driven by raycast
// in _apply_flame_transform so the fan stops at walls without scaling.
uniform float clip_ratio : hint_range(0.0, 1.0) = 0.0;


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
	// Flowing energy noise — scrolls outward from muzzle to tip.
	vec2 uv = UV * noise_scale;
	uv.y += TIME * scroll_speed;
	float n = (fbm(uv) + fbm(uv * 1.7 + vec2(5.2, 1.3))) * 0.5;

	// Secondary crackle layer — higher frequency, faster scroll for
	// the look of energy arcs dancing across the fan surface.
	vec2 uv2 = UV * noise_scale * 2.5;
	uv2.y += TIME * scroll_speed * 1.8;
	uv2.x += TIME * 0.7;
	float crackle = fbm(uv2);
	// Sharp threshold turns smooth noise into bright arc lines.
	crackle = smoothstep(0.55, 0.7, crackle);

	// Radial: bright centerline, fading to edges.
	float radial = 1.0 - smoothstep(0.0, 1.0, abs(UV.x - 0.5) * 2.0);

	// Length fade: brightest at muzzle (UV.y=1), cooling toward tip (UV.y=0).
	float length_fade = pow(UV.y, 1.2);

	// Leading edge glow — bright band at the far tip so the reach
	// boundary is clearly visible to the player.
	float edge_glow = smoothstep(0.12, 0.0, UV.y) * 0.6;

	// Subtle pulsing tied to TIME so the stream feels alive.
	float pulse = 0.85 + 0.15 * sin(TIME * 5.0);

	float brightness = radial * length_fade * (n * 1.4 + 0.3) * pulse;
	// Add crackle arcs — strongest at mid-range, fading at muzzle/tip.
	float arc_mask = smoothstep(0.0, 0.3, 1.0 - UV.y) * smoothstep(0.0, 0.15, UV.y);
	brightness += crackle * arc_mask * 0.5;
	// Leading edge contribution.
	brightness += edge_glow * radial;
	brightness = clamp(brightness * intensity, 0.0, 2.0);

	// Core/body color blend.
	float core_blend = smoothstep(0.35, 0.9, brightness);
	vec3 col = mix(flame_color, inner_color, core_blend);
	// Crackle arcs tint toward white for contrast.
	col = mix(col, vec3(1.0), crackle * arc_mask * 0.4);

	// Wall clip — discard pixels beyond the wall distance. Soft edge
	// over a narrow band so the cutoff doesn't look razor-sharp.
	float clip_fade = smoothstep(clip_ratio, clip_ratio + 0.04, UV.y);
	brightness *= clip_fade;

	ALBEDO = col * brightness * 1.6;
	ALPHA = clamp(brightness * 1.1, 0.0, 1.0);
}
