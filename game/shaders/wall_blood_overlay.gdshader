// Wall blood overlay — density-gradient + wet-sheen realism pass.
// Two masks: mask_x covers ±X-facing walls (indexed by (z, y)),
// mask_z covers ±Z-facing walls (indexed by (x, y)). Wall's world
// normal picks which mask to sample.
//
// Like the floor shader (liquid_surface.gdshader) the same blob
// reads pink-translucent at the edges and near-opaque dark burgundy
// at the dense core, driven by mask coverage value. Adds a wet-sheen
// normal perturbation so dense blood reflects lights with a glossy
// highlight instead of looking like flat paint.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled;

uniform sampler2D mask_x : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D mask_z : filter_linear, repeat_disable, hint_default_black;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D surface_noise : hint_normal, filter_linear, repeat_enable;
// Raw noise for density modulation (organic mottled boundaries vs.
// smooth-circle blobs). See liquid_surface.gdshader for matching pair.
uniform sampler2D shape_noise : hint_default_white, filter_linear, repeat_enable;
uniform float shape_noise_scale : hint_range(1.0, 64.0) = 14.0;
uniform float shape_noise_strength : hint_range(0.0, 1.0) = 0.35;
uniform float world_extent_xz : hint_range(8.0, 200.0) = 40.0;
uniform float wall_height : hint_range(1.0, 16.0) = 4.0;

// Two-color density gradient (matches floor shader uniforms).
//   blood_thin  = THIN/edge tint (dark burgundy stain, translucent)
//   blood_dense = DENSE/core tint (near-black, opaque)
// Thin intentionally NOT bright pink — only very-fine-spray blood
// reads pink in real life; stained surfaces read as dark red.
uniform vec3 blood_thin : source_color = vec3(0.32, 0.08, 0.10);
uniform vec3 blood_dense : source_color = vec3(0.06, 0.015, 0.025);
uniform float density_power : hint_range(0.3, 4.0) = 0.9;
uniform float density_full : hint_range(0.2, 2.0) = 1.25;
uniform float density_opacity_max : hint_range(0.4, 1.0) = 0.92;
// Alpha floor at thinnest visible edge. Raised from 0 so small per-hit
// droplets (which can't accumulate to dense) stay readable. With the
// darker fresh tint, thin areas read as faint dark stain, not as a
// bright pink ring.
uniform float alpha_min : hint_range(0.0, 0.5) = 0.32;

uniform float stain_brightness : hint_range(0.5, 4.0) = 2.0;
// Threshold raised vs. the original 0.015 to gate trail-end haze
// that, combined with solid_opacity, used to paint visible bars
// along mask rows where stamps had clustered.
uniform float coverage_threshold : hint_range(0.0, 0.5) = 0.05;
uniform float edge_softness : hint_range(0.0, 0.3) = 0.10;
uniform float blood_roughness : hint_range(0.0, 1.0) = 0.26;
// 0 = pure multiply-stain at thinnest edge. Density scales up from
// here toward density_opacity_max in the dense core.
uniform float solid_opacity : hint_range(0.0, 1.0) = 0.0;

// Wet-sheen tuning (same shape as the floor's normal map sampling).
// Dialed down so highlights read as a subtle wet film instead of a
// glass-bright reflection.
uniform float normal_strength : hint_range(0.0, 2.0) = 0.04;
uniform float noise_scale : hint_range(0.5, 32.0) = 5.0;
uniform float specular_intensity : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec2 v_quad_uv;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_quad_uv = UV;
}

void fragment() {
	float a;
	float half_h = 0.5;
	if (abs(v_world_normal.x) > abs(v_world_normal.z)) {
		vec2 uv = vec2(
			v_world_pos.z / world_extent_xz + half_h,
			1.0 - v_world_pos.y / wall_height
		);
		a = texture(mask_x, uv).a;
	} else {
		vec2 uv = vec2(
			v_world_pos.x / world_extent_xz + half_h,
			1.0 - v_world_pos.y / wall_height
		);
		a = texture(mask_z, uv).a;
	}
	if (a < coverage_threshold) {
		discard;
	}
	float coverage = min(a, 1.0);
	float blood_alpha = smoothstep(coverage_threshold, coverage_threshold + edge_softness, coverage);
	// Density factor — 0 at edge of blob, 1 in saturated core. Drives
	// color, opacity, roughness, and normal perturbation strength.
	// Spatial noise modulation breaks the smooth-circle silhouette and
	// the dense/thin transition into organic mottled patches.
	float density = pow(
		smoothstep(coverage_threshold, density_full, coverage),
		density_power
	);
	float noise = texture(shape_noise, v_quad_uv * shape_noise_scale).r;
	float shape_mod = mix(1.0 - shape_noise_strength, 1.0 + shape_noise_strength, noise);
	density = clamp(density * shape_mod, 0.0, 1.0);

	vec3 blood_color = mix(blood_thin, blood_dense, density);

	// Multiply-stain × screen behind. Edges tint the wall pinkish,
	// dense centers nearly cover it.
	vec3 behind = texture(screen_tex, SCREEN_UV).rgb;
	vec3 stained_mul = behind * blood_color * stain_brightness;
	float opacity_here = mix(solid_opacity, density_opacity_max, density);
	vec3 stained = mix(stained_mul, blood_color, opacity_here);

	// Wet sheen — two-octave static noise normal map. Sampled in
	// quad-UV space (each wall is a flat QuadMesh) so the noise tiles
	// consistently regardless of wall size. Strength scales with
	// density so only the dense blood gets the glossy "wet" reflection.
	vec2 n_uv1 = v_quad_uv * noise_scale;
	vec2 n_uv2 = v_quad_uv * noise_scale * 2.3 + vec2(13.7, 5.1);
	vec3 n1 = texture(surface_noise, n_uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(surface_noise, n_uv2).rgb * 2.0 - 1.0;
	vec3 n_mixed = normalize(n1 * 0.6 + n2 * 0.4);
	NORMAL_MAP = vec3(n_mixed.xy * 0.5 + 0.5, 1.0);
	NORMAL_MAP_DEPTH = normal_strength * mix(0.3, 1.0, density);

	ALBEDO = stained;
	ROUGHNESS = mix(0.75, blood_roughness, density);
	METALLIC = 0.0;
	SPECULAR = specular_intensity * mix(0.15, 1.0, density);
	// ALPHA driven by density so thin pinkish edges fade to transparent
	// (wall shows through) and only the dense dark core stays opaque.
	// blood_alpha keeps the perimeter discard edge anti-aliased.
	ALPHA = blood_alpha * mix(alpha_min, 1.0, density);
}
