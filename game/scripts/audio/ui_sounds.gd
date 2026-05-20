extends Node
## Autoload that wires UI sound effects to all Button and TabContainer
## nodes automatically. Connects to the SceneTree's node_added signal
## so newly-created UI elements get sounds without any per-script work.
##
## Plays via WeaponSounds.play_ui() which routes through the UI audio bus.

const CLICK_DB := 0.0
const HOVER_DB := -6.0


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	# Wire existing nodes (scene already built before this autoload runs).
	_wire_existing(get_tree().root)


func _wire_existing(node: Node) -> void:
	_try_wire(node)
	for child in node.get_children():
		_wire_existing(child)


func _on_node_added(node: Node) -> void:
	# Deferred so the node is fully in the tree and ready. Closure avoids
	# the Godot 4 deferred type-check bug ("Cannot convert argument 1 from
	# Object to Object") — no argument crosses the deferred boundary.
	#
	# instance_from_id (int capture) instead of an Object capture — see
	# OverhangFader for the rationale; node_added fires on every node
	# added, so on level reload we get a wave of freed-Object lambdas.
	var node_id: int = node.get_instance_id()
	(func() -> void:
		var n := instance_from_id(node_id) as Node
		if n != null:
			_try_wire(n)
	).call_deferred()


func _try_wire(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node is BaseButton:
		if not node.pressed.is_connected(_on_button_pressed):
			node.pressed.connect(_on_button_pressed)
		if not node.mouse_entered.is_connected(_on_button_hover):
			node.mouse_entered.connect(_on_button_hover)
	if node is TabBar:
		if not node.tab_changed.is_connected(_on_tab_changed):
			node.tab_changed.connect(_on_tab_changed)
	if node is TabContainer:
		if not node.tab_changed.is_connected(_on_tab_changed):
			node.tab_changed.connect(_on_tab_changed)


func _on_button_pressed() -> void:
	WeaponSounds.play_ui(&"ui_click", CLICK_DB)


func _on_button_hover() -> void:
	WeaponSounds.play_ui(&"ui_hover", HOVER_DB)


func _on_tab_changed(_tab: int) -> void:
	WeaponSounds.play_ui(&"ui_navigate", CLICK_DB)
