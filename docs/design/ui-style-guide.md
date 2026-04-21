# UI Style Guide

> Source of truth for colors, type sizes, and component conventions.
> All values live in `game/scripts/systems/ui_theme_config.gd` and `ui_theme_state.gd`.
> This document is generated from the current theme resources — update it when theme values change.

## Type Scale

Defined as semantic names in `UIThemeConfig`. Exposed as Godot theme type variations via `UIThemeState._build_theme()`. Assign with `label.theme_type_variation = &"VariationName"` — never hardcode font sizes.

| Variation | Size | Default Color | Usage |
|---|---|---|---|
| `TitleLabel` | 28 | text | Startup screen section titles |
| `HeadingLabel` | 18 | text | Modal panel titles (Menu, Settings) |
| `SectionLabel` | 14 | accent_dim | Settings section headers |
| `CardTitle` | 13 | text | Class card names; also theme default font size |
| `SubLabel` | 12 | text | Inventory panel title, option row labels |
| `BodyLabel` | 11 | text | Standard body text, character sheet stat rows |
| `TooltipLabel` | 10 | text_dim | Tooltip description and stats text |
| `SmallLabel` | 9 | text_dim | Card backstory, debug readonly rows, captions |
| `StatLabel` | 8 | text_dim | Stat tags on class cards, empty slot labels |
| `SlotGlyph` | 20 | — | Item glyph inside equipment/inventory slots |
| `DragPreview` | 24 | — | Item glyph shown during drag |
| `PortraitGlyph` | 32 | — | Glyph on class card portrait placeholder |

`CheckBox` and `OptionButton` do not support `theme_type_variation` on a Label — use `add_theme_font_size_override(&"font_size", UIThemeState.palette.font_size_*)` with the appropriate palette field.

## Tag Components

Styled `PanelContainer` variations for stat indicators. Assign with `container.theme_type_variation = &"StatPosTag"` (or `StatNegTag`). Put a `StatLabel` inside with a color override.

| Variation | Background | Border | Text Color | Usage |
|---|---|---|---|---|
| `StatPosTag` | `(0.0, 0.15, 0.05, 0.9)` | `(0.35, 0.9, 0.45, 1.0)` | `(0.35, 0.9, 0.45, 1.0)` | Primary stat (`+Soul`) |
| `StatNegTag` | `(0.15, 0.0, 0.0, 0.9)` | `(0.9, 0.3, 0.3, 1.0)` | `(0.9, 0.3, 0.3, 0.85)` | Opposing stat (`-Interface`) |

Tag colors are **fixed** — they do not shift per class theme. Green = benefit, red = penalty. This is intentional: colorblind-friendly alternatives may be added later.

## Color Groups

Each `UIThemeConfig` resource defines these semantic color fields. Read them via `UIThemeState.palette.<field>` — never hardcode their values.

| Field | Purpose |
|---|---|
| `accent` | Primary class color. Borders, hover states, highlights. |
| `accent_dim` | Muted accent. Section labels, unfocused borders. |
| `panel_bg` | Background fill for panels and modals. |
| `panel_border` | Border color for panels and modals. |
| `text` | Primary readable text. |
| `text_dim` | Secondary / label text, captions. |
| `hp_full` | HP bar fill at full health. |
| `hp_low` | HP bar fill when critically low. |
| `hp_bar_bg` | HP bar background. |
| `hp_bar_border` | HP bar border. |
| `slot_bg` | Equipment and inventory slot background. |
| `slot_border` | Equipment and inventory slot border. |
| `credits` | Credit amount text. |
| `player_color` | Player token / minimap dot color. |

## Class Palettes

### Default (no class selected)

| Field | RGB |
|---|---|
| accent | `(0.3, 0.7, 1.0)` |
| accent_dim | `(0.25, 0.45, 0.7)` |
| panel_bg | `(0.04, 0.05, 0.08, 0.92)` |
| panel_border | `(0.3, 0.5, 0.7, 0.9)` |
| text | `(0.82, 0.9, 1.0)` |
| text_dim | `(0.55, 0.65, 0.8)` |
| credits | `(1.0, 0.85, 0.25)` |
| player_color | `(0.75, 0.78, 0.85)` |

---

### Human

| Field | RGB |
|---|---|
| accent | `(0.65, 0.45, 0.25)` — Brown / SOU |
| accent_dim | `(0.42, 0.3, 0.16)` |
| panel_bg | `(0.08, 0.05, 0.04, 0.92)` |
| panel_border | `(0.75, 0.45, 0.25, 0.9)` |
| text | `(1.0, 0.92, 0.82)` |
| text_dim | `(0.8, 0.65, 0.5)` |
| credits | `(1.0, 0.85, 0.25)` |
| player_color | `(0.95, 0.68, 0.48)` |

### Human / Survivalist

| Field | RGB |
|---|---|
| accent | `(0.7, 0.85, 0.35)` — Olive green / ING |
| accent_dim | `(0.42, 0.5, 0.22)` |
| panel_bg | `(0.06, 0.07, 0.04, 0.93)` |
| panel_border | `(0.55, 0.65, 0.3, 0.9)` |
| text | `(0.95, 0.95, 0.82)` |
| text_dim | `(0.7, 0.72, 0.55)` |
| credits | `(0.95, 0.85, 0.3)` |
| player_color | `(0.78, 0.85, 0.5)` |

