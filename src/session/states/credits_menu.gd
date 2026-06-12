class_name CreditsMenuState
extends SessionState


func enter() -> void:
	session_flow.show_menu_screen("creditsmenu")
	session_flow.set_menu_navigation_active(true, session_flow.credits_menu_focus)
	session_flow.set_menu_cancel_enabled(true)
