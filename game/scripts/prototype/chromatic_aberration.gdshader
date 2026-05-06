shader_type canvas_item;

// RGB-split / chromatic aberration screen effect. Sample the screen texture
// three times: red shifted toward screen center, blue shifted away, green
// centered. Magnitude scales with distance from screen center (radial bias)
// so the effect reads as lens distortion at speed instead of a flat global
// offset that would just look like a broken display.
//
// `strength` is in normalized screen units (1.0 = full screen width). At
// 1080p, strength=0.003 ≈ 3.5px peak shift at the screen edges.
//
// `radial_power` shapes the falloff: 1.0 = linear from center, 2.0 =
// quadratic (center is "clean", edges hit harder). The default 2.0 keeps
// the player-centered area readable while pushing the visual cue outward.

// Godot 4 removed the canvas_item SCREEN_TEXTURE built-in — we declare it
// as a uniform with hint_screen_texture, which the renderer auto-binds to
// the back-buffer. repeat_disable + filter_linear keep edge sampling clean
// when the offset pulls a sample slightly out of bounds.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

uniform float strength : hint_range(0.0, 0.02) = 0.0;
uniform float radial_power : hint_range(1.0, 4.0) = 1.4;

void fragment() {
	vec2 from_center = SCREEN_UV - vec2(0.5);
	float radial = pow(length(from_center) * 2.0, radial_power);
	vec2 dir = normalize(from_center + vec2(0.0001));
	vec2 offset = dir * strength * radial;

	vec4 r = texture(screen_texture, SCREEN_UV - offset);
	vec4 g = texture(screen_texture, SCREEN_UV);
	vec4 b = texture(screen_texture, SCREEN_UV + offset);

	COLOR = vec4(r.r, g.g, b.b, 1.0);
}
