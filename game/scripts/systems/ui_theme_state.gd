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

	return t
