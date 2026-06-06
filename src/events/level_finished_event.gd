class_name LevelFinishedEvent
extends LevelEvent


func _trigger_event() -> void:
	var gsm := _find_game_state_machine()
	if gsm == null:
		return
	if gsm.current == null:
		return
	if gsm.current.name.to_lower() != "playing":
		return
	gsm.transition_to("levelfinished")


func _find_game_state_machine() -> GameStateMachine:
	var world := _find_world_local()
	if world == null:
		return null
	return world.get_node_or_null("GameStateMachine") as GameStateMachine


func _find_world_local() -> WorldLocal:
	var n := get_parent()
	while n != null:
		var w := n as WorldLocal
		if w != null:
			return w
		n = n.get_parent()
	return null


func _on_survival_enemy_group_enemies_defeated():
	pass # Replace with function body.
