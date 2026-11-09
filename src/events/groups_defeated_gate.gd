class_name GroupsDefeatedGate
extends LevelEvent
## Waits for several enemy groups to all be defeated, then sets `checkpoint`, runs `also_trigger` and `next_event`.
## With no groups it passes straight through, which makes it a way to set a checkpoint from an event chain.
## Connect every group's `enemies_defeated` to `trigger`: each call checks whether the rest are done too, so the
## order they finish in doesn't matter. Used where one reward needs two fights, such as a survival wave plus a
## separate group fought at the same time.

@export var groups: Array[EnemyGroup] = []
## Set as the current checkpoint once every group is down. Optional.
@export var checkpoint: Checkpoint
## Run alongside `next_event`, such as camera framings.
@export var also_trigger: Array[LevelEvent] = []


func trigger() -> void:
	if not _all_defeated():
		return
	if checkpoint != null:
		checkpoint._trigger_checkpoint()
	for event in also_trigger:
		if event != null:
			event.trigger()
	super.trigger()


func _all_defeated() -> bool:
	for group in groups:
		if not is_instance_valid(group):
			continue
		if not bool(group.get("signal_emitted")):
			return false
	return true
