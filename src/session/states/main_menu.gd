class_name MainMenuState
extends SessionState


func enter() -> void:
	session_flow.show_menu_screen("mainmenu")
	session_flow.set_menu_navigation_active(true, session_flow.level_picker_focus)
	session_flow.set_menu_cancel_enabled(true)
