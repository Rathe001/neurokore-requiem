extends CharacterBody2D

const SPEED := 240.0

func _physics_process(_delta: float) -> void:
	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * SPEED
	move_and_slide()
