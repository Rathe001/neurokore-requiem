class_name LoadingScreen
extends CanvasLayer

## Full-screen overlay shown during level rebuilds. Procgen rebake +
## navmesh bake is a synchronous main-thread hitch (hundreds of ms on
## larger layouts) — without the cover the player watches the previous
## level disintegrate, then a frozen frame, then the new level pops in.
## This panel masks both transitions with a dark cover and a "DESCENDING"
## label, giving the rebuild deliberate-pacing feel.
##
## Usage from PrototypeRoot:
##   var s := LoadingScreen.new()
##   add_child(s)
##   s.show_loading()
##   await get_tree().process_frame  # one frame so the cover actually renders
##   ...heavy work...
##   await get_tree().process_frame  # one frame so the new world renders behind us
##   s.hide_loading()  # fades out and queue_frees

## Sits above the death screen (DEATH_LAYER = 110) and the HUD; nothing
## else should outrank this while it's up.
const LOADING_LAYER := 120
# Full opacity — the world subtree behind us is mid-build (level pieces
# popping in over multiple frames, navmesh baking, etc.) so any sliver
# of see-through reads as "scene flashing in pieces." 1.0 makes the
# transition a clean cut. Fade-out tween still drops to 0.0 at the end
# so the new world reveals smoothly.
const OVERLAY_COLOR := Color(0.03, 0.04, 0.05, 1.0)
const TITLE_COLOR := Color(0.4, 0.85, 0.95, 1.0)
const SUBTITLE_COLOR := Color(0.6, 0.66, 0.7, 0.85)
const FADE_OUT_DURATION := 0.35
const TITLE_FONT_SIZE := 32
const SUBTITLE_FONT_SIZE := 14
# Progress-bar geometry. Wider than the labels so it dominates the
# vertical stack visually; thin enough to read as a "filling line"
# rather than a chunky gauge.
const PROGRESS_BAR_WIDTH := 360.0
const PROGRESS_BAR_HEIGHT := 8.0
# Eases bar fill so a sudden jump from build_progress=0.3 to 0.6 (which
# can happen when a large room-bundle yields back at once) doesn't snap.
const PROGRESS_FILL_LERP := 8.0

var _overlay: ColorRect
var _title: Label
var _subtitle: Label
var _progress_bar: ProgressBar
var _target_progress: float = 0.0
var _hiding: bool = false
# Pause state before show_loading() — restored on hide_loading so we
# don't clobber an intentional pause (pause menu, spec select, death
# screen). 99% of the time this is just false→true→false, but the
# save/restore is cheap insurance.
var _prev_paused: bool = false


func _ready() -> void:
	# Group membership lets PrototypeRoot dismiss any LoadingScreen on the
	# tree from a single call_group, regardless of who created it (the
	# rebuild path here, or the cross-scene cover_scene_transition helper
	# that survives change_scene_to_file).
	add_to_group(&"loading_screen")
	layer = LOADING_LAYER
	# Run regardless of pause. PrototypeRoot calls hide_loading() right
	# before showing SpecSelectOverlay (post-descent), and SpecSelectOverlay
	# sets `get_tree().paused = true` on _ready. With the default
	# process_mode the fade-out tween freezes mid-animation and the cover
	# stays visible on top of the spec select panel — looks like the loader
	# is stuck. PROCESS_MODE_ALWAYS keeps the tween advancing through the
	# pause so the cover finishes fading and queue_frees normally.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	# Instant cover — the player just triggered a transition and is staring
	# at a frozen world, so any fade-in would be wasted frames before the
	# rebuild hitch swallows the next several hundred ms anyway.
	visible = false
	set_process(false)


## Single-call helper for change_scene_to_file transitions. Adds a
## LoadingScreen to tree.root (NOT current_scene, so it survives the swap),
## yields for two frames so the cover actually paints before the new
## scene's _ready chain locks the main thread, then triggers the scene
## change. Caller should `await` so it doesn't run any code that depends
## on the old scene after returning.
##
## PrototypeRoot._ready dismisses any LoadingScreen in the &"loading_screen"
## group once its setup completes, so callers don't have to clean up.
static func transition_to_scene(scene_path: String, title: String = "DESCENDING", subtitle: String = "Loading") -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var screen := LoadingScreen.new()
	tree.root.add_child(screen)
	screen.show_loading(title, subtitle)
	# Two render frames before kicking off the scene change. One frame is
	# necessary so the layer paints; the second buys a margin in case the
	# user has v-sync stalls or the previous scene's _process happened to
	# add deferred work that defers rendering by another tick. Without
	# this, the cover only paints AFTER the new scene's _ready hitch
	# finishes — which is exactly when we want it to be GONE, not
	# starting to fade out.
	await tree.process_frame
	await tree.process_frame
	tree.change_scene_to_file(scene_path)


