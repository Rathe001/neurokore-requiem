shader_type spatial;
// cull_disabled: the mitred trapezoidal wall's end caps are diagonal
// faces whose "outward" normal isn't a clean +X/-X or +Z/-Z direction —
// it's at 45° in XZ. From an iso camera angle, one half of the room's
// corners look at the cap's front face and the other half look at its
// back, so any single cull_back orientation hides caps somewhere. Drawing
// both sides ensures every corner is sealed regardless of camera angle.
// Cost is minimal (the shader is fragment-bound, not vertex-bound) and
// adjacent walls' coincident caps z-fight invisibly because they share
// world-aligned panel UVs through the same shader.
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Procedural worn-steel wall panel shader. Applied to the flat mitred wall
// mesh produced by WallBuilder.build_room_mesh. Single shader covers all
// theme rooms; tunable via uniforms.
//
// Visual stack:
//   1. World-aligned 1m panel grid (rooms can be axis-aligned along X or Z;
//      panels stay consistent across both orientations).
//   2. Carved seams at each panel edge — both ALBEDO darkens AND NORMAL
//      perturbs into a depression so lighting reads it as actual depth,
//      not paint.
//   3. Per-panel albedo variation via hash on the cell index, so adjacent
//      panels read as separate steel slabs of slightly different age/wear.
//   4. Surface wear noise: dirty patches darken albedo and shift roughness
//      up (worn metal = duller specular than polished metal).
//   5. Micro-scratch noise perturbs the surface normal at sub-cm scale,
//      breaking up specular reflections on the panel faces.
//
// All bevel/wear math lives in the fragment shader using `wall_uv` derived
// from world position + the orientation of the wall's outward normal. No
// tangent attribute on the mesh — we build the world-space perturbed
// normal directly from the height-field gradient.

uniform vec3 base_color : source_color = vec3(0.22, 0.24, 0.28);
uniform vec3 seam_color : source_color = vec3(0.03, 0.04, 0.05);
// Panel cell size in world meters. 1m matches the level grid the rest of
// the build system uses.
uniform float panel_size_x : hint_range(0.1, 4.0) = 1.0;
uniform float panel_size_y : hint_range(0.1, 4.0) = 1.0;
// Distance from panel edge to the seam centerline. ~2cm reads cleanly at
// the iso angle.
uniform float seam_width : hint_range(0.0, 0.1) = 0.02;
// Bevel width — how far the seam "ramp" extends inward from seam_width.
// Larger = softer transition. The normal perturbation is concentrated
// inside this ramp.
uniform float seam_bevel : hint_range(0.01, 0.2) = 0.05;
// Depth of the carved seam (controls the strength of the normal kick).
// 0.0 = paint-on, 0.2 = obvious gouge.
uniform float seam_depth : hint_range(0.0, 0.5) = 0.15;
// Per-panel albedo variation (0 = all identical).
uniform float panel_variation : hint_range(0.0, 0.5) = 0.15;

// PBR. Reflective worn steel — push metallic up and roughness down to
// catch sharp specular highlights from the ceiling fluorescents (the main
// light source on every wall), while keeping enough surface variation
// that it reads as worn rather than chrome. METALLIC = 0 in the seam
// (dirt accumulates there).
uniform float metallic_value : hint_range(0.0, 1.0) = 0.75;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.32;
uniform float roughness_wear : hint_range(0.0, 0.6) = 0.18;
uniform float wear_albedo_strength : hint_range(0.0, 1.0) = 0.4;
uniform float wear_noise_scale : hint_range(0.5, 16.0) = 6.0;
// Sub-cm scratch noise that perturbs the normal — too small to read as
// macro features but adds character to the specular highlights. Kept
// modest so reflections stay sharp rather than getting broken into noise.
uniform float scratch_strength : hint_range(0.0, 1.0) = 0.25;
uniform float scratch_scale : hint_range(8.0, 128.0) = 48.0;

// Pixel-scale albedo jitter. Multiplied into final ALBEDO as ±strength
// brightness noise at very high frequency (~120 cycles per meter ≈ sub-cm
// in world space). The amplitude is too low to read as a visual feature
// — but it gives Godot's debanding dither something to hide inside, so
// the dither pattern doesn't show through on smooth bright surfaces
// (which it does when ALBEDO is uniform across many pixels). Effectively
// "natural surface noise" to mask the engine's quantization mitigation.
uniform float micro_albedo_strength : hint_range(0.0, 0.2) = 0.05;
uniform float micro_albedo_scale : hint_range(40.0, 400.0) = 140.0;

