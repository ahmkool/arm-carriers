class_name ShaderCompilingState
extends SessionState


func enter() -> void:
	session_flow.show_menu_screen("shadercompiling")
	session_flow.set_menu_navigation_active(false)
	session_flow.set_menu_cancel_enabled(false)
	session_flow.start_pending_level_load()
