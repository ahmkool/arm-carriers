class_name LevelEvent
extends Node

@export var next_event: LevelEvent
signal completed(event: LevelEvent)

var _is_triggering := false

func trigger() -> void:
	if _is_triggering:
		return
	_is_triggering = true
	await _trigger_event()
	_is_triggering = false
	completed.emit(self)
	execute_next_event()

func _trigger_event():
	pass
	
func _complete_event():
	pass

func execute_next_event():
	if not is_instance_valid(next_event):
		return
	print("Triggering next event")
	next_event.trigger()
