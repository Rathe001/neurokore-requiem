shader_type canvas_item;

// Neon-tube silhouette outline. Reads the SubViewport texture that
// renders highlighted meshes as flat colors against a transparent
// background. Paints two unrolled 8-direction passes:
//
//   1. CORE band — close to the silhouette (core_thickness px). If
//      any neighbor is inside the silhouette, paint the highlight
//      color at HDR intensity (`core_boost`). Bloom in the level
//      Environment kicks in for values > 1 and the band reads as
//      a glowing tube.
//
//   2. GLOW halo — farther out (glow_radius px). Soft fade by how
//      many neighbors sit inside. Sells the air-glow around the tube.
//
// Loop-free / explicit 8-direction sampling: Godot 4's canvas_item
// shader compiler has been spotty about for-loop unrolling, and
// the previous loop-based rewrite stopped rendering at all on this
// pipeline. Hard-unrolled compass + diagonal taps match the
// pre-rewrite sobel pattern that was reliably visible.

uniform float core_thickness : hint_range(0.5, 4.0) = 1.5;
uniform float glow_radius : hint_range(2.0, 14.0) = 5.5;
uniform float core_boost : hint_range(1.0, 12.0) = 5.0;
uniform float glow_boost : hint_range(0.3, 4.0) = 1.6;

void fragment() {
	vec4 here = texture(TEXTURE, UV);
	vec4 out_color = vec4(0.0);
	// Paint OUTSIDE the silhouette only. Inside stays transparent so
	// the world view shows through. canvas_item shaders disallow
	// `return` from fragment, so the early-out is folded into the if.
	if (here.a <= 0.1) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		vec2 cpx = px * core_thickness;
		vec2 gpx = px * glow_radius;

		// CORE ring — 8 explicit taps at core_thickness px.
		vec4 core_sum = vec4(0.0);
		core_sum += texture(TEXTURE, UV + vec2( cpx.x,  0.0));
		core_sum += texture(TEXTURE, UV + vec2(-cpx.x,  0.0));
		core_sum += texture(TEXTURE, UV + vec2( 0.0,  cpx.y));
		core_sum += texture(TEXTURE, UV + vec2( 0.0, -cpx.y));
		core_sum += texture(TEXTURE, UV + vec2( cpx.x,  cpx.y));
		core_sum += texture(TEXTURE, UV + vec2(-cpx.x,  cpx.y));
		core_sum += texture(TEXTURE, UV + vec2( cpx.x, -cpx.y));
		core_sum += texture(TEXTURE, UV + vec2(-cpx.x, -cpx.y));

		// GLOW ring — 8 explicit taps at glow_radius px.
		vec4 glow_sum = vec4(0.0);
		glow_sum += texture(TEXTURE, UV + vec2( gpx.x,  0.0));
		glow_sum += texture(TEXTURE, UV + vec2(-gpx.x,  0.0));
		glow_sum += texture(TEXTURE, UV + vec2( 0.0,  gpx.y));
		glow_sum += texture(TEXTURE, UV + vec2( 0.0, -gpx.y));
		glow_sum += texture(TEXTURE, UV + vec2( gpx.x,  gpx.y));
		glow_sum += texture(TEXTURE, UV + vec2(-gpx.x,  gpx.y));
		glow_sum += texture(TEXTURE, UV + vec2( gpx.x, -gpx.y));
		glow_sum += texture(TEXTURE, UV + vec2(-gpx.x, -gpx.y));

		if (core_sum.a > 0.01) {
			// Right at the tube — alpha-weighted average of neighbor
			// colors × HDR boost. Bloom blooms it.
			vec3 col = core_sum.rgb / core_sum.a;
			out_color = vec4(col * core_boost, 1.0);
		} else if (glow_sum.a > 0.01) {
			// Soft halo zone — same color, dimmer, mask-faded so the
			// halo tapers out smoothly.
			vec3 col = glow_sum.rgb / glow_sum.a;
			float falloff = clamp(glow_sum.a / 8.0, 0.0, 1.0);
			out_color = vec4(col * glow_boost * falloff, falloff);
		}
	}
	COLOR = out_color;
}
