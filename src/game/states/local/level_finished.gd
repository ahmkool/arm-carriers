extends GameState

const MESSAGE_HOLD_SECONDS := 6.0
const FADE_TO_MENU_DURATION := 0.75


func enter() -> void:
	GameplayInput.lock()
	_persist_level_completion()
	InfoMessagePresenter.show_level_complete(world.get_node("UI/InfoMessage"))
	_begin_return_to_menu_sequence()


func exit() -> void:
	GameplayInput.unlock()


func _persist_level_completion() -> void:
	var world_local := world as WorldLocal
	if world_local == null:
		return
	if world_local.skip_save:
		return
	var level_id := world_local.get_level_id()
	if level_id.is_empty():
		push_warning("LevelFinished: cannot save completion without level_id.")
		return
	GameSave.mark_level_completed(level_id)


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
