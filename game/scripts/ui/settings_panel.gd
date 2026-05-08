extends Panel
class_name SettingsPanel

signal back_pressed

const PANEL_SIZE := Vector2(360.0, 500.0)
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

	var body := VBoxContainer.new()
	body.add_theme_constant_override(&"separation", 8)
	body.position = Vector2(18.0, 48.0)
	body.size = Vector2(PANEL_SIZE.x - 36.0, PANEL_SIZE.y - 110.0)
	add_child(body)

	body.add_child(_make_section_label("MENU_SETTINGS_DISPLAY"))
	_window_mode_option = _make_window_mode_option()
	body.add_child(_make_option_row("MENU_SETTINGS_WINDOW_MODE", _window_mode_option))
	_resolution_option = _make_resolution_option()
	body.add_child(_make_option_row("MENU_SETTINGS_RESOLUTION", _resolution_option))
	_msaa_option = _make_msaa_option()
	body.add_child(_make_option_row("MENU_SETTINGS_MSAA", _msaa_option))
	_fxaa_option = _make_fxaa_option()
	body.add_child(_make_option_row("MENU_SETTINGS_FXAA", _fxaa_option))
	_taa_option = _make_taa_option()
	body.add_child(_make_option_row("MENU_SETTINGS_TAA", _taa_option))
	_bloom_option = _make_bloom_option()
	body.add_child(_make_option_row("MENU_SETTINGS_BLOOM", _bloom_option))

	body.add_child(_make_section_label("MENU_SETTINGS_CONTROLS"))
	_sensitivity_slider = _make_sensitivity_slider()
	body.add_child(_make_slider_row("MENU_SETTINGS_MOUSE_SENSITIVITY", _sensitivity_slider))

	body.add_child(_make_section_label("MENU_SETTINGS_ACCESSIBILITY"))

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
