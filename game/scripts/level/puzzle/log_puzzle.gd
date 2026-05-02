extends PuzzleDef
class_name LogPuzzle
## Demonstration of the custom-puzzle escape hatch — confirms a designer can
## drop in a new PuzzleDef subclass and have the level builder dispatch it
## without any changes to the puzzle layer or builders. Just prints a message
## when applied. Replace with whatever one-off behaviour you need.

@export var message: String = ""


func apply(_ctx: LevelBuildContext, _slots: Dictionary, _doors: Dictionary) -> void:
	print_rich("[color=cyan][LogPuzzle][/color] %s" % message)
