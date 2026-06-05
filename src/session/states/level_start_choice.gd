class_name LevelStartChoiceState
extends SessionState


func enter() -> void:
	session_flow.show_menu_screen("levelstartchoice")
	session_flow.update_level_start_choice_prompt()
	session_flow.set_menu_navigation_active(true, session_flow.level_start_choice_focus)
	session_flow.set_menu_cancel_enabled(true)
