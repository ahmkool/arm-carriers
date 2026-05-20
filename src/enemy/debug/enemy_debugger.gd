extends Node

var _last_state_name := ""

@onready var _state_machine: EnemyStateMachine = _find_state_machine()


func _find_state_machine() -> EnemyStateMachine:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("EnemyStateMachine") as EnemyStateMachine


func _process(_delta: float) -> void:
	if _state_machine == null or _state_machine.current_state == null:
		return
	var state_name := _state_machine.current_state.name
	if state_name == _last_state_name:
		return
	_last_state_name = state_name
	print("Enemy state: ", state_name)
