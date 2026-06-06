class_name PressStartState
extends SessionState

const START_ACTIONS: Array[StringName] = [
	&"ui_accept",
	&"p0_start",
	&"p1_start",
	&"p0_accept",
	&"p1_accept",
]


func enter() -> void:
	session_flow.show_menu_screen("pressstart")
	session_flow.set_menu_navigation_active(false)
	session_flow.set_menu_cancel_enabled(false)


func handle_input(event: InputEvent) -> bool:
	if not _is_start_press(event):
		return false
	session_flow.transition_to("homemenu")
	return true


func _is_start_press(event: InputEvent) -> bool:
	if not event.is_pressed():
		return false
	if event.is_echo():
		return false
	for action in START_ACTIONS:
		if event.is_action(action):
			return true
	return false
