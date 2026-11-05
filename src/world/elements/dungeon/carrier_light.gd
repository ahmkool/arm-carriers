extends OmniLight3D

## A warm light that follows the two carriers, so they can always see what is around them.
@export var height: float = 5.0
@export var smoothing: float = 10.0

var _players: Node


func _process(delta: float) -> void:
	if not is_instance_valid(_players):
		_players = get_tree().current_scene.get_node_or_null("Players")
	if not is_instance_valid(_players):
		return
	var target := _carriers_midpoint() + Vector3.UP * height
	global_position = global_position.lerp(target, clampf(smoothing * delta, 0.0, 1.0))


func _carriers_midpoint() -> Vector3:
	var sum := Vector3.ZERO
	var count := 0
	for child in _players.get_children():
		if child is Node3D:
			sum += (child as Node3D).global_position
			count += 1
	if count == 0:
		return global_position
	return sum / float(count)
