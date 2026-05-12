class_name EnemyGroup
extends Node3D

## Emitted when this group's success condition is met (all pre-placed enemies dead, or survival timer ended with no living spawns).
signal enemies_defeated


func trigger(offensive: bool = true) -> void:
	pass


func mark_as_defeated() -> void:
	pass


func reset() -> void:
	pass
