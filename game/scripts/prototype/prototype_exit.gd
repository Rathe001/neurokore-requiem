class_name PrototypeExit
extends HoverableInteractable

# Locked teleporter pad. Joins the "boss_listeners" group so PrototypeEnemy
# dispatches on_boss_died() when any boss falls. Once unlocked, the player
# can interact() to trigger a level reset on the PrototypeRoot.

const TINT_LOCKED := Color(0.95, 0.15, 0.15, 1.0)
const TINT_UNLOCKED := Color(0.25, 1.0, 0.45, 1.0)
const PULSE_SPEED := 2.4
const PULSE_MIN := 0.6
const PULSE_MAX := 1.0

@onready var pad_mesh: MeshInstance3D = $Pad
@onready var ring_mesh: MeshInstance3D = $Ring

var _locked: bool = true
var _pad_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _pulse_t: float = 0.0

func _ready() -> void:
	add_to_group(&"boss_listeners")
	_pad_mat = StandardMaterial3D.new()
	_pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_pad_mat.metallic = 0.6
	_pad_mat.roughness = 0.3
	_pad_mat.emission_enabled = true
	_pad_mat.emission_energy_multiplier = 1.4
	pad_mesh.material_override = _pad_mat
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(0, 0, 0, 0)
	_ring_mat.emission_enabled = true
	_ring_mat.emission_energy_multiplier = 4.0
	ring_mesh.material_override = _ring_mat
	super._ready()
	_refresh_tint()

func _process(delta: float) -> void:
	# Subtle pulse on the unlocked ring so the player notices it's active.
	if _locked:
		return
	_pulse_t += delta * PULSE_SPEED
	var pulse := lerpf(PULSE_MIN, PULSE_MAX, 0.5 + 0.5 * sin(_pulse_t))
	_ring_mat.emission_energy_multiplier = 4.0 * pulse

func _get_outline_source() -> MeshInstance3D:
	return pad_mesh

func _get_tooltip_text() -> String:
	var key := &"EXIT_TOOLTIP_UNLOCKED" if not _locked else &"EXIT_TOOLTIP_LOCKED"
	return tr(key)

# Re-lock when the level resets so the next boss must fall before the pad
# becomes interactive again.
func reset_state() -> void:
	lock()

func is_locked() -> bool:
	return _locked

func unlock() -> void:
	if not _locked:
		return
	_locked = false
	_refresh_tint()

func lock() -> void:
	if _locked:
		return
	_locked = true
	_refresh_tint()

# Group dispatch from PrototypeEnemy._die() when a boss falls.
func on_boss_died(_boss: Node) -> void:
	unlock()

func interact(_user: Node) -> void:
	if _locked:
		get_tree().call_group(&"interactable_tooltip", &"show_text", tr(&"EXIT_TOOLTIP_LOCKED"))
		return
	get_tree().call_group(&"level_reset_handler", &"reset_level")

func _refresh_tint() -> void:
	var c := TINT_LOCKED if _locked else TINT_UNLOCKED
	_pad_mat.albedo_color = Color(c.r * 0.25, c.g * 0.25, c.b * 0.25, 1.0)
	_pad_mat.emission = c
	_ring_mat.emission = c