### Human / Gentleman-Lady

| Field | RGB |
|---|---|
| accent | `(0.95, 0.92, 0.8)` — Ivory / ORT |
| accent_dim | `(0.62, 0.6, 0.52)` |
| panel_bg | `(0.06, 0.04, 0.05, 0.94)` |
| panel_border | `(0.78, 0.62, 0.32, 0.9)` |
| text | `(0.98, 0.92, 0.82)` |
| text_dim | `(0.78, 0.68, 0.55)` |
| credits | `(0.95, 0.82, 0.4)` |
| player_color | `(0.85, 0.7, 0.45)` |

### Human / Enculted

| Field | RGB |
|---|---|
| accent | `(0.78, 0.35, 0.85)` — Purple / AMB |
| accent_dim | `(0.45, 0.2, 0.55)` |
| panel_bg | `(0.06, 0.03, 0.08, 0.94)` |
| panel_border | `(0.6, 0.25, 0.7, 0.9)` |
| text | `(0.95, 0.88, 1.0)` |
| text_dim | `(0.7, 0.55, 0.78)` |
| credits | `(1.0, 0.78, 0.35)` |
| player_color | `(0.78, 0.45, 0.88)` |

---

### Cyborg

| Field | RGB |
|---|---|
| accent | `(0.3, 0.85, 1.0)` — Cyan / ITF |
| accent_dim | `(0.2, 0.55, 0.75)` |
| panel_bg | `(0.02, 0.06, 0.1, 0.92)` |
| panel_border | `(0.3, 0.75, 1.0, 0.9)` |
| text | `(0.82, 0.95, 1.0)` |
| text_dim | `(0.5, 0.72, 0.88)` |
| credits | `(0.6, 0.95, 1.0)` |
| player_color | `(0.45, 0.78, 0.98)` |

### Cyborg / Forged

| Field | RGB |
|---|---|
| accent | `(0.9, 0.25, 0.2)` — Red / DEV |
| accent_dim | `(0.58, 0.16, 0.13)` |
| panel_bg | `(0.08, 0.05, 0.03, 0.94)` |
| panel_border | `(0.85, 0.5, 0.18, 0.9)` |
| text | `(1.0, 0.92, 0.78)` |
| text_dim | `(0.78, 0.62, 0.45)` |
| credits | `(1.0, 0.82, 0.3)` |
| player_color | `(0.95, 0.6, 0.3)` |

### Cyborg / Automaton

| Field | RGB |
|---|---|
| accent | `(0.55, 0.78, 0.85)` — Steel blue / OPT |
| accent_dim | `(0.32, 0.48, 0.55)` |
| panel_bg | `(0.05, 0.07, 0.08, 0.94)` |
| panel_border | `(0.5, 0.7, 0.78, 0.9)` |
| text | `(0.88, 0.93, 0.96)` |
| text_dim | `(0.6, 0.7, 0.75)` |
| credits | `(0.85, 0.92, 0.55)` |
| player_color | `(0.62, 0.78, 0.85)` |

### Cyborg / Polymath

| Field | RGB |
|---|---|
| accent | `(0.95, 0.9, 0.3)` — Yellow / CLA |
| accent_dim | `(0.62, 0.58, 0.2)` |
| panel_bg | `(0.04, 0.04, 0.09, 0.94)` |
| panel_border | `(0.55, 0.4, 0.95, 0.9)` |
| text | `(0.9, 0.88, 1.0)` |
| text_dim | `(0.62, 0.6, 0.78)` |
| credits | `(0.7, 0.95, 1.0)` |
| player_color | `(0.7, 0.55, 0.95)` |

## i18n Conventions

- All visible strings must go through `tr()` or be assigned as i18n keys (auto-translated Controls).
- `Label.text = "KEY"` auto-translates when `auto_translate_mode` is on (the default), but dynamically built UI may not inherit it reliably — use `tr("KEY")` explicitly.
- `OptionButton.add_item()` does **not** auto-translate. Always wrap: `add_item(tr("KEY"), id)`.
- Format strings: apply `tr()` to the template, not the result: `tr("FORMAT_KEY") % [value]`.
- Key naming: `NAMESPACE_DESCRIPTION` in SCREAMING_SNAKE_CASE. Namespaces: `COMMON_`, `CLASS_`, `SPEC_`, `STAT_`, `STARTUP_`, `MENU_`, `HUD_`, `EQUIP_`, `ITEM_`, `DEBUG_`.

## Conventions

- Never call `add_theme_font_size_override` with a magic number. Use `label.theme_type_variation` for Label subtypes. For widget types (CheckBox, OptionButton), read from `UIThemeState.palette.font_size_*`.
- Never hardcode palette colors. All colors come from `UIThemeState.palette.*`.
- Fixed colors (e.g. stat tag green/red, morality dot) are documented above and stay fixed regardless of theme.
- Panel backgrounds use 0.92–0.96 alpha to keep backgrounds readable over the 3D scene.
