class_name SessionState
extends RefCounted

var session_flow: SessionFlowNode


func enter() -> void:
	pass


func exit() -> void:
	pass


func handle_input(_event: InputEvent) -> bool:
	return false
