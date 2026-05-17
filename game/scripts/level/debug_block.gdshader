shader_type spatial;
// Debug visualization material for level kit pieces. Solid fill body with a
// FIXED-PIXEL emissive border traced around each UV-face perimeter. Pixel-
// width (not UV-fraction) border lets thin geometry (e.g. a 1m-wide wall
// top trapezoid) still show a clean outline at iso scale.
//
// Horizontal faces (wall tops, floor) detected via NORMAL.y get a much
// brighter fill so the iso camera can clearly read wall top geometry —
// without this, thin top trapezoids blend into the background and the wall
// looks like a plane. Mitre seams at wall corners pop as bright diagonals.

render_mode unshaded, cull_disabled;

uniform vec4 fill_color : source_color = vec4(0.10, 0.10, 0.13, 1.0);
// Fill color used when the face's normal points up (wall tops, floors).
// Brighter than `fill_color` so horizontal surfaces read at iso scale
// where they project to thin strips.
uniform vec4 top_fill_color : source_color = vec4(0.30, 0.30, 0.38, 1.0);
uniform vec4 border_color : source_color = vec4(0.0, 1.0, 1.0, 1.0);
uniform float border_width : hint_range(0.0, 16.0) = 2.0;
uniform float emission_strength : hint_range(0.0, 8.0) = 2.0;

void fragment() {
	vec2 uv = UV;
	vec2 fw = fwidth(uv) * border_width;
	vec2 d = min(uv, 1.0 - uv);
	float edge_x = 1.0 - smoothstep(0.0, fw.x, d.x);
	float edge_y = 1.0 - smoothstep(0.0, fw.y, d.y);
	float edge = max(edge_x, edge_y);
	// Branch on face orientation: horizontal-up = top fill, otherwise side fill.
	vec3 face_fill = mix(fill_color.rgb, top_fill_color.rgb, step(0.5, NORMAL.y));
	vec3 base = mix(face_fill, border_color.rgb, edge);
	ALBEDO = base + border_color.rgb * edge * emission_strength;
}
