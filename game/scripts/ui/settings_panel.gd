extends Panel
class_name SettingsPanel

signal back_pressed

const PANEL_SIZE := Vector2(420.0, 480.0)
const BUTTON_SIZE := Vector2(168.0, 32.0)
const ROW_LABEL_WIDTH := 130.0
const OPTION_WIDTH := 170.0

var _window_mode_option: OptionButton
var _resolution_option: OptionButton
var _msaa_option: OptionButton
var _fxaa_option: OptionButton
var _taa_option: OptionButton
var _bloom_option: OptionButton
var _sensitivity_slider: HSlider
var _music_slider: HSlider
var _sfx_slider: HSlider
var _ambient_slider: HSlider

func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_bottom = PANEL_SIZE.y * 0.5

	var title := Label.new()
	title.text = "MENU_SETTINGS_TITLE"
	title.theme_type_variation = &"HeadingLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 14.0)
	title.size = Vector2(PANEL_SIZE.x, 22.0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)

	# TabContainer hosts four pages: Game, Display, Audio, Accessibility.
	# Tab titles are localised in _localise_tabs() after add_child (Godot's
	# TabContainer reads child node names by default; we override with tr()
	# so the strings.csv keys drive the UI text).
	var tabs := TabContainer.new()
	tabs.position = Vector2(18.0, 44.0)
	tabs.size = Vector2(PANEL_SIZE.x - 36.0, PANEL_SIZE.y - 110.0)
	tabs.clip_tabs = false
	add_child(tabs)

	tabs.add_child(_build_game_tab())
	tabs.add_child(_build_display_tab())
	tabs.add_child(_build_audio_tab())
	tabs.add_child(_build_accessibility_tab())
	_localise_tabs(tabs)

	var back := Button.new()
	back.text = "COMMON_BACK"
	back.custom_minimum_size = BUTTON_SIZE
	back.size = BUTTON_SIZE
	back.position = Vector2(
		(PANEL_SIZE.x - BUTTON_SIZE.x) * 0.5,
		PANEL_SIZE.y - BUTTON_SIZE.y - 18.0,
	)
	back.pressed.connect(func() -> void: back_pressed.emit())
	add_child(back)

	_refresh_display_options()
	DisplayState.changed.connect(_refresh_display_options)


func _exit_tree() -> void:
	DisplayState.changed.disconnect(_refresh_display_options)


# ── Tab builders ───────────────────────────────────────────────────────────
# Each builder returns a VBoxContainer that becomes a tab page. The tab
# title is set via TabContainer.set_tab_title in _localise_tabs; the node
# `name` is kept as the English fallback so dev-time debugging is clear.

func _build_game_tab() -> VBoxContainer:
	var page := _make_tab_page("Game")
	_sensitivity_slider = _make_sensitivity_slider()
	page.add_child(_make_slider_row("MENU_SETTINGS_MOUSE_SENSITIVITY", _sensitivity_slider))
	return page


func _build_display_tab() -> VBoxContainer:
	var page := _make_tab_page("Display")
	_window_mode_option = _make_window_mode_option()
	page.add_child(_make_option_row("MENU_SETTINGS_WINDOW_MODE", _window_mode_option))
	_resolution_option = _make_resolution_option()
	page.add_child(_make_option_row("MENU_SETTINGS_RESOLUTION", _resolution_option))
	_msaa_option = _make_msaa_option()
	page.add_child(_make_option_row("MENU_SETTINGS_MSAA", _msaa_option))
	_fxaa_option = _make_fxaa_option()
	page.add_child(_make_option_row("MENU_SETTINGS_FXAA", _fxaa_option))
	_taa_option = _make_taa_option()
	page.add_child(_make_option_row("MENU_SETTINGS_TAA", _taa_option))
	_bloom_option = _make_bloom_option()
	page.add_child(_make_option_row("MENU_SETTINGS_BLOOM", _bloom_option))
	return page


