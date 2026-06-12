class_name PauseControlsState
extends PauseState


func enter() -> void:
	pause_flow.show_pause_screen("controls")
	pause_flow.set_menu_navigation_active(true, pause_flow.controls_focus)
	pause_flow.set_menu_cancel_enabled(true)
