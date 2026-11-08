extends Node
## Test driver for the level select's weapon choice, with real input. Run against the menu:
##   tools/level_gen/godot.sh test tools/level_gen/verify_weapon_choice.gd res://src/menu/menu.tscn <out_dir>
## Arms the Skeleton Boss poster, moves between its weapons, backs out, then fires the saw and checks
## the level loads with the saw under its own save key. Stops before any checkpoint can be saved.

const BOSS_SCENE := "res://src/world/levels/world_boss_scene.tscn"

var out_dir: String
var fails := 0
var level_select: LevelTargetSelect


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	get_tree().create_timer(90.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func shot(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


## One real press, sent through the input pipeline like a key or button would be.
func press(action: StringName) -> void:
	_send_action(action, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_send_action(action, false)
	await wait(0.3)
	print("INFO after %s: %s" % [action, _state()])


func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)


func _run() -> void:
	await wait(3.0)
	var menu := get_tree().current_scene
	## Every poster and weapon open, whatever the save holds.
	LevelSelectCatalog.force_unlock_all = true
	menu.call("_on_play_pressed")
	await wait(1.0)
	level_select = menu.get_node("LevelSelectRoot") as LevelTargetSelect
	var slot := _boss_slot()
	check("boss poster offers all seven weapons", not slot.is_empty())
	if slot.is_empty():
		_finish()
		return
	level_select.call("_show_group", slot[0], slot[1])
	await wait(1.2)
	await shot("posters.png")
	await press(&"ui_accept")
	check("accept opens the weapon choice", _choosing(), _state())
	check("starts on the default weapon", _weapon_index() == 0, _state())
	await wait(0.6)
	await shot("choice_bazooka.png")
	await press(&"ui_right")
	check("right moves to the sword", _weapon_index() == 1, _state())
	await press(&"ui_left")
	await press(&"ui_left")
	check("left wraps round to the last weapon", _weapon_index() == 6, _state())
	await press(&"ui_down")
	check("down on the last row stays", _weapon_index() == 6, _state())
	await press(&"ui_up")
	check("up moves to the row above", _weapon_index() == 2, _state())
	await press(&"ui_down")
	await press(&"ui_left")
	await wait(0.6)
	await shot("choice_second_row.png")
	await press(&"ui_cancel")
	check("cancel backs out to the posters", not _choosing() and level_select.visible, _state())
	await press(&"ui_up")
	await press(&"ui_down")
	check("tabs work again after backing out", level_select.get("_group_index") == slot[0], _state())
	level_select.call("_show_group", slot[0], slot[1])
	await wait(0.8)
	await press(&"ui_accept")
	await press(&"ui_right")
	await press(&"ui_right")
	check("re-armed and on the saw", _choosing() and _weapon_index() == 2, _state())
	await press(&"ui_accept")
	await _check_level_loads_with_saw(menu.get_node("LevelStartChoiceRoot") as Control)
	_finish()


func _check_level_loads_with_saw(save_prompt: Control) -> void:
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline:
		if get_tree().current_scene is WorldLocal:
			break
		if save_prompt.is_visible_in_tree():
			check("saw has saved progress: continue prompt shown", true)
			return
		await get_tree().process_frame
	var world := get_tree().current_scene as WorldLocal
	check("firing loads the boss level", world != null and world.scene_file_path == BOSS_SCENE)
	if world == null:
		return
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	check("level carries the saw", world.get_active_weapon_id() == "saw", world.get_active_weapon_id())
	check("level saves under the saw key", world.get_level_id() == GameSave.level_key(BOSS_SCENE, "saw"), world.get_level_id())
	await wait(4.0)
	await shot("level_saw.png")


func _boss_slot() -> Array:
	for group_index in LevelSelectCatalog.GROUPS.size():
		var levels: Array = LevelSelectCatalog.GROUPS[group_index]["levels"]
		var index := levels.find_custom(func(level): return level["scene"] == BOSS_SCENE)
		if index >= 0 and LevelSelectCatalog.weapons_for(levels[index]).size() == WeaponCatalog.WEAPONS.size():
			return [group_index, index]
	return []


func _choosing() -> bool:
	return level_select.get("_choosing_weapon")


func _weapon_index() -> int:
	return level_select.get("_weapon_index")


func _state() -> String:
	return "choosing=%s weapon=%s" % [level_select.get("_choosing_weapon"), level_select.get("_weapon_index")]


func _finish() -> void:
	print("RESULT %s fails=%d" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(0 if fails == 0 else 1)
