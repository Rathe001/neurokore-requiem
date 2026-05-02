extends Marker3D
class_name PrototypePlayerSpawn
## Marker placed by InteractableBuilder for slots whose scene is this script.
## Joins the &"player_spawn" group on _ready so PrototypeRoot can find it
## without knowing which room the marker landed in. Generated and authored
## levels both use the same mechanism.

func _ready() -> void:
	add_to_group(&"player_spawn")
