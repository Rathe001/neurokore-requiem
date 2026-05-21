shader_type canvas_item;

// Screen-space silhouette outline. Reads a SubViewport texture that
// renders highlighted meshes as flat colors against transparent
// background. For each pixel that is OUTSIDE any highlighted mesh,
// check 8 neighbors — if any are inside, paint the outline color
// (preserved from the neighbor's color so different highlight tints
// — white for hover, red for tooltip-locked — render correctly).
//
// Pixels INSIDE a highlighted mesh stay transparent so the world
// view shows through; only the silhouette edge is painted.

uniform float outline_thickness : hint_range(0.5, 4.0) = 1.5;

void fragment() {
	vec4 here = texture(TEXTURE, UV);
	vec4 out_color = vec4(0.0);
	// Outline only on pixels OUTSIDE any highlighted mesh.
	if (here.a <= 0.1) {
		// Sample 8 neighbors at outline_thickness pixels out. If any
		// are inside a highlighted mesh, this pixel is on the
		// silhouette edge.
		vec2 px = TEXTURE_PIXEL_SIZE * outline_thickness;
		vec4 sum = vec4(0.0);
		sum += texture(TEXTURE, UV + vec2( px.x,  0.0));
		sum += texture(TEXTURE, UV + vec2(-px.x,  0.0));
		sum += texture(TEXTURE, UV + vec2( 0.0,  px.y));
		sum += texture(TEXTURE, UV + vec2( 0.0, -px.y));
		sum += texture(TEXTURE, UV + vec2( px.x,  px.y));
		sum += texture(TEXTURE, UV + vec2(-px.x,  px.y));
		sum += texture(TEXTURE, UV + vec2( px.x, -px.y));
		sum += texture(TEXTURE, UV + vec2(-px.x, -px.y));
		if (sum.a > 0.01) {
			// Normalise — preserves the highlight color from the
			// neighbor pixels regardless of how many were lit.
			out_color = vec4(sum.rgb / sum.a, 1.0);
		}
	}
	// Inside-mesh pixels stay transparent so the world view shows
	// through; only the silhouette edge gets painted.
	COLOR = out_color;
}
