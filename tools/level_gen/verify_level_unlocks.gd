extends Node
## Checks the level select's unlock rules and screenshots the menu at a few stages of progress.
##   tools/level_gen/godot.sh test tools/level_gen/verify_level_unlocks.gd res://src/menu/menu.tscn <out_dir>
## Swaps GameSave's completion table in memory only and never saves, so the real save is untouched.

var out_dir: String
var fails := 0
var level_select: LevelTargetSelect


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	get_tree().create_timer(60.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func _run() -> void:
	var real_completed: Dictionary = GameSave.get("_completed")
	LevelSelectCatalog.force_unlock_all = false
	_check_fresh_save()
	_check_partial_progress()
	_check_weapons()
	await wait(3.0)
	var menu := get_tree().current_scene
	_set_completed({})
	menu.call("_on_play_pressed")
	await wait(1.0)
	level_select = menu.get_node("LevelSelectRoot") as LevelTargetSelect
	await _shoot_group(0, "fresh_dungeon.png")
	await _shoot_group(1, "fresh_crypt.png")
	_check_locked_pick()
	_set_completed(_cleared(["res://src/world/levels/world_local.tscn", "res://src/world/levels/world_local_level_2_medieval.tscn", "res://src/world/levels/world_local_bazooka.tscn", LevelSelectCatalog.DUNGEON_BOSS]))
	await _shoot_group(0, "dungeon_done.png")
	await _shoot_group(1, "crypt_open.png")
	await _shoot_group(5, "challenges_open.png")
	GameSave.set("_completed", real_completed)
	print("RESULT %s fails=%d" % ["OK" if fails == 0 else "FAILED", fails])
	get_tree().quit(0 if fails == 0 else 1)


func _check_fresh_save() -> void:
	_set_completed({})
	check("fresh: dungeon open", LevelSelectCatalog.is_group_open(0))
	check("fresh: level 1 open", LevelSelectCatalog.is_level_open(0, 0))
	check("fresh: level 2 locked", not LevelSelectCatalog.is_level_open(0, 1), LevelSelectCatalog.lock_reason(0, 1))
	check("fresh: crypt locked", not LevelSelectCatalog.is_group_open(1), LevelSelectCatalog.lock_reason(1, 0))
	check("fresh: challenges locked", not LevelSelectCatalog.is_group_open(5), LevelSelectCatalog.lock_reason(5, 0))
	check("fresh: reason names the boss", LevelSelectCatalog.lock_reason(1, 0) == "Slay Skeleton Boss", LevelSelectCatalog.lock_reason(1, 0))


func _check_partial_progress() -> void:
	_set_completed(_cleared(["res://src/world/levels/world_local.tscn"]))
	check("after level 1: level 2 open", LevelSelectCatalog.is_level_open(0, 1))
	check("after level 1: level 3 locked", not LevelSelectCatalog.is_level_open(0, 2), LevelSelectCatalog.lock_reason(0, 2))
	check("after level 1: 1/4 cleared", LevelSelectCatalog.cleared_count(0) == 1)
	_set_completed(_cleared([LevelSelectCatalog.DUNGEON_BOSS]))
	check("after boss: crypt open", LevelSelectCatalog.is_group_open(1))
	check("after boss: crypt level 2 locked", not LevelSelectCatalog.is_level_open(1, 1))
	check("after boss: frozen shore locked", not LevelSelectCatalog.is_group_open(2))
	check("after boss: all challenges open", LevelSelectCatalog.is_level_open(5, 2))


func _check_weapons() -> void:
	var boss: Dictionary = LevelSelectCatalog.GROUPS[0]["levels"][3]
	_set_completed({})
	var offered := LevelSelectCatalog.offered_weapons(boss)
	check("uncleared offers own weapon only", offered.size() == 1 and offered[0] == "bazooka", str(offered))
	_set_completed({LevelSelectCatalog.save_id(boss, "saw"): true})
	check("cleared with any weapon offers all", LevelSelectCatalog.offered_weapons(boss).size() == LevelSelectCatalog.weapons_for(boss).size())
	LevelSelectCatalog.force_unlock_all = true
	_set_completed({})
	check("force unlock opens everything", LevelSelectCatalog.is_level_open(4, 3) and LevelSelectCatalog.offered_weapons(boss).size() > 1)
	LevelSelectCatalog.force_unlock_all = false


func _check_locked_pick() -> void:
	level_select.call("_show_group", 0, 1)
	level_select.call("_pick_poster")
	check("picking a locked poster stays in the menu", level_select.get("_input_enabled") and not level_select.get("_choosing_weapon"))


func _shoot_group(group_index: int, file_name: String) -> void:
	level_select.call("_show_group", group_index, 0)
	await wait(1.2)
	await shot(file_name)


func _cleared(scenes: Array) -> Dictionary:
	var result := {}
	for level in _levels_for(scenes):
		result[LevelSelectCatalog.save_id(level, level["weapon"])] = true
	return result


func _levels_for(scenes: Array) -> Array:
	var result := []
	for group in LevelSelectCatalog.GROUPS:
		result.append_array(group["levels"].filter(func(level): return scenes.has(level["scene"])))
	return result


func _set_completed(completed: Dictionary) -> void:
	GameSave.set("_completed", completed)
