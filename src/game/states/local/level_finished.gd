extends GameState

const MESSAGE_HOLD_SECONDS := 3.0
const FADE_TO_MENU_DURATION := 0.75


func enter() -> void:
	GameplayInput.lock()
	world.get_node("UI/InfoMessage").show()
	world.get_node("UI/InfoMessage/PanelContainer/MarginContainer/InfoLabel").text = "Level Complete - congratulations !"
	_begin_return_to_menu_sequence()


func exit() -> void:
	GameplayInput.unlock()


func _begin_return_to_menu_sequence() -> void:
	await get_tree().create_timer(MESSAGE_HOLD_SECONDS).timeout
	if not is_inside_tree():
		return
	ScreenFade.fade_to_black(FADE_TO_MENU_DURATION)
	await get_tree().create_timer(FADE_TO_MENU_DURATION).timeout
	if not is_inside_tree():
		return
	GameplayInput.unlock()
	ScreenFade.fade_from_black(FADE_TO_MENU_DURATION)
	SessionFlow.go_to_main_menu()
