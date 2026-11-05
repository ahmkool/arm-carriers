class_name LevelSelectState
extends SessionState


func enter() -> void:
	session_flow.show_menu_screen("levelselect")
	session_flow.set_menu_navigation_active(false)
	session_flow.set_menu_cancel_enabled(false)
	session_flow.level_select_root.open()
