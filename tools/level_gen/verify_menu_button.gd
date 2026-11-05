extends Node
## Checks a level's menu button fits on screen and loads its level. Set MENU_BUTTON to the node name.
## Run against res://src/menu/menu.tscn through godot.sh.

const BOX := "MainMenuRoot/PanelContainer/MarginContainer/VBoxContainer/"


func _ready() -> void:
	get_tree().create_timer(50.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	await get_tree().create_timer(3.0).timeout
	var menu := get_tree().current_scene
	menu.call("_on_play_pressed")
	await get_tree().create_timer(1.5).timeout
	var panel := menu.get_node("MainMenuRoot/PanelContainer") as Control
	var button := menu.get_node(BOX + OS.get_environment("MENU_BUTTON")) as Button
	var rect := panel.get_global_rect()
	var fits := rect.position.y >= 0.0 and rect.end.y <= get_viewport().get_visible_rect().size.y
	print(("PASS " if fits and button.is_visible_in_tree() else "FAIL ") + "menu fits: panel %.0f to %.0f" % [rect.position.y, rect.end.y])
	get_tree().root.get_texture().get_image().save_png(OS.get_environment("VERIFY_OUT") + "/menu.png")
	button.pressed.emit()
	_wait_for_level(menu.get_node("LevelStartChoiceRoot") as Control)


func _wait_for_level(save_prompt: Control) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if get_tree().current_scene is WorldLocal:
			break
		if save_prompt.is_visible_in_tree():
			_finish_at_save_prompt()
			return
		await get_tree().process_frame
	var world := get_tree().current_scene as WorldLocal
	if world == null:
		print("FAIL button did not load a level")
		get_tree().quit(1)
		return
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	print("PASS button loads ", world.scene_file_path)
	await get_tree().create_timer(1.5).timeout
	print("RESULT fails=0")
	get_tree().quit(0)


## The level has saved progress. Stop here: "From beginning" could overwrite the player's checkpoint.
func _finish_at_save_prompt() -> void:
	print("PASS button opens the continue prompt (level has saved progress)")
	print("RESULT fails=0")
	get_tree().quit(0)
