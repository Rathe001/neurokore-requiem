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
const OVERLAY_COLOR := Color(0.03, 0.04, 0.05, 0.96)
const TITLE_COLOR := Color(0.4, 0.85, 0.95, 1.0)
const SUBTITLE_COLOR := Color(0.6, 0.66, 0.7, 0.85)
const FADE_OUT_DURATION := 0.35
const TITLE_FONT_SIZE := 32
const SUBTITLE_FONT_SIZE := 14
const DOT_ANIM_INTERVAL := 0.35

var _overlay: ColorRect
var _title: Label
var _subtitle: Label
var _subtitle_base: String = ""
var _dot_phase: int = 0
var _dot_accum: float = 0.0
var _hiding: bool = false


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
	_subtitle_base = subtitle
	_subtitle.text = subtitle
	_dot_phase = 0
	_dot_accum = 0.0
	_hiding = false
	_overlay.color = OVERLAY_COLOR
	_title.modulate.a = 1.0
	_subtitle.modulate.a = 1.0
	visible = true
	set_process(true)


func hide_loading() -> void:
	if _hiding:
		return
	_hiding = true
	set_process(false)
	var tween := create_tween()
	tween.tween_property(_overlay, "color:a", 0.0, FADE_OUT_DURATION)
	tween.parallel().tween_property(_title, "modulate:a", 0.0, FADE_OUT_DURATION)
	tween.parallel().tween_property(_subtitle, "modulate:a", 0.0, FADE_OUT_DURATION)
	tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	_dot_accum += delta
	if _dot_accum < DOT_ANIM_INTERVAL:
		return
	_dot_accum = 0.0
	_dot_phase = (_dot_phase + 1) % 4
	# Pad to fixed width so the label doesn't visibly resize each tick.
	_subtitle.text = "%s %s%s" % [_subtitle_base, ".".repeat(_dot_phase), " ".repeat(3 - _dot_phase)]


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
