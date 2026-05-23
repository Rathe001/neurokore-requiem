// Hammer crater PBR + radial alpha vignette.
//
// The crater glb carries full PBR maps (albedo / normal / roughness).
// Without an alpha mask, the mesh silhouette reads as a hard sticker
// dropped onto the floor. This shader reuses the original PBR maps
// but softens the silhouette via a radial alpha mask computed in
// OBJECT space — distance from the mesh's local origin in the XZ
// plane, normalised by `fade_radius`. Smoothstep from
// `vignette_start` → `vignette_end` fades the edges so the crater
// melts into the surrounding floor texture.
//
// fade_radius is set per-spawn by PrototypeAttackIndicator.spawn_hammer_crater
// (= measured half-footprint of the mesh AABB after the inner glb
// transforms are accounted for). `fade` is the lifetime-tween driver
// (1 = full opacity → 0 = invisible).
//
// Object-space radial mask beats UV-radial here because the imported
// glb's UVs are sculpted-mesh-style (non-radial; islands scattered
// for texel density). VERTEX.xz is layout-agnostic.
//
// (Prior contents of this file were a procedural diffused-crater
// shader — replaced when the PBR model swap landed.)

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D roughness_tex : hint_roughness_r, filter_linear_mipmap;
uniform vec3 albedo_tint : source_color = vec3(1.0);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float fade_radius : hint_range(0.5, 100.0) = 20.0;
uniform float vignette_start : hint_range(0.0, 1.0) = 0.45;
uniform float vignette_end : hint_range(0.0, 1.0) = 0.85;

// Pass model-local vertex position from vertex → fragment. In Godot 4
// spatial shaders, the built-in VERTEX in the fragment() function is in
// VIEW space, not model space — so reading VERTEX.xz there gives a
// camera-relative coord that has nothing to do with the mesh layout.
// Capturing it in vertex() (where VERTEX is still model-local) and
// passing it through as a varying gets us the mesh-local position we
// need for the radial mask.
varying vec3 v_local_pos;

void vertex() {
	v_local_pos = VERTEX;
}

void fragment() {
	vec4 col = texture(albedo_tex, UV);
	vec3 nrm = texture(normal_tex, UV).xyz;
	float rough = texture(roughness_tex, UV).r;

	// Local-space radial fade. Mesh origin = centre (Blender export
	// convention), so r = 0 at centre, r = 1 at fade_radius units out
	// in the XZ plane of the mesh's own coordinate frame.
	float r = length(v_local_pos.xz) / max(fade_radius, 0.001);
	float mask = 1.0 - smoothstep(vignette_start, vignette_end, r);

	ALBEDO = col.rgb * albedo_tint;
	NORMAL_MAP = nrm;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	ALPHA = mask * fade;
}