func _build_audio_tab() -> VBoxContainer:
	var page := _make_tab_page("Audio")
	_music_slider = _make_volume_slider(AudioState.config.music_volume if AudioState.config != null else 0.12)
	page.add_child(_make_percent_slider_row("MENU_SETTINGS_VOLUME_MUSIC", _music_slider))
	_music_slider.value_changed.connect(AudioState.set_music_volume)
	_sfx_slider = _make_volume_slider(AudioState.config.sfx_volume if AudioState.config != null else 0.85)
	page.add_child(_make_percent_slider_row("MENU_SETTINGS_VOLUME_SFX", _sfx_slider))
	_sfx_slider.value_changed.connect(AudioState.set_sfx_volume)
	_ambient_slider = _make_volume_slider(AudioState.config.ambient_volume if AudioState.config != null else 0.7)
	page.add_child(_make_percent_slider_row("MENU_SETTINGS_VOLUME_AMBIENT", _ambient_slider))
	_ambient_slider.value_changed.connect(AudioState.set_ambient_volume)
	return page


func _build_accessibility_tab() -> VBoxContainer:
	var page := _make_tab_page("Accessibility")
	# Placeholder hint while the accessibility section has no controls.
	# Replace this with real toggles (reduce camera effects, etc.) as
	# they land.
	var hint := Label.new()
	hint.text = "MENU_SETTINGS_ACCESSIBILITY_HINT"
	hint.theme_type_variation = &"SubLabel"
	hint.modulate = Color(1.0, 1.0, 1.0, 0.6)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(hint)
	return page


func _make_tab_page(node_name: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = node_name
	page.add_theme_constant_override(&"separation", 8)
	# Inner padding so the first row doesn't sit flush against the tab strip.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 6.0)
	page.add_child(spacer)
	return page


func _localise_tabs(tabs: TabContainer) -> void:
	# Map order matches the order tabs are added in _ready. Using indices
	# avoids relying on child node names matching the translation keys.
	tabs.set_tab_title(0, tr("MENU_SETTINGS_TAB_GAME"))
	tabs.set_tab_title(1, tr("MENU_SETTINGS_TAB_DISPLAY"))
	tabs.set_tab_title(2, tr("MENU_SETTINGS_TAB_AUDIO"))
	tabs.set_tab_title(3, tr("MENU_SETTINGS_TAB_ACCESSIBILITY"))


func _make_option_row(label_key: String, option: OptionButton) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.text = label_key
	label.theme_type_variation = &"SubLabel"
	label.custom_minimum_size = Vector2(ROW_LABEL_WIDTH, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	option.custom_minimum_size = Vector2(OPTION_WIDTH, 26.0)
	row.add_child(option)
	return row

func _make_window_mode_option() -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_sublabel)
	option.add_item(tr("WINDOW_MODE_WINDOWED"), DisplayConfig.Mode.WINDOWED)
	option.add_item(tr("WINDOW_MODE_BORDERLESS"), DisplayConfig.Mode.BORDERLESS_FULLSCREEN)
	option.add_item(tr("WINDOW_MODE_EXCLUSIVE"), DisplayConfig.Mode.EXCLUSIVE_FULLSCREEN)
	option.item_selected.connect(_on_window_mode_selected)
	return option

func _make_resolution_option() -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_sublabel)
	for res in DisplayState.available_resolutions():
		option.add_item("%d × %d" % [res.x, res.y])
	option.item_selected.connect(_on_resolution_selected)
	return option

func _make_msaa_option() -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_sublabel)
	option.add_item(tr("COMMON_OFF"), Viewport.MSAA_DISABLED)
	option.add_item(tr("MSAA_2X"), Viewport.MSAA_2X)
	option.add_item(tr("MSAA_4X"), Viewport.MSAA_4X)
	option.add_item(tr("MSAA_8X"), Viewport.MSAA_8X)
	option.item_selected.connect(_on_msaa_selected)
	return option

func _make_fxaa_option() -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_sublabel)
	option.add_item(tr("COMMON_OFF"), Viewport.SCREEN_SPACE_AA_DISABLED)
	option.add_item(tr("COMMON_ON"), Viewport.SCREEN_SPACE_AA_FXAA)
	option.item_selected.connect(_on_fxaa_selected)
	return option

func _make_taa_option() -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_sublabel)
	option.add_item(tr("COMMON_OFF"), 0)
	option.add_item(tr("COMMON_ON"), 1)
	option.item_selected.connect(_on_taa_selected)
	return option

