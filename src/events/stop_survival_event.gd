class_name StopSurvivalEvent
extends LevelEvent
## Stops an endless SurvivalEnemyGroup's spawning; the group still emits enemies_defeated once the ones left are dead.

@export var survival_group: SurvivalEnemyGroup


func _trigger_event() -> void:
	if not is_instance_valid(survival_group):
		push_warning("StopSurvivalEvent: survival_group is not set")
		return
	survival_group.stop()
