class_name DoomsayerAura
extends Node3D

# Visual aura for the Enculted Doomsayer perk — a single large
# billboarded smoke sprite attached to the player, looping through the
# 46-frame smoke spritesheet (assets/effects/smoke.png, 7×7 grid). The
# grayscale smoke is tinted purple via Sprite3D.modulate.
#
# Pairs with a shadow-casting OmniLight3D for the wider purple wash on
# world surfaces (handles the wall-clipping that the visible sprite
# alone can't, since it's billboarded and large enough to extend past
# walls in plan view).

const SMOKE_TEXTURE: Texture2D = preload("res://assets/effects/smoke.png")
const COLOR := Color(0.78, 0.35, 0.85, 1.0)  # AMB stat color (purple)
# Spritesheet layout — 7 columns × 7 rows, last row only has 4 cells
# filled (3 empty). We loop frames 0..TOTAL_FRAMES-1 only, skipping
# the empty cells.
const SPRITE_H_FRAMES := 7
const SPRITE_V_FRAMES := 7
const TOTAL_FRAMES := 46
const ANIM_FPS := 18.0  # speed the puff loops at

# Per-tier visual scaling. T0 hides everything. pixel_size scales the
# sprite to a real-world meter size (smoke.png frame is 256² so
# pixel_size 0.018 → ~4.6m visible width). Modulate alpha controls
# the overall opacity per tier; the OmniLight scales independently to
# match the skill's per-tier aura radius.
const PIXEL_SIZE_PER_TIER: Array[float] = [0.0, 0.022, 0.030, 0.040]
const ALPHA_PER_TIER: Array[float] = [0.0, 0.65, 0.85, 1.0]
const LIGHT_ENERGY_PER_TIER: Array[float] = [0.0, 1.6, 2.8, 4.5]
const LIGHT_RANGE_PER_TIER: Array[float] = [0.0, 5.0, 7.0, 9.0]
# Center the sprite at the player's torso so the smoke surrounds the
# body rather than sitting at the feet.
const SPRITE_OFFSET_Y := 1.0

var _tier: int = 0
var _sprite: Sprite3D
var _light: OmniLight3D
var _frame_w: int = 0
var _frame_h: int = 0
var _anim_t: float = 0.0


func _ready() -> void:
	_build_sprite()
	_build_light()
	_apply_tier()


func _build_sprite() -> void:
	_sprite = Sprite3D.new()
	_sprite.name = &"SmokeSprite"
	_sprite.texture = SMOKE_TEXTURE
	_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# region_enabled lets us crop to one cell of the spritesheet; we
	# update region_rect each frame in _process to cycle through them.
	_sprite.region_enabled = true
	_sprite.modulate = Color(COLOR.r, COLOR.g, COLOR.b, ALPHA_PER_TIER[0])
	# transparent + shaded=false = unlit alpha-blended billboard. The
	# OmniLight handles the wider lit wash; the sprite itself is just
	# a self-glowing texture.
	_sprite.transparent = true
	_sprite.shaded = false
	_sprite.no_depth_test = false
	# Disable depth-write so multiple overlapping sprite frames don't
	# punch holes in each other (only matters if we ever stack auras).
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_sprite.position = Vector3(0.0, SPRITE_OFFSET_Y, 0.0)
	_sprite.visible = false
	_frame_w = SMOKE_TEXTURE.get_width() / SPRITE_H_FRAMES
	_frame_h = SMOKE_TEXTURE.get_height() / SPRITE_V_FRAMES
	_sprite.region_rect = Rect2(0.0, 0.0, _frame_w, _frame_h)
	add_child(_sprite)


func _build_light() -> void:
	_light = OmniLight3D.new()
	_light.name = &"Spill"
	_light.light_color = COLOR
	_light.light_energy = LIGHT_ENERGY_PER_TIER[0]
	_light.omni_range = LIGHT_RANGE_PER_TIER[0]
	_light.omni_attenuation = 1.6
	# Shadow casting handles wall containment for the coloured wash on
	# world surfaces — the sprite itself doesn't try to clip on walls.
	_light.shadow_enabled = true
	_light.shadow_blur = 1.5
	_light.light_volumetric_fog_energy = 0.0
	_light.position = Vector3(0.0, SPRITE_OFFSET_Y, 0.0)
	add_child(_light)


func _process(delta: float) -> void:
	if _tier <= 0 or _sprite == null or not _sprite.visible:
		return
	_anim_t += delta * ANIM_FPS
	# Wrap once we've passed the last used frame — the spritesheet has
	# 49 cells but only the first 46 are painted, so we loop at 46.
	var frame_idx := int(_anim_t) % TOTAL_FRAMES
	var fx := frame_idx % SPRITE_H_FRAMES
	var fy := frame_idx / SPRITE_H_FRAMES
	_sprite.region_rect = Rect2(float(fx * _frame_w), float(fy * _frame_h), float(_frame_w), float(_frame_h))


# Public API — PrototypePlayer calls this on perks_changed with the
# unlocked AMB tier (0..3). T0 hides everything; T1+ scales visibility.
func set_tier(t: int) -> void:
	var clamped := clampi(t, 0, 3)
	if clamped == _tier:
		return
	_tier = clamped
	_apply_tier()


func _apply_tier() -> void:
	var on := _tier > 0
	if _sprite != null:
		_sprite.visible = on
		_sprite.pixel_size = PIXEL_SIZE_PER_TIER[_tier]
		_sprite.modulate = Color(COLOR.r, COLOR.g, COLOR.b, ALPHA_PER_TIER[_tier])
	if _light != null:
		_light.visible = on
		_light.light_energy = LIGHT_ENERGY_PER_TIER[_tier]
		_light.omni_range = LIGHT_RANGE_PER_TIER[_tier]
