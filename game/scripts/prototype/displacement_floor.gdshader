// Real geometric displacement for flat floor planes. PBR sampling via
// world-space XZ UVs (matches StandardMaterial3D triplanar at scale 0.2)
// so the result lines up with any neighbouring non-displaced surfaces.
//
// Requires the consumer PlaneMesh to set subdivide_width/depth — without
// them the mesh is 4 corner verts and there's nothing to displace.
//
// Cost is one extra texture sample in the vertex shader. Negligible on
// modern GPUs even at horde density; the real perf hit is the increased
// vertex count from subdivision.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_texture : hint_roughness_r, filter_linear_mipmap_anisotropic;
uniform sampler2D metallic_texture : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D height_texture : hint_default_white, filter_linear_mipmap_anisotropic;

uniform float uv_scale : hint_range(0.05, 1.0) = 0.2;
uniform float normal_strength : hint_range(0.0, 6.0) = 3.0;
uniform float displacement_strength : hint_range(0.0, 0.5) = 0.3;
uniform float metallic_factor : hint_range(0.0, 1.0) = 0.35;
// Clamp roughness up at the floor — sub-pixel detail at iso distance
// would otherwise produce harsh specular flicker on bright metal areas.
uniform float roughness_floor : hint_range(0.0, 1.0) = 0.4;
// Bias subtracted from the heightmap sample before scaling. The Sci-Fi
// Vent3 heightmap has its "floor level" at mid-grey; without this the
// whole surface lifts uniformly by the strength and we lose half the
// visible depth range to a flat raise.
uniform float displacement_bias : hint_range(-1.0, 1.0) = 0.5;

varying vec2 floor_uv;

void vertex() {
    vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    floor_uv = world_pos.xz * uv_scale;
    float h = texture(height_texture, floor_uv).r;
    VERTEX.y += (h - displacement_bias) * displacement_strength;
}

void fragment() {
    ALBEDO = texture(albedo_texture, floor_uv).rgb;
    ROUGHNESS = max(texture(roughness_texture, floor_uv).r, roughness_floor);
    METALLIC = texture(metallic_texture, floor_uv).r * metallic_factor;
    NORMAL_MAP = texture(normal_texture, floor_uv).rgb;
    NORMAL_MAP_DEPTH = normal_strength;
}
