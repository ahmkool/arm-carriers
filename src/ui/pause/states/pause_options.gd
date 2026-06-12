class_name PauseOptionsState
extends PauseState


func enter() -> void:
	pause_flow.show_pause_screen("options")
	pause_flow.set_menu_navigation_active(true, pause_flow.options_focus)
	pause_flow.set_menu_cancel_enabled(true)
