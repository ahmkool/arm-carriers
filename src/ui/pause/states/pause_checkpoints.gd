class_name PauseCheckpointsState
extends PauseState


func enter() -> void:
	pause_flow.show_pause_screen("checkpoints")
	pause_flow.set_menu_navigation_active(true, pause_flow.checkpoints_focus)
	pause_flow.set_menu_cancel_enabled(true)
