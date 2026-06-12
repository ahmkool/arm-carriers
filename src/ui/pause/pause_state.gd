class_name PauseState
extends RefCounted

var pause_flow: PauseFlowNode


func enter() -> void:
	pass


func exit() -> void:
	pass


func handle_input(_event: InputEvent) -> bool:
	return false
