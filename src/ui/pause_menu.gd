extends Node

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not _is_pause_input(event):
		return
	get_tree().paused = not get_tree().paused
	get_viewport().set_input_as_handled()


func _is_pause_input(event: InputEvent) -> bool:
	if not event.is_action("pause"):
		return false
	if not event.is_pressed():
		return false
	if event.is_echo():
		return false
	return true
	