// Splotch / grime patches. Separate from the small-scale wear noise:
// these are meter-scale stains with thresholded edges so they read as
// distinct dirty patches instead of smooth tint variation. Inside a
// splotch, ALBEDO darkens, ROUGHNESS climbs (matte dirt instead of
// polished steel), and METALLIC drops (organic muck doesn't reflect).
// Strength tuned higher on the floor (foot traffic, spills) than the
// walls (relatively clean by comparison).
uniform float splotch_strength : hint_range(0.0, 1.0) = 0.0;
uniform float splotch_scale : hint_range(0.2, 4.0) = 1.4;
uniform float splotch_threshold : hint_range(0.2, 0.8) = 0.55;
uniform vec3 splotch_color : source_color = vec3(0.06, 0.05, 0.04);

// Raised border lip running around each panel face. Sits between the
// seam bevel and the open panel face — reads as a thin welded/stamped
// frame around the tile. Catches its own specular highlight separate
// from the panel face and the seam.
uniform float border_height : hint_range(0.0, 0.2) = 0.04;
uniform float border_width : hint_range(0.0, 0.2) = 0.05;
uniform vec3 border_color : source_color = vec3(0.30, 0.32, 0.36);

// Rivets: small circular domes at the 4 inset corners of every panel.
// rivet_inset is how far into the panel face from the edge each rivet
// sits; rivet_radius is the dome footprint; rivet_height is the dome
// rise. Set rivet_radius to 0 to disable.
uniform float rivet_inset : hint_range(0.0, 0.5) = 0.10;
uniform float rivet_radius : hint_range(0.0, 0.2) = 0.035;
uniform float rivet_height : hint_range(0.0, 0.1) = 0.02;
uniform vec3 rivet_color : source_color = vec3(0.42, 0.44, 0.48);

// ── Architectural trim ───────────────────────────────────────────────────
// Universal trim features that frame every wall. Identical across all
// themes — they're the structural silhouette, not a per-zone variation.
// Skipped on floors (no vertical extent to anchor against).
//
// Baseboard: a darker, slightly recessed band at the bottom of every wall.
// Catches grime; reads as the kick-plate / dirt-line you find in any
// industrial corridor. Disable with baseboard_height = 0.
uniform float baseboard_height : hint_range(0.0, 0.5) = 0.18;
uniform float baseboard_bevel : hint_range(0.0, 0.1) = 0.02;
uniform float baseboard_recess : hint_range(0.0, 0.05) = 0.008;
uniform float baseboard_roughness_boost : hint_range(0.0, 0.6) = 0.22;
uniform vec3 baseboard_color : source_color = vec3(0.11, 0.12, 0.14);
// Chair rail: a thin raised band running horizontally at chair_rail_y.
// Acts as a horizontal silhouette break across every wall — the single
// feature that does the most to stop "slab of metal" reads. Profile is
// a smooth bell so it catches a thin specular highlight at iso angles.
// Disable with chair_rail_thickness = 0.
uniform float chair_rail_y : hint_range(0.5, 2.5) = 1.05;
uniform float chair_rail_thickness : hint_range(0.0, 0.2) = 0.06;
uniform float chair_rail_lip : hint_range(0.0, 0.05) = 0.012;
uniform vec3 chair_rail_color : source_color = vec3(0.34, 0.36, 0.40);

// ── Theme tints ──────────────────────────────────────────────────────────
// Per-zone modulation off the base. Defaults are identity so theme=null
// (or any theme that doesn't set these) renders the neutral base. Keep
// deltas SUBTLE — the goal is family resemblance across rooms, not
// wholesale palette swaps. Hard transitions only happen at corridor
// boundaries (corridors stay on the neutral base by design).
uniform vec3 tint_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float wear_offset : hint_range(-0.5, 0.5) = 0.0;
uniform float metallic_offset : hint_range(-0.3, 0.3) = 0.0;
uniform float roughness_offset : hint_range(-0.3, 0.3) = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 2D hash → [0, 1).
float hash21(vec2 p) {
	p = fract(p * vec2(443.8975, 397.2973));
	p += dot(p.yx, p.xy + 19.19);
	return fract(p.x * p.y);
}

// Bilinear-smoothed value noise. Good enough for surface wear.
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Two-octave noise for richer wear.
float fbm2(vec2 p) {
	return vnoise(p) * 0.6 + vnoise(p * 2.3 + 17.0) * 0.4;
}

