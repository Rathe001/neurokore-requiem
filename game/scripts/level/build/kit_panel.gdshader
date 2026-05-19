shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Spatial shader applied to kit wall/floor panels in place of the
// StandardMaterial3D that ships in the .glb. It does two jobs:
//
//   1. Standard PBR shading — sample albedo/normal/roughness textures and
//      set the engine's PBR slots so lighting still works the way it would
//      with BaseMaterial3D.
//   2. Per-instance 45° mitre clip — discard fragments outside a 45° plane
//      at the panel's mitred ends. Mitre flags + per-instance scale are
//      packed into INSTANCE_CUSTOM so each MultiMesh instance can opt into
//      clipping independently and the clip stays at 45° in WORLD coords:
//        INSTANCE_CUSTOM.x = 1.0 → clip the LEFT end (-X face)
//        INSTANCE_CUSTOM.y = 1.0 → clip the RIGHT end (+X face)
//        INSTANCE_CUSTOM.z = scale_w (the per-instance Transform3D X-scale)
//        INSTANCE_CUSTOM.w = unused (reserved)
//      Without scale_w the cut would only be 45° in mesh-local space, which
//      is only 45° in world when scale_w = 1.0 (rare — panels get stretched
//      to fit the wall length evenly).
//
// `half_length` and `half_thickness` are set from the mesh AABB by the
// post-import script, in mesh-local space. The clip line runs at 45° in
// local coords from (half_length, 0) at the centerline to
// (half_length - half_thickness, ±half_thickness) at the panel's outer
// faces — a tiny triangular bite that resolves visual overlap between
// perpendicular walls meeting at a corner.

// Anisotropic filtering is already enabled globally via
// project.godot/textures/default_filters/anisotropic_filtering_level — so
// no per-sampler filter hint is needed here.
//
// `hint_default_white` makes each sampler return solid white when nothing
// is bound — Blenderkit assets vary: some ship full PBR maps (albedo +
// normal + roughness), others ship a colored BaseMaterial3D with no
// textures at all (e.g. stylized models that rely on mesh geometry for
// detail). Without the default-white hint, sampling an unbound sampler2D
// returns undefined GPU memory, which renders as garbled black/white
// shapes per panel. With it, untextured assets fall through to the
// `albedo_color` uniform below.
// All three samplers are always bound by the post-import script — when
// the source BaseMaterial3D lacks a channel, a 1x1 white fallback texture
// is bound. (We can't combine hint_default_* with hint_normal /
// hint_roughness_gray in Godot 4 — they're mutually exclusive hint
// categories, so the binding has to happen at the material level.)
uniform sampler2D albedo_tex : source_color;
uniform sampler2D normal_tex : hint_normal;
uniform sampler2D roughness_tex : hint_roughness_gray;

// Source material's albedo_color, copied by the post-import script.
// Multiplied with the albedo texture sample so:
//   textured asset: albedo_color = white, texture provides the color
//   untextured asset: albedo_tex defaults to white, color drives the look
uniform vec3 albedo_color : source_color = vec3(1.0);

uniform float normal_strength : hint_range(0.0, 2.0) = 0.3;
uniform float metallic_factor : hint_range(0.0, 1.0) = 0.1;
uniform float roughness_factor : hint_range(0.0, 2.0) = 0.85;

uniform float half_length = 1.0;
uniform float half_thickness = 0.0125;

// INSTANCE_CUSTOM is only readable in the vertex stage in Godot 4; pass
// the mitre flags through a varying to use them in fragment.
varying vec3 v_local;
varying vec4 v_custom;

void vertex() {
	v_local = VERTEX;
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	// World-space 45° clip. Local X is scaled by scale_w (= v_custom.z),
	// local Y is unscaled (no Y stretch in the per-instance Transform3D).
	// To make a 45° cut in WORLD coords we compare scaled X against the
	// world-scaled half_length. Equivalent: in pure world coords,
	//   discard if (world_x + |world_y|) > world_half_length
	// where world_x = local_x * scale_w, world_y = local_y, and
	// world_half_length = half_length * scale_w.
	float scale_w = max(v_custom.z, 0.0001);
	float wx = v_local.x * scale_w;
	float wy = abs(v_local.y);
	float w_half_length = half_length * scale_w;
	if (v_custom.y > 0.5 && (wx + wy) > w_half_length) {
		discard;
	}
	if (v_custom.x > 0.5 && (-wx + wy) > w_half_length) {
		discard;
	}

	vec4 albedo = texture(albedo_tex, UV);
	ALBEDO = albedo.rgb * albedo_color;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = texture(roughness_tex, UV).r * roughness_factor;
	METALLIC = metallic_factor;
}
