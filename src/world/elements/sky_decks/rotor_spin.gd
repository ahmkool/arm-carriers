extends Node3D
## Spins a rotor's blades. The start angle comes from its position, so rotors don't turn in step.

@export var speed: float = 11.0


func _ready() -> void:
	rotation.y = global_position.x * 1.3 + global_position.z * 0.7


func _process(delta: float) -> void:
	rotate_y(speed * delta)
