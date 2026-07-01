extends GameState

const MESSAGE_HOLD_SECONDS := 2.0
const FADE_TO_CHECKPOINT_DURATION := 0.75


func enter() -> void:
	GameplayInput.lock()
	var you_died_screen := world.get_node("UI/YouDiedScreen") as YouDiedScreen
	you_died_screen.show_and_animate()
	_begin_return_to_checkpoint_sequence()


func exit() -> void:
	var you_died_screen := world.get_node_or_null("UI/YouDiedScreen") as YouDiedScreen
	if you_died_screen != null:
		you_died_screen.hide_screen()
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