// Returns a 1-at-center, 0-at-edges trapezoidal mask for the chair rail at
// world height `world_y`. Centered on `chair_rail_y`, total band thickness
// `chair_rail_thickness`. Smooth transitions on each side so the gradient
// reads as a bevel rather than a step.
float chair_rail_mask(float world_y) {
	if (chair_rail_thickness <= 0.0) {
		return 0.0;
	}
	float rail_half = chair_rail_thickness * 0.5;
	float rail_dist = abs(world_y - chair_rail_y);
	return 1.0 - smoothstep(rail_half * 0.55, rail_half, rail_dist);
}


// Returns a 1-below, 0-above mask for the baseboard at world height
// `world_y`. Smoothstep gives a bevel at the top edge so the normal kicks
// outward (catches a thin highlight) where the baseboard meets the panel
// face above.
float baseboard_mask(float world_y) {
	if (baseboard_height <= 0.0) {
		return 0.0;
	}
	return 1.0 - smoothstep(baseboard_height, baseboard_height + baseboard_bevel, world_y);
}


// Surface height field. Combines:
//   - Seam depression (negative h, runs around panel edges)
//   - Raised border lip (positive h, sits just inside the seam)
//   - Rivet domes (positive h, 4 per panel at inset corners)
//   - Chair rail (positive h, horizontal band — walls only)
//   - Baseboard recess (negative h, lower band — walls only)
//
// `is_wall` gates the trim contributions; floors share the shader but
// don't have a meaningful vertical anchor for baseboard/chair rail.
// Returns the world-space height offset from the geometric plane. Used
// both by the albedo blend (deciding what color a fragment is) and the
// finite-difference normal perturbation (gradient-based bevel direction).
float surface_height(vec2 wall_uv, bool is_wall) {
	vec2 panel = vec2(panel_size_x, panel_size_y);
	vec2 cell_uv = fract(wall_uv / panel);
	vec2 edge_dist01 = min(cell_uv, 1.0 - cell_uv);
	vec2 edge_dist_m = edge_dist01 * panel;
	float min_edge = min(edge_dist_m.x, edge_dist_m.y);

	// Seam depression — 1 inside seam, 0 on panel face.
	float seam_inv = 1.0 - smoothstep(seam_width, seam_width + seam_bevel, min_edge);
	float h = -seam_inv * seam_depth;

	// Raised border lip — a smooth bump that peaks between the seam and
	// the panel face. Modeled as a triangular ramp: rises from the outer
	// edge of the seam bevel, peaks at the lip centerline, falls back to
	// face level at border_width past the seam.
	float lip_outer = seam_width + seam_bevel;
	float lip_inner = lip_outer + border_width;
	float lip_t = 1.0 - abs((min_edge - (lip_outer + lip_inner) * 0.5)
		/ max(border_width * 0.5, 0.001));
	lip_t = clamp(lip_t, 0.0, 1.0);
	// Only contributes between lip_outer and lip_inner.
	float lip_mask = step(lip_outer, min_edge) * step(min_edge, lip_inner);
	h += lip_t * lip_mask * border_height;

	// Rivet domes at the 4 inset corners. cell_m is the fragment's
	// position within its cell in world meters; rivet_pos picks the
	// nearest of the 4 inset rivet centers.
	if (rivet_radius > 0.0) {
		vec2 cell_m = cell_uv * panel;
		vec2 rivet_pos;
		rivet_pos.x = cell_m.x < panel.x * 0.5 ? rivet_inset : panel.x - rivet_inset;
		rivet_pos.y = cell_m.y < panel.y * 0.5 ? rivet_inset : panel.y - rivet_inset;
		float d = length(cell_m - rivet_pos);
		// Smooth dome: 1 at center, 0 at radius.
		float dome = 1.0 - smoothstep(0.0, rivet_radius, d);
		// Square it for a fuller bell-curve shape (avoids a too-conical
		// tip that aliases against the iso pixel grid).
		h += dome * dome * rivet_height;
	}

	// Trim — walls only. wall_uv.y IS world_y for walls (see fragment
	// shader's wall_uv assignment); for floors we'd be reading world_z
	// there, which doesn't correspond to "up" so trim is meaningless.
	if (is_wall) {
		float world_y = wall_uv.y;
		h += chair_rail_mask(world_y) * chair_rail_lip;
		h -= baseboard_mask(world_y) * baseboard_recess;
	}

	return h;
}

