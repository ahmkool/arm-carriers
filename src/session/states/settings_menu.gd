class_name SettingsMenuState
extends SessionState


func enter() -> void:
	session_flow.show_menu_screen("settingsmenu")
	session_flow.set_menu_navigation_active(true, session_flow.settings_menu_focus)
	session_flow.set_menu_cancel_enabled(true)
