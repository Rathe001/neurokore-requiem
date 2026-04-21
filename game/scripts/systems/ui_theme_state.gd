extends Node

# Active UI skin. Picks a UIThemeConfig based on PlayerState.class_id
# and assembles a Godot Theme from it so any Control subtree that sets
# `theme = UIThemeState.theme` inherits widget styling automatically.
# Semantic colors (HP, resource fill, slot border, etc.) stay on the
# palette — read them directly as UIThemeState.palette.<field>.

signal changed

const THEME_DEFAULT: UIThemeConfig = preload("res://resources/ui/theme_default.tres")
const THEME_HUMAN: UIThemeConfig = preload("res://resources/ui/theme_human.tres")
const THEME_CYBORG: UIThemeConfig = preload("res://resources/ui/theme_cyborg.tres")
const THEME_HUMAN_SURVIVALIST: UIThemeConfig = preload("res://resources/ui/theme_human_survivalist.tres")
const THEME_HUMAN_GENTLEMAN: UIThemeConfig = preload("res://resources/ui/theme_human_gentleman.tres")
const THEME_HUMAN_ENCULTED: UIThemeConfig = preload("res://resources/ui/theme_human_enculted.tres")
const THEME_CYBORG_FORGED: UIThemeConfig = preload("res://resources/ui/theme_cyborg_forged.tres")
const THEME_CYBORG_AUTOMATON: UIThemeConfig = preload("res://resources/ui/theme_cyborg_automaton.tres")
const THEME_CYBORG_POLYMATH: UIThemeConfig = preload("res://resources/ui/theme_cyborg_polymath.tres")

const SPEC_THEMES: Dictionary = {
	&"human/survivalist": THEME_HUMAN_SURVIVALIST,
	&"human/gentleman": THEME_HUMAN_GENTLEMAN,
	&"human/enculted": THEME_HUMAN_ENCULTED,
	&"cyborg/forged": THEME_CYBORG_FORGED,
	&"cyborg/automaton": THEME_CYBORG_AUTOMATON,
	&"cyborg/polymath": THEME_CYBORG_POLYMATH,
}

var palette: UIThemeConfig
var theme: Theme

func _ready() -> void:
	_refresh()
	PlayerState.class_changed.connect(_on_player_changed)
	PlayerState.spec_changed.connect(_on_player_changed)

func _on_player_changed(_id: StringName) -> void:
	_refresh()

func _refresh() -> void:
	var p := _palette_for(PlayerState.class_id, PlayerState.spec_id)
	palette = p
	theme = _build_theme(p)
	changed.emit()

func get_palette_for(class_id: StringName, spec_id: StringName) -> UIThemeConfig:
	return _palette_for(class_id, spec_id)

func _palette_for(class_id: StringName, spec_id: StringName) -> UIThemeConfig:
	if spec_id != &"":
		var key := StringName("%s/%s" % [class_id, spec_id])
		if SPEC_THEMES.has(key):
			return SPEC_THEMES[key]
	match class_id:
		&"human":
			return THEME_HUMAN
		&"cyborg":
			return THEME_CYBORG
	return THEME_DEFAULT