func show_loading(title: String = "DESCENDING", subtitle: String = "Generating sub-level") -> void:
	_title.text = title
	_subtitle.text = subtitle
	_target_progress = 0.0
	_progress_bar.value = 0.0
	_progress_bar.modulate.a = 1.0
	_hiding = false
	_overlay.color = OVERLAY_COLOR
	_title.modulate.a = 1.0
	_subtitle.modulate.a = 1.0
	visible = true
	# _process drives the bar's eased fill toward _target_progress. Cheap;
	# runs only while the screen is visible.
	set_process(true)
	# Pause the world while the cover is up. Default PROCESS_MODE_INHERIT
	# on the player + level subtrees stops their _process / _physics_process
	# / _unhandled_input calls under pause, so WASD can't drive the player
	# around the half-built level (was visible through the previous 0.96
	# alpha cover before we bumped it to 1.0, and even with full opacity
	# the player was still moving + the level was still ticking behind
	# the curtain). LoadingScreen itself runs at PROCESS_MODE_ALWAYS so
	# its dots animation + hide_loading fade tween keep advancing.
	#
	# LevelBuilder's streamed `_build_level` yields via
	# `await get_tree().process_frame` — process_frame fires regardless
	# of pause, so the async build keeps making progress while the world
	# subtree itself is frozen.
	var tree := get_tree()
	if tree != null:
		_prev_paused = tree.paused
		tree.paused = true


func hide_loading() -> void:
	if _hiding:
		return
	_hiding = true
	set_process(false)
	# Restore the pre-show pause state BEFORE the fade-out so the world
	# is already updating behind the fading cover — gives the cleanest
	# "world reveals back in motion" feel rather than a frozen frame
	# during the fade. Restoring (not blanket-clearing) preserves an
	# intentional outer pause (pause menu, etc.) on the rare path where
	# loading was kicked off from an already-paused state.
	var tree := get_tree()
	if tree != null:
		tree.paused = _prev_paused
	var tween := create_tween()
	tween.tween_property(_overlay, "color:a", 0.0, FADE_OUT_DURATION)
	tween.parallel().tween_property(_title, "modulate:a", 0.0, FADE_OUT_DURATION)
	tween.parallel().tween_property(_subtitle, "modulate:a", 0.0, FADE_OUT_DURATION)
	tween.parallel().tween_property(_progress_bar, "modulate:a", 0.0, FADE_OUT_DURATION)
	tween.tween_callback(queue_free)


## Bump the displayed progress bar toward `value` (clamped [0, 1]). Driven
## by LevelBuilder via a group-call on &"loading_screen" — see the per-
## yield calls in _build_level. The actual bar fill eases toward this
## target in _process so a jump from 0.3 → 0.6 doesn't snap.
func set_progress(value: float) -> void:
	_target_progress = clampf(value, 0.0, 1.0)


func _process(delta: float) -> void:
	# Frame-rate-independent damping toward _target_progress. Catches up
	# ~63% of the gap every ~1/PROGRESS_FILL_LERP seconds — feels lively
	# without overshooting, and stays smooth even when LevelBuilder yields
	# back with a big multi-step jump (e.g. corridors batch-finishing).
	var weight: float = 1.0 - exp(-PROGRESS_FILL_LERP * delta)
	var current: float = _progress_bar.value
	# Clamp to no-decrease — if a stale low value somehow arrived late we
	# don't want the bar visibly retreating.
	_progress_bar.value = maxf(current, lerp(current, _target_progress, weight))


func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = OVERLAY_COLOR
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Swallow input so a held-down interact keypress can't bleed through to
	# the freshly-spawned interactables on the new level.
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	vbox.offset_left = -260.0
	vbox.offset_right = 260.0
	vbox.offset_top = -50.0
	vbox.offset_bottom = 50.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override(&"separation", 12)
	_overlay.add_child(vbox)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override(&"font_size", TITLE_FONT_SIZE)
	_title.add_theme_color_override(&"font_color", TITLE_COLOR)
	vbox.add_child(_title)

	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_font_size_override(&"font_size", SUBTITLE_FONT_SIZE)
	_subtitle.add_theme_color_override(&"font_color", SUBTITLE_COLOR)
	vbox.add_child(_subtitle)

	# Thin progress bar centered under the subtitle. Authored without
	# percentage text (would re-layout the label every value change and
	# fight the bar's clean fill animation). MarginContainer pads it off
	# the subtitle visually so the bar doesn't crowd the label baseline.
	var bar_wrap := MarginContainer.new()
	bar_wrap.add_theme_constant_override(&"margin_top", 6)
	vbox.add_child(bar_wrap)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	_progress_bar.step = 0.001
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(PROGRESS_BAR_WIDTH, PROGRESS_BAR_HEIGHT)
	_progress_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# Tint the fill to match the title's cyan accent so the bar reads as
	# part of the same UI element rather than a generic engine widget.
	# StyleBoxFlat keeps it crisp at iso scale; tweak `bg_*` if the look
	# needs to match a later theme pass.
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.08, 0.10, 0.12, 1.0)
	bar_bg.border_color = Color(0.18, 0.22, 0.26, 1.0)
	bar_bg.border_width_left = 1
	bar_bg.border_width_right = 1
	bar_bg.border_width_top = 1
	bar_bg.border_width_bottom = 1
	bar_bg.corner_radius_top_left = 2
	bar_bg.corner_radius_top_right = 2
	bar_bg.corner_radius_bottom_left = 2
	bar_bg.corner_radius_bottom_right = 2
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = TITLE_COLOR
	bar_fill.corner_radius_top_left = 2
	bar_fill.corner_radius_top_right = 2
	bar_fill.corner_radius_bottom_left = 2
	bar_fill.corner_radius_bottom_right = 2
	_progress_bar.add_theme_stylebox_override(&"background", bar_bg)
	_progress_bar.add_theme_stylebox_override(&"fill", bar_fill)
	bar_wrap.add_child(_progress_bar)