func _make_bloom_option() -> OptionButton:
	var option := OptionButton.new()
	option.add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_sublabel)
	option.add_item(tr("COMMON_OFF"), 0)
	option.add_item(tr("COMMON_ON"), 1)
	option.item_selected.connect(_on_bloom_selected)
	return option

func _make_volume_slider(initial: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.custom_minimum_size = Vector2(OPTION_WIDTH - 40.0, 26.0)
	return slider


# Slider row with a percent-formatted value label. Audio sliders are
# linear [0,1]; showing "0.700" reads as gibberish, "70%" is the convention
# every player expects.
func _make_percent_slider_row(label_key: String, slider: HSlider) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.text = label_key
	label.theme_type_variation = &"SubLabel"
	label.custom_minimum_size = Vector2(ROW_LABEL_WIDTH, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	row.add_child(slider)
	var value_label := Label.new()
	value_label.theme_type_variation = &"BodyLabel"
	value_label.custom_minimum_size = Vector2(36.0, 0.0)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.text = "%d%%" % int(round(slider.value * 100.0))
	slider.value_changed.connect(func(v: float) -> void: value_label.text = "%d%%" % int(round(v * 100.0)))
	row.add_child(value_label)
	return row


func _make_sensitivity_slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.001
	slider.max_value = 0.020
	slider.step = 0.001
	slider.value = DisplayState.config.fps_mouse_sensitivity if DisplayState.config != null else 0.006
	slider.custom_minimum_size = Vector2(OPTION_WIDTH - 40.0, 26.0)
	slider.value_changed.connect(func(v: float) -> void:
		if DisplayState.config != null:
			DisplayState.config.fps_mouse_sensitivity = v
			DisplayState.save()
	)
	return slider

func _make_slider_row(label_key: String, slider: HSlider) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var label := Label.new()
	label.text = label_key
	label.theme_type_variation = &"SubLabel"
	label.custom_minimum_size = Vector2(ROW_LABEL_WIDTH, 0.0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	row.add_child(slider)
	var value_label := Label.new()
	value_label.theme_type_variation = &"BodyLabel"
	value_label.custom_minimum_size = Vector2(36.0, 0.0)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.text = "%.3f" % slider.value
	slider.value_changed.connect(func(v: float) -> void: value_label.text = "%.3f" % v)
	row.add_child(value_label)
	return row

func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"SectionLabel"
	return label

func _refresh_display_options() -> void:
	if DisplayState.config == null:
		return
	_window_mode_option.select(_window_mode_option.get_item_index(DisplayState.config.mode))
	var resolutions := DisplayState.available_resolutions()
	var current := DisplayState.config.resolution
	for i in resolutions.size():
		if resolutions[i] == current:
			_resolution_option.select(i)
			break
	_resolution_option.disabled = DisplayState.config.mode != DisplayConfig.Mode.WINDOWED
	_msaa_option.select(_msaa_option.get_item_index(DisplayState.config.msaa_3d))
	_fxaa_option.select(_fxaa_option.get_item_index(DisplayState.config.screen_space_aa))
	_taa_option.select(_taa_option.get_item_index(1 if DisplayState.config.use_taa else 0))
	_bloom_option.select(_bloom_option.get_item_index(1 if DisplayState.config.bloom_enabled else 0))
	_sensitivity_slider.set_value_no_signal(DisplayState.config.fps_mouse_sensitivity)

func _on_window_mode_selected(index: int) -> void:
	DisplayState.set_mode(_window_mode_option.get_item_id(index))

func _on_resolution_selected(index: int) -> void:
	var resolutions := DisplayState.available_resolutions()
	if index < 0 or index >= resolutions.size():
		return
	DisplayState.set_resolution(resolutions[index])

func _on_msaa_selected(index: int) -> void:
	DisplayState.set_msaa_3d(_msaa_option.get_item_id(index) as Viewport.MSAA)

func _on_fxaa_selected(index: int) -> void:
	DisplayState.set_screen_space_aa(_fxaa_option.get_item_id(index) as Viewport.ScreenSpaceAA)

func _on_taa_selected(index: int) -> void:
	DisplayState.set_use_taa(_taa_option.get_item_id(index) == 1)

func _on_bloom_selected(index: int) -> void:
	DisplayState.set_bloom_enabled(_bloom_option.get_item_id(index) == 1)