void fragment() {
	// Map the world position onto the surface's 2D plane. Three cases:
	//   - Floor (normal mostly ±Y): wall_uv = (world X, world Z)
	//   - Wall facing ±X: wall_uv = (world Z, world Y)
	//   - Wall facing ±Z: wall_uv = (world X, world Y)
	// The same shader covers all three so walls and floors share material.
	vec2 wall_uv;
	bool is_floor = abs(v_world_normal.y) > abs(v_world_normal.x)
		&& abs(v_world_normal.y) > abs(v_world_normal.z);
	if (is_floor) {
		wall_uv = vec2(v_world_pos.x, v_world_pos.z);
	} else if (abs(v_world_normal.x) > abs(v_world_normal.z)) {
		wall_uv = vec2(v_world_pos.z, v_world_pos.y);
	} else {
		wall_uv = vec2(v_world_pos.x, v_world_pos.y);
	}

	// Cell + albedo seam factor (1 inside panel, 0 in seam center).
	vec2 cell = floor(wall_uv / vec2(panel_size_x, panel_size_y));
	vec2 cell_uv = fract(wall_uv / vec2(panel_size_x, panel_size_y));
	vec2 edge_dist01 = min(cell_uv, 1.0 - cell_uv);
	vec2 edge_dist_m = edge_dist01 * vec2(panel_size_x, panel_size_y);
	float min_edge = min(edge_dist_m.x, edge_dist_m.y);
	float seam_t = smoothstep(seam_width, seam_width + seam_bevel, min_edge);

	bool is_wall = !is_floor;

	// ── Normal perturbation ────────────────────────────────────────────
	// Sample the surface height field at three nearby points and finite-
	// difference for the gradient. Sample spacing matters: it has to be
	// smaller than the smallest feature (rivet_radius or seam_bevel) so
	// we resolve the ramp, but not so small that we hit floating-point
	// precision issues. 5mm is a good compromise.
	float eps = 0.005;
	float h_c = surface_height(wall_uv, is_wall);
	float h_dx = surface_height(wall_uv + vec2(eps, 0.0), is_wall);
	float h_dy = surface_height(wall_uv + vec2(0.0, eps), is_wall);
	float dhdx = (h_dx - h_c) / eps;
	float dhdy = (h_dy - h_c) / eps;

	// Add a sub-cm scratch component so panel faces aren't mirror-flat —
	// breaks specular highlights into a worn look.
	float s_c = vnoise(wall_uv * scratch_scale);
	float s_dx = vnoise((wall_uv + vec2(eps, 0.0)) * scratch_scale);
	float s_dy = vnoise((wall_uv + vec2(0.0, eps)) * scratch_scale);
	dhdx += (s_dx - s_c) / eps * scratch_strength * 0.01;
	dhdy += (s_dy - s_c) / eps * scratch_strength * 0.01;

	// Build the world-space perturbed normal directly. dhdx is along
	// wall_uv.x, dhdy is along wall_uv.y; the geometric normal is the
	// remaining axis. Sign flips handle which side of the surface the
	// face is on so the perturbation tilts in the right direction.
	vec3 perturbed;
	if (is_floor) {
		float sy = sign(v_world_normal.y);
		perturbed = normalize(vec3(-sy * dhdx, sy, -sy * dhdy));
	} else if (abs(v_world_normal.x) > abs(v_world_normal.z)) {
		float sx = sign(v_world_normal.x);
		perturbed = normalize(vec3(sx, -dhdy, -sx * dhdx));
	} else {
		float sz = sign(v_world_normal.z);
		perturbed = normalize(vec3(-sz * dhdx, -dhdy, sz));
	}
	// Godot's NORMAL in fragment is view-space. Convert.
	NORMAL = normalize((VIEW_MATRIX * vec4(perturbed, 0.0)).xyz);

	// ── Albedo ─────────────────────────────────────────────────────────
	// Per-panel jitter for slab-to-slab variation.
	float jitter = (hash21(cell) - 0.5) * 2.0 * panel_variation;
	vec3 panel_albedo = base_color * (1.0 + jitter);

	// Surface wear: 2-octave noise darkens random patches. Stylized as
	// dirt/oxidation on the steel face. `wear_offset` lets a theme dial
	// the overall grime amount up or down so adjacent zones can read as
	// "newer" vs "more decayed" without changing the wear pattern itself.
	float wear = clamp(fbm2(wall_uv * wear_noise_scale) + wear_offset, 0.0, 1.0);
	panel_albedo = mix(panel_albedo, panel_albedo * 0.55, wear * wear_albedo_strength);

	// Compose albedo: seam → panel face, then layer border lip and rivets
	// on top using masks derived from the same height contributions. The
	// border and rivets read as distinct colors (typically slightly
	// brighter than the panel face) so they catch direct light into
	// readable highlights.
	vec3 base = mix(seam_color, panel_albedo, seam_t);

	// Reuse `cell_uv` / `min_edge` from above — we already computed them
	// for the seam_t logic. Earlier draft redeclared them here and silently
	// broke the shader compile (GLSL doesn't allow redeclaring a name in
	// the same scope; the fragment compiles to a default fallback when
	// this happens, which renders as flat white).
	vec2 panel = vec2(panel_size_x, panel_size_y);
	float lip_outer = seam_width + seam_bevel;
	float lip_inner = lip_outer + border_width;
	float lip_mask = step(lip_outer, min_edge) * step(min_edge, lip_inner);
	float lip_t_alb = 1.0 - abs((min_edge - (lip_outer + lip_inner) * 0.5)
		/ max(border_width * 0.5, 0.001));
	lip_t_alb = clamp(lip_t_alb, 0.0, 1.0) * lip_mask;
	vec3 with_border = mix(base, border_color, lip_t_alb * 0.85);

	// Rivet albedo mask: same dome footprint as the height field.
	float rivet_alb = 0.0;
	if (rivet_radius > 0.0) {
		vec2 cell_m = cell_uv * panel;
		vec2 rivet_pos;
		rivet_pos.x = cell_m.x < panel.x * 0.5 ? rivet_inset : panel.x - rivet_inset;
		rivet_pos.y = cell_m.y < panel.y * 0.5 ? rivet_inset : panel.y - rivet_inset;
		float d = length(cell_m - rivet_pos);
		rivet_alb = 1.0 - smoothstep(rivet_radius * 0.7, rivet_radius, d);
	}
	vec3 composed = mix(with_border, rivet_color, rivet_alb * 0.9);

	// Splotches: meter-scale grime patches with thresholded edges. The
	// 47.3 offset gives this noise field a different shape than the wear
	// noise, so splotches don't sit on top of wear darkening (which would
	// just look like more wear).
	float splotch_raw = fbm2(wall_uv * splotch_scale + vec2(47.3, 13.9));
	float splotch = smoothstep(splotch_threshold, splotch_threshold + 0.12, splotch_raw)
		* splotch_strength;
	composed = mix(composed, splotch_color, splotch);

	// Trim — recolor the baseboard and chair rail bands AFTER splotches so
	// trim reads as architectural (clean, defined) on top of the grime
	// rather than being eaten by it. Walls only — masks return 0 on
	// floors anyway via the surface_height gate, but we early-out here to
	// avoid pointlessly mixing.
	float trim_baseboard = is_wall ? baseboard_mask(wall_uv.y) : 0.0;
	float trim_chair = is_wall ? chair_rail_mask(wall_uv.y) : 0.0;
	composed = mix(composed, baseboard_color, trim_baseboard);
	composed = mix(composed, chair_rail_color, trim_chair);

	// Pixel-scale micro-noise on the final albedo. Centered on 0 (no net
	// brightness shift), high frequency. Breaks up uniform regions just
	// enough for the engine's debanding dither to blend in.
	float micro = vnoise(wall_uv * micro_albedo_scale) - 0.5;
	// Theme tint applied last — multiplicative, identity = vec3(1).
	ALBEDO = composed * tint_color * (1.0 + micro * 2.0 * micro_albedo_strength);

	// ── PBR ────────────────────────────────────────────────────────────
	// Metallic only on the panel face — dirt in the seams kills the
	// specular response there. Splotches reduce metallic further (grime
	// is non-metallic). Baseboard is dirty paint → no metal response.
	// Theme tint adds a small offset (default 0).
	METALLIC = clamp(metallic_value * seam_t * (1.0 - splotch * 0.8)
			* (1.0 - trim_baseboard * 0.9) + metallic_offset, 0.0, 1.0);
	// Roughness shifts up with wear, splotches, and baseboard grime.
	// Theme can dial overall roughness up/down via roughness_offset.
	ROUGHNESS = clamp(roughness_value + roughness_offset
			+ wear * roughness_wear
			+ splotch * 0.35
			+ trim_baseboard * baseboard_roughness_boost, 0.0, 1.0);
}
