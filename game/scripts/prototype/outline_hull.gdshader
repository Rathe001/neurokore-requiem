// Inverted-hull outline.
//
// Vertex stage extrudes each vertex along its normal by `outline_width`
// metres (in mesh-local space). The fragment stage paints the result
// in `outline_color` × intensity, unshaded. render_mode cull_front
// means only the BACK faces of the inflated hull render — those land
// behind the original mesh from the camera's POV, peeking out at the
// silhouette edge to form the outline ring.
//
// Used by OutlineCompositor as a per-mesh material_overlay (Godot 4's
// MeshInstance3D-level second-pass material). One ShaderMaterial per
// outlined mesh; no SubViewport, no camera mirroring, no skin/skeleton
// routing — the overlay runs through the same vertex pipeline as the
// source mesh's main material, so skinned characters inflate their
// per-frame skinned pose automatically.
//
// Replaces the previous SubViewport-based outline compositor: that
// approach broke for skinned-mesh-under-Skeleton3D children where the
// duplicated MeshInstance3D's skin/skeleton routing didn't survive
// being parented under the skeleton.

shader_type spatial;
// cull_front = render BACK faces of the inflated hull (the visible
// silhouette edge from any camera angle).
// unshaded so the outline reads as a flat color regardless of scene
// lighting.
// depth_draw_opaque + depth_test enabled so the hull respects
// occlusion — outlines hide behind walls correctly.
render_mode unshaded, cull_front, depth_draw_opaque;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// Hull expansion distance in metres along the local-space normal.
// 0.02 reads as a thin silhouette from the iso camera; 0.04+ starts
// looking like a thick comic-book outline.
uniform float outline_width : hint_range(0.0, 0.10) = 0.025;
// EMISSION intensity — pushed above 1.0 so the level's bloom env amp
// picks up the outline color and adds a subtle glow halo. Set to 0
// for a flat un-glowing outline.
uniform float emission_boost : hint_range(0.0, 4.0) = 1.5;

void vertex() {
	VERTEX += NORMAL * outline_width;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	EMISSION = outline_color.rgb * emission_boost;
	ALPHA = outline_color.a;
}
