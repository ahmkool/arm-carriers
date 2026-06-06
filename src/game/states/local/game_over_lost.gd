extends GameState

const MESSAGE_HOLD_SECONDS := 2.0
const FADE_TO_CHECKPOINT_DURATION := 0.75


func enter() -> void:
	GameplayInput.lock()
	world.get_node("UI/InfoMessage").show()
	world.get_node("UI/InfoMessage/PanelContainer/MarginContainer/InfoLabel").text = "Game Over !"
	_begin_return_to_checkpoint_sequence()


func exit() -> void:
	GameplayInput.unlock()


func _begin_return_to_checkpoint_sequence() -> void:
	await get_tree().create_timer(MESSAGE_HOLD_SECONDS).timeout
	if not is_inside_tree():
		return
	ScreenFade.fade_to_black(FADE_TO_CHECKPOINT_DURATION)
	await get_tree().create_timer(FADE_TO_CHECKPOINT_DURATION).timeout
	if not is_inside_tree():
		return
	world.restart_game()
