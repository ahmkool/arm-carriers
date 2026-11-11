extends LevelEvent
## Starts an enemy group (such as a survival wave) a moment after it runs, and again whenever a checkpoint that
## lists it in events_completed is restored. Use it for a fight that starts where the carriers spawn, where an
## area trigger they spawn inside might not fire.
## The delay also lets the checkpoint reset its enemy_groups_reset first, which it does after its events.

@export var enemy_group: EnemyGroup
@export_range(0.0, 10.0, 0.1) var delay_seconds := 2.0


func _trigger_event() -> void:
	_start_later()


func _complete_event() -> void:
	_start_later()


func _start_later() -> void:
	if not is_instance_valid(enemy_group):
		push_warning("StartEnemyGroupEvent: enemy_group is not set")
		return
	await get_tree().create_timer(delay_seconds).timeout
	if not is_instance_valid(enemy_group):
		return
	enemy_group.trigger(true)
