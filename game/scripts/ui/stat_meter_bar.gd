class_name StatMeterBar
extends Control

# Reusable horizontal stat meter bar drawn via _draw(). Designed for weapon
# tooltips and the character sheet. The parent sets properties, then calls
# queue_redraw(). No signals — pure passive rendering.
#
# The bar represents the archetype+rarity range for this stat. 0% fill =
# archetype floor, 100% fill = archetype ceiling. Fixed red → yellow →
# green gradient (not theme-dependent). When an item's effective_multiplier
# is below 1.0 (underleveled), a pulsing red overlay shows the decay zone.
#
# Layout: [label left-aligned] [value right-aligned] [gap] [bar]
#
# Visual layers (back to front):
#   1. Label text (left-aligned)
#   2. Value text (right-aligned, between label and bar)
#   3. Background track (dark)
#   4. Fill (gradient colored by fill %)
#   5. Decay overlay (pulsing red, covers gap between decayed and raw fill)
#   6. Boost overlay (pulsing blue, extends beyond raw fill to boosted position)

# ── Layout constants ────────────────────────────────────────────────────────

const BAR_WIDTH := 90.0
const BAR_HEIGHT := 4.0
const LABEL_WIDTH := 42.0
const VALUE_WIDTH := 36.0
const GAP := 3.0
const ROW_HEIGHT := 8.0         # Total height per bar row (bar + vertical padding)
const FONT_SIZE_LABEL := 5
const FONT_SIZE_NUMBER := 5
const TOTAL_WIDTH := LABEL_WIDTH + VALUE_WIDTH + GAP + BAR_WIDTH

# ── Properties (set by parent before queue_redraw) ──────────────────────────

var value: float = 0.0              # Normalized [0,1] position in archetype range
var decayed_value: float = -1.0     # Normalized [0,1] effective value after decay; -1 = no decay
var boosted_value: float = -1.0     # Normalized [0,1] effective value when boosted; -1 = no boost
var number_text: String = ""        # Formatted raw value
var label_text: String = ""         # Left-side label
var _pulsing: bool = false          # True when decay/boost overlay needs animation

# ── Cached theme colors (track + text only; fill uses fixed gradient) ──────

var _track_color: Color = Color(0.1, 0.1, 0.15, 0.8)
var _label_color: Color = Color(0.82, 0.9, 1.0)
var _number_color: Color = Color(1.0, 1.0, 1.0, 0.95)
var _number_shadow: Color = Color(0.0, 0.0, 0.0, 0.8)


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(TOTAL_WIDTH, ROW_HEIGHT)
	set_process(false)
	update_theme()


func _process(_delta: float) -> void:
	# Only runs when pulsing decay overlay — drives redraw for animation.
	queue_redraw()


func update_theme() -> void:
	var p: UIThemeConfig = UIThemeState.palette
	if p == null:
		return
	_track_color = Color(p.slot_bg, 0.8)
	_label_color = p.text_dim
	_number_color = Color(p.text, 0.95)
	_number_shadow = Color(p.panel_bg, 0.8)
	queue_redraw()


# Fixed gradient: red(0%) → yellow(50%) → green(100%).
# Not theme-dependent — roll quality reads consistently regardless of palette.
static func _gradient_color(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	if t < 0.5:
		return Color(0.9, 0.2, 0.2).lerp(Color(0.95, 0.85, 0.2), t / 0.5)
	else:
		return Color(0.95, 0.85, 0.2).lerp(Color(0.2, 0.85, 0.3), (t - 0.5) / 0.5)


## Call after setting properties to enable/disable the pulse animation.
func update_pulse() -> void:
	var has_decay := decayed_value >= 0.0 and decayed_value < value - 0.005
	var has_boost := boosted_value > value + 0.005
	var needs_pulse := visible and (has_decay or has_boost)
	if needs_pulse != _pulsing:
		_pulsing = needs_pulse
		set_process(_pulsing)
		if _pulsing:
			queue_redraw()


func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	var bar_x := LABEL_WIDTH + VALUE_WIDTH + GAP
	var bar_y := (ROW_HEIGHT - BAR_HEIGHT) * 0.5
	var text_y := bar_y + BAR_HEIGHT * 0.5 + float(FONT_SIZE_LABEL) * 0.35

	# 1. Label text (left-aligned)
	draw_string(font, Vector2(0, text_y), label_text, HORIZONTAL_ALIGNMENT_LEFT,
		LABEL_WIDTH, FONT_SIZE_LABEL, _label_color)

	# 2. Value text (right-aligned, between label and bar)
	if not number_text.is_empty():
		draw_string(font, Vector2(LABEL_WIDTH, text_y), number_text, HORIZONTAL_ALIGNMENT_RIGHT,
			VALUE_WIDTH, FONT_SIZE_NUMBER, _number_color)

	# 3. Background track
	draw_rect(Rect2(bar_x, bar_y, BAR_WIDTH, BAR_HEIGHT), _track_color)

	# 4. Fill (gradient colored by value)
	var fill_w := clampf(value, 0.0, 1.0) * BAR_WIDTH
	# Minimum 2px fill for rolled stats (has number_text) so a floor-roll
	# is visually distinct from an unrolled empty bar.
	if not number_text.is_empty() and fill_w < 2.0:
		fill_w = 2.0
	if fill_w > 0.5:
		var fill_color := _gradient_color(value)
		draw_rect(Rect2(bar_x, bar_y, fill_w, BAR_HEIGHT), fill_color)

	# 5. Decay overlay — pulsing red between decayed and raw fill positions
	if _pulsing and decayed_value >= 0.0 and decayed_value < value - 0.005:
		var decay_w := clampf(decayed_value, 0.0, 1.0) * BAR_WIDTH
		if not number_text.is_empty() and decay_w < 2.0:
			decay_w = 2.0
		if decay_w < fill_w:
			var pulse := 0.45 + 0.35 * sin(float(Time.get_ticks_msec()) * 0.008)
			var overlay_color := Color(0.9, 0.15, 0.15, pulse)
			draw_rect(Rect2(bar_x + decay_w, bar_y, fill_w - decay_w, BAR_HEIGHT), overlay_color)

	# 6. Boost overlay — pulsing blue from raw fill to boosted fill position
	if _pulsing and boosted_value > value + 0.005:
		var boost_w := clampf(boosted_value, 0.0, 1.0) * BAR_WIDTH
		if boost_w > fill_w:
			var pulse := 0.45 + 0.35 * sin(float(Time.get_ticks_msec()) * 0.008)
			var overlay_color := Color(0.3, 0.5, 1.0, pulse)
			draw_rect(Rect2(bar_x + fill_w, bar_y, boost_w - fill_w, BAR_HEIGHT), overlay_color)
