class_name CharacterSelectState
extends SessionState


func enter() -> void:
	session_flow.show_menu_screen("characterselect")
	session_flow.set_menu_navigation_active(false)
	session_flow.set_menu_cancel_enabled(false)
	session_flow.character_select_root.open()
