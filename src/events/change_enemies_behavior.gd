extends LevelEvent

@export var enemy_group: EnemyGroup

func _trigger_event():
	if not is_instance_valid(enemy_group):
		return
	enemy_group.trigger(true)

func _complete_event():
	pass
