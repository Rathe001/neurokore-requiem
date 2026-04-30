class_name PrototypeLootCrate
extends HoverableInteractable

const ITEM_PICKUP_SCENE: PackedScene = preload("res://scenes/prototype/prototype_item_pickup.tscn")

const COLOR_CLOSED := Color(0.9, 0.75, 0.3, 1.0)
const COLOR_OPENED := Color(0.35, 0.35, 0.35, 1.0)

## Items to spawn on open. When empty, rolls random items instead.
@export var fixed_items: Array[Item] = []
## Number of random items to spawn when fixed_items is empty.
@export var random_item_count: int = 3
## Weapon base resource paths to roll as test items. Overrides random_item_count.
@export var test_weapon_base_paths: Array[String] = []

@onready var mesh: MeshInstance3D = $Mesh
@onready var lid: MeshInstance3D = $Lid

var _opened: bool = false
var _mat: StandardMaterial3D

func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.emission_enabled = true
	_mat.emission_energy_multiplier = 2.0
	_apply_color(COLOR_CLOSED)
	mesh.material_override = _mat
	super._ready()

func _get_outline_source() -> MeshInstance3D:
	return mesh

func _get_tooltip_text() -> String:
	return "Loot Crate" if not _opened else "Empty Crate"

func reset_state() -> void:
	_opened = false
	_apply_color(COLOR_CLOSED)
	if lid != null:
		lid.visible = true
	input_ray_pickable = true
	SpatialGrid.register(self, &"interactables")

func interact(_user: Node) -> void:
	if _opened:
		return
	_opened = true
	_apply_color(COLOR_OPENED)
	if lid != null:
		var tween := create_tween()
		tween.tween_property(lid, "rotation_degrees:x", -110.0, 0.3).set_ease(Tween.EASE_OUT)

	var items: Array[Item] = []
	if fixed_items.size() > 0:
		items.assign(fixed_items)
	elif test_weapon_base_paths.size() > 0:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var ilvl := maxi(1, PlayerState.level)
		for path in test_weapon_base_paths:
			var base := load(path) as WeaponBase
			if base == null:
				push_warning("[LootCrate] missing WeaponBase: %s" % path)
				continue
			items.append(ItemRoller.roll_from_base(base, ilvl, &"magic", rng))
	else:
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		var ilvl := maxi(1, PlayerState.level)
		for _i in random_item_count:
			items.append(ItemRoller.roll_random(ilvl, rng))

	var parent := get_parent()
	if parent == null:
		return
	for i in items.size():
		var pickup := ITEM_PICKUP_SCENE.instantiate()
		pickup.configure(items[i])
		parent.add_child(pickup)
		pickup.global_position = global_position + Vector3(0.0, 1.5, 0.0)

	# Become inert after opening.
	SpatialGrid.unregister(self)
	if _outline != null:
		_outline.visible = false
	remove_from_group(&"hovered_clickable")
	remove_from_group(&"tooltip_target")
	get_tree().call_group(&"interactable_tooltip", &"hide_tooltip")

func _apply_color(c: Color) -> void:
	_mat.albedo_color = c
	_mat.emission = c