func _build_theme(p: UIThemeConfig) -> Theme:
	var t := Theme.new()
	t.default_font_size = p.base_font_size
	t.set_color(&"font_color", &"Label", p.text)
	t.set_color(&"font_color", &"Button", p.text)
	t.set_color(&"font_color", &"CheckBox", p.text)
	t.set_color(&"font_hover_color", &"Button", p.accent)
	t.set_color(&"font_pressed_color", &"Button", p.accent)
	t.set_color(&"font_disabled_color", &"Button", p.text_dim)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = p.panel_bg
	panel_style.border_color = p.panel_border
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	t.set_stylebox(&"panel", &"PanelContainer", panel_style)
	t.set_stylebox(&"panel", &"Panel", panel_style)

	var button_style := StyleBoxFlat.new()
	button_style.bg_color = Color(p.panel_bg.r, p.panel_bg.g, p.panel_bg.b, 0.85)
	button_style.border_color = p.accent_dim
	button_style.border_width_left = 1
	button_style.border_width_top = 1
	button_style.border_width_right = 1
	button_style.border_width_bottom = 1
	button_style.content_margin_left = 8
	button_style.content_margin_right = 8
	button_style.content_margin_top = 4
	button_style.content_margin_bottom = 4
	t.set_stylebox(&"normal", &"Button", button_style)

	var button_hover := button_style.duplicate() as StyleBoxFlat
	button_hover.border_color = p.accent
	t.set_stylebox(&"hover", &"Button", button_hover)

	var button_pressed := button_style.duplicate() as StyleBoxFlat
	button_pressed.bg_color = Color(p.accent.r, p.accent.g, p.accent.b, 0.25)
	button_pressed.border_color = p.accent
	t.set_stylebox(&"pressed", &"Button", button_pressed)

	var button_disabled := button_style.duplicate() as StyleBoxFlat
	button_disabled.border_color = Color(p.accent_dim.r, p.accent_dim.g, p.accent_dim.b, 0.4)
	t.set_stylebox(&"disabled", &"Button", button_disabled)

	# Label type variations
	t.set_type_variation(&"TitleLabel", &"Label")
	t.set_font_size(&"font_size", &"TitleLabel", p.font_size_title)

	t.set_type_variation(&"HeadingLabel", &"Label")
	t.set_font_size(&"font_size", &"HeadingLabel", p.font_size_heading)

	t.set_type_variation(&"SectionLabel", &"Label")
	t.set_font_size(&"font_size", &"SectionLabel", p.font_size_section)
	t.set_color(&"font_color", &"SectionLabel", p.accent_dim)

	t.set_type_variation(&"CardTitle", &"Label")
	t.set_font_size(&"font_size", &"CardTitle", p.font_size_card_title)

	t.set_type_variation(&"SubLabel", &"Label")
	t.set_font_size(&"font_size", &"SubLabel", p.font_size_sublabel)

	t.set_type_variation(&"BodyLabel", &"Label")
	t.set_font_size(&"font_size", &"BodyLabel", p.font_size_body)

	t.set_type_variation(&"TooltipLabel", &"Label")
	t.set_font_size(&"font_size", &"TooltipLabel", p.font_size_tooltip)
	t.set_color(&"font_color", &"TooltipLabel", p.text_dim)

	t.set_type_variation(&"SmallLabel", &"Label")
	t.set_font_size(&"font_size", &"SmallLabel", p.font_size_small)
	t.set_color(&"font_color", &"SmallLabel", p.text_dim)

	t.set_type_variation(&"StatLabel", &"Label")
	t.set_font_size(&"font_size", &"StatLabel", p.font_size_stat)
	t.set_color(&"font_color", &"StatLabel", p.text_dim)

	t.set_type_variation(&"SlotGlyph", &"Label")
	t.set_font_size(&"font_size", &"SlotGlyph", p.font_size_slot_glyph)

	t.set_type_variation(&"DragPreview", &"Label")
	t.set_font_size(&"font_size", &"DragPreview", p.font_size_drag_preview)

	t.set_type_variation(&"PortraitGlyph", &"Label")
	t.set_font_size(&"font_size", &"PortraitGlyph", p.font_size_portrait)

	# PanelContainer tag variations — stat indicators on class cards
	t.set_type_variation(&"StatPosTag", &"PanelContainer")
	var pos_style := StyleBoxFlat.new()
	pos_style.bg_color = Color(0.0, 0.15, 0.05, 0.9)
	pos_style.border_color = Color(0.35, 0.9, 0.45, 1.0)
	pos_style.set_border_width_all(1)
	pos_style.content_margin_left = 3
	pos_style.content_margin_right = 3
	pos_style.content_margin_top = 0
	pos_style.content_margin_bottom = 0
	t.set_stylebox(&"panel", &"StatPosTag", pos_style)

	t.set_type_variation(&"StatNegTag", &"PanelContainer")
	var neg_style := pos_style.duplicate() as StyleBoxFlat
	neg_style.bg_color = Color(0.15, 0.0, 0.0, 0.9)
	neg_style.border_color = Color(0.9, 0.3, 0.3, 1.0)
	t.set_stylebox(&"panel", &"StatNegTag", neg_style)

	return t
