class_name PauseMainState
extends PauseState


func enter() -> void:
	pause_flow.show_pause_screen("main")
	pause_flow.set_menu_navigation_active(true, pause_flow.main_focus)
	pause_flow.set_menu_cancel_enabled(true)
