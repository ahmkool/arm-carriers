class_name SpikeTrapEvent
extends LevelEvent
## Starts a SpikeTrap's walls closing, or sends them back. The trap resets itself on respawn,
## so there is nothing to restore here.

enum Action { START, RETRACT }

@export var trap: SpikeTrap
@export var action := Action.START


func _trigger_event():
	if not is_instance_valid(trap):
		return
	if action == Action.RETRACT:
		trap.retract()
		return
	trap.start()
