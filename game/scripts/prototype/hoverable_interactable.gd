class_name HoverableInteractable
extends StaticBody3D

# Shared scaffolding for clickable world objects: hover outline, group
# membership, tooltip dispatch, and a reset_state() hook so the level-reset
# loop can restore initial state. Subclasses provide the outline source mesh,
# tooltip text, and any reset behavior.
#
# Outline visibility has two triggers:
#   1. Mouse hover  → bright white outline, tooltip shows.
#   2. Proximity    → dim cyan outline whenever the player is within
#                     interact range, no tooltip. Gives a visual cue
#                     that this object can be interacted with (matches
#                     the "I" key prompt).
# Hover wins when both are active (color is set to white).

@export var display_name: String = ""

# The MeshInstance3D the OutlineCompositor wraps when the mouse enters
# this body. Resolved once in _ready via _get_outline_source(); cached so
# _on_mouse_exited can detach against the same source.
var _outline_source: MeshInstance3D

# Proximity-outline state.
const PROXIMITY_RANGE_SQ: float = 6.0          # 2.45m — slightly past INTERACT_RANGE_SQ so the
                                                # outline appears just before "I" lights up
const PROXIMITY_TICK_INTERVAL: float = 0.18    # cheap polling rate, doesn't need 60Hz
const PROXIMITY_OUTLINE_COLOR := Color(0.4, 0.85, 1.0, 1.0)  # cyan-ish, dim
const HOVER_OUTLINE_COLOR := Color.WHITE
var _proximity_active: bool = false
var _mouse_active: bool = false
var _proximity_tick_t: float = 0.0


func _ready() -> void:
	add_to_group(&"interactables")
	add_to_group(&"resettable")
	SpatialGrid.register(self, &"interactables")
	# Opt into the object-blood pipeline so kills near a chest / switch /
	# door splatter onto its surface. See PrototypeAttackIndicator's
	# "Object blood" comment block for the full pipeline.
	PrototypeAttackIndicator.register_as_blood_receiver(self)
	_outline_source = _get_outline_source()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	# Stagger the first proximity check randomly so a roomful of
	# interactables doesn't all poll on the same tick.
	_proximity_tick_t = randf() * PROXIMITY_TICK_INTERVAL
	set_process(_outline_source != null)


# Polls the local player's distance every PROXIMITY_TICK_INTERVAL seconds
# and toggles a passive outline when in range.
func _process(delta: float) -> void:
	if _outline_source == null:
		return
	_proximity_tick_t -= delta
	if _proximity_tick_t > 0.0:
		return
	_proximity_tick_t = PROXIMITY_TICK_INTERVAL
	var player := get_tree().get_first_node_in_group(&"player") as Node3D
	if player == null:
		_set_proximity(false)
		return
	var in_range := global_position.distance_squared_to(player.global_position) <= PROXIMITY_RANGE_SQ
	_set_proximity(in_range)


# Toggle the proximity-outline state. Hover takes priority for color —
# if the mouse is hovering, we leave the white color in place; otherwise
# the cyan proximity tint shows or the outline detaches entirely.
func _set_proximity(active: bool) -> void:
	if active == _proximity_active:
		return
	_proximity_active = active
	if _outline_source == null:
		return
	if _mouse_active:
		# Mouse hover owns the outline; proximity just tracks state
		# silently so the right thing happens on mouse exit.
		return
	if active:
		OutlineCompositor.attach(_outline_source, PROXIMITY_OUTLINE_COLOR)
	else:
		OutlineCompositor.detach(_outline_source)

# Subclass override: which MeshInstance3D do we wrap an outline halo around?
# Return null to skip outline (e.g. interactables with bespoke hover visuals).
func _get_outline_source() -> MeshInstance3D:
	return null

# Subclass override: tooltip text for the current state. Empty string suppresses.
func _get_tooltip_text() -> String:
	return display_name

# Subclass override: called by PrototypeRoot.reset_level() via the "resettable"
# group. Restore initial state (close doors, re-lock, clear "used" flags, etc).
func reset_state() -> void:
	pass


func _on_mouse_entered() -> void:
	_mouse_active = true
	if _outline_source != null:
		# Hover wins — attach (or recolor if proximity already attached)
		# with the brighter white tint.
		if _proximity_active:
			OutlineCompositor.set_color(_outline_source, HOVER_OUTLINE_COLOR)
		else:
			OutlineCompositor.attach(_outline_source, HOVER_OUTLINE_COLOR)
	add_to_group(&"hovered_clickable")
	add_to_group(&"tooltip_target")
	var text := _get_tooltip_text()
	if text != "":
		get_tree().call_group(&"interactable_tooltip", &"show_text", text)


func _on_mouse_exited() -> void:
	_mouse_active = false
	if _outline_source != null:
		# Mouse left. Drop back to the dim cyan tint if proximity is
		# still active; otherwise detach entirely.
		if _proximity_active:
			OutlineCompositor.set_color(_outline_source, PROXIMITY_OUTLINE_COLOR)
		else:
			OutlineCompositor.detach(_outline_source)
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
