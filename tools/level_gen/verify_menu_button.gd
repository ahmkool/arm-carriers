extends Node
## Checks a level has a poster in the level select and that firing at it loads the level.
## Set MENU_LEVEL to the level's scene path. Run against res://src/menu/menu.tscn through godot.sh.


func _ready() -> void:
	get_tree().create_timer(50.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	await get_tree().create_timer(3.0).timeout
	var menu := get_tree().current_scene
	menu.call("_on_play_pressed")
	await get_tree().create_timer(1.0).timeout
	var scene_id := OS.get_environment("MENU_LEVEL")
	var slot := _find_catalog_slot(scene_id)
	if slot.is_empty():
		print("FAIL no poster for ", scene_id, " in level_select_catalog.gd")
		get_tree().quit(1)
		return
	print("PASS poster found in tab ", LevelSelectCatalog.GROUPS[slot[0]]["name"])
	var level_select := menu.get_node("LevelSelectRoot")
	level_select.call("_show_group", slot[0], slot[1])
	await get_tree().create_timer(1.0).timeout
	get_tree().root.get_texture().get_image().save_png(OS.get_environment("VERIFY_OUT") + "/menu.png")
	level_select.call("_fire")
	_wait_for_level(menu.get_node("LevelStartChoiceRoot") as Control)


## Returns the tab and poster index, or an empty array when the level has no poster.
func _find_catalog_slot(scene_id: String) -> Array:
	for group_index in LevelSelectCatalog.GROUPS.size():
		var levels: Array = LevelSelectCatalog.GROUPS[group_index]["levels"]
		var poster_index := levels.find_custom(func(level): return level["scene"] == scene_id)
		if poster_index >= 0:
			return [group_index, poster_index]
	return []


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
		print("FAIL firing did not load a level")
		get_tree().quit(1)
		return
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	print("PASS firing loads ", world.scene_file_path)
	await get_tree().create_timer(1.5).timeout
	print("RESULT fails=0")
	get_tree().quit(0)


## The level has saved progress. Stop here: "From beginning" could overwrite the player's checkpoint.
func _finish_at_save_prompt() -> void:
	print("PASS button opens the continue prompt (level has saved progress)")
	print("RESULT fails=0")
	get_tree().quit(0)
