extends LevelEvent

@export var enemy_group: EnemyGroup

func _trigger_event():
	if not is_instance_valid(enemy_group):
		return
	enemy_group.trigger(true)

func _complete_event():
	pass


func _on_all_players_area_trigger_4_all_players_inside():
	pass # Replace with function body.
