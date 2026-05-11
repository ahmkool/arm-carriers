extends GameState


func enter() -> void:
	var world_local := world as WorldLocal
	if world_local == null:
		push_error("ResettingCheckpointState: world is not WorldLocal")
		return
	world_local.restart_game()
