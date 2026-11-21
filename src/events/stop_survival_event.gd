class_name StopSurvivalEvent
extends LevelEvent
## Stops an endless SurvivalEnemyGroup's spawning; the group still emits enemies_defeated once the ones left are dead.
## Set `clear_remaining` true to also defeat any still-alive support enemies immediately (e.g. a helper laser drone).

@export var survival_group: SurvivalEnemyGroup
@export var clear_remaining := false


func _trigger_event() -> void:
	if not is_instance_valid(survival_group):
		push_warning("StopSurvivalEvent: survival_group is not set")
		return
	survival_group.stop()
	if clear_remaining:
		_kill_remaining_enemies()


func _kill_remaining_enemies() -> void:
	var container := survival_group.get_node_or_null(^"Enemies")
	if container == null:
		return
	for child in container.get_children():
		var enemy := child as EnemyLocal
		if enemy != null and enemy.is_alive():
			var health := Health.from_target(enemy)
			if health != null:
				health.kill(enemy.global_position + Vector3.UP)
			else:
				enemy.die(enemy.global_position + Vector3.UP)
