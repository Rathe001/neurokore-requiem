shader_type canvas_item;

// Neon-tube silhouette outline. Reads the SubViewport texture that
// renders highlighted meshes as flat colors against a transparent
// background, then paints two layered passes:
//
//   1. CORE band — a tight ring (~1 pixel) right at the silhouette
//      edge. Output as the highlight color × `core_boost`, which
//      typically exceeds 1.0 in HDR. The level Environment has
//      glow_enabled = true, so values > 1 trigger bloom and the
//      band reads as a glowing neon tube rather than a flat line.
//
//   2. GLOW halo — a softer falloff extending several pixels outward
//      from the silhouette. Same color, lower intensity. Sells the
//      "light spilling onto the air around the tube" look.
//
// Both passes preserve the source highlight color so different tints
// (enemy red, interactable cyan, door yellow) render correctly.
// Pixels INSIDE the silhouette stay transparent so the world view
// shows through — only the surrounding tube + glow is painted.

uniform float core_thickness : hint_range(0.5, 3.0) = 1.2;
uniform float glow_radius : hint_range(2.0, 14.0) = 6.0;
uniform float core_boost : hint_range(1.0, 12.0) = 5.5;
uniform float glow_boost : hint_range(0.3, 4.0) = 1.4;

// (Godot's shading language reserves `TAU` as a builtin in some
// passes — redeclaring it caused the canvas_item shader to fail to
// compile and the engine fell back to the default. Inline the constant
// instead.)

void fragment() {
	vec4 here = texture(TEXTURE, UV);
	// Inside the silhouette → leave transparent so the world shows
	// through. Godot 4 canvas_item shaders disallow `return` in
	// fragment(), so the early-out is restructured as an else-branch
	// rather than `if (cond) { COLOR = ...; return; }`.
	if (here.a > 0.5) {
		COLOR = vec4(0.0);
	} else {
		vec2 px = TEXTURE_PIXEL_SIZE;

		// Two-tap, 8-direction sampling: one ring at core_thickness for
		// the bright tube band, one at glow_radius for the soft halo.
		// 16 samples per pixel — cheap enough at 1080p.
		float core_mask = 0.0;
		vec3 core_color = vec3(0.0);
		float glow_mask = 0.0;
		vec3 glow_color = vec3(0.0);

		for (int i = 0; i < 8; i++) {
			float angle = float(i) * 6.28318530718 / 8.0;
			vec2 dir = vec2(cos(angle), sin(angle));

			vec4 c = texture(TEXTURE, UV + dir * px * core_thickness);
			core_mask += c.a;
			core_color += c.rgb * c.a;

			vec4 g = texture(TEXTURE, UV + dir * px * glow_radius);
			glow_mask += g.a;
			glow_color += g.rgb * g.a;
		}

		// Normalise — both masks now in [0, 1], colors weighted by mask.
		core_mask /= 8.0;
		glow_mask /= 8.0;
		if (core_mask > 0.001) {
			core_color /= core_mask * 8.0;
		}
		if (glow_mask > 0.001) {
			glow_color /= glow_mask * 8.0;
		}

		// Compose. Core color wins where the tube band is bright; the
		// outer halo uses the glow_color blend so each pixel reads as
		// the right hue. RGB intensity can exceed 1.0 so bloom picks
		// it up; alpha is clamped so we don't accidentally fade the
		// underlying world view at the halo's tail.
		vec3 col = mix(glow_color, core_color, core_mask);
		float core_intensity = core_mask * core_boost;
		float glow_intensity = glow_mask * glow_boost;
		float total = core_intensity + glow_intensity * 0.5;

		COLOR = vec4(col * total, clamp(total, 0.0, 1.0));
	}
}
