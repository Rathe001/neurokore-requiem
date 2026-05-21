class_name HoverableInteractable
extends StaticBody3D

# Shared scaffolding for clickable world objects: hover outline, group
# membership, tooltip dispatch, and a reset_state() hook so the level-reset
# loop can restore initial state. Subclasses provide the outline source mesh,
# tooltip text, and any reset behavior.

@export var display_name: String = ""

# The MeshInstance3D the OutlineCompositor wraps when the mouse enters
# this body. Resolved once in _ready via _get_outline_source(); cached so
# _on_mouse_exited can detach against the same source.
var _outline_source: MeshInstance3D

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
	if _outline_source != null:
		OutlineCompositor.attach(_outline_source, Color.WHITE)
	add_to_group(&"hovered_clickable")
	add_to_group(&"tooltip_target")
	var text := _get_tooltip_text()
	if text != "":
		get_tree().call_group(&"interactable_tooltip", &"show_text", text)


func _on_mouse_exited() -> void:
	if _outline_source != null:
		OutlineCompositor.detach(_outline_source)
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")
