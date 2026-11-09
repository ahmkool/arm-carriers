extends Node
## Test driver for the survival HUD countdown (UI/SurvivalTimer) in world_local.tscn.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_survival_timer.gd res://src/world/levels/world_local.tscn <out_dir> 60

var out_dir: String
var world: WorldLocal
var fails := 0


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	get_tree().create_timer(50.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func _run() -> void:
	await wait(4.0)
	var group := world.get_node("Enemies/SurvivalEnemyGroup") as SurvivalEnemyGroup
	var timer_ui := world.get_node("UI/SurvivalTimer") as SurvivalTimer
	var title := timer_ui.get_node("PanelContainer/VBoxContainer/TitleLabel") as Label
	var time_label := timer_ui.get_node("PanelContainer/VBoxContainer/TimeLabel") as Label
	check("timer hidden before trigger", not timer_ui.visible)

	group.trigger(true)
	await wait(0.6)
	check("timer shown after trigger", timer_ui.visible)
	check("time label counts down", time_label.text.begins_with("0:5") or time_label.text == "1:00", time_label.text)
	await shot("survive.png")

	group._fight_elapsed = group.fight_duration - 5.0
	await wait(0.3)
	check("urgent time shown", time_label.text == "0:05", time_label.text)
	await shot("urgent.png")

	group._fight_elapsed = group.fight_duration + 1.0
	await wait(0.1)
	check("clear phase text", title.text == SurvivalTimer.CLEAR_TEXT and not time_label.visible, title.text)
	await shot("clear.png")

	group.reset()
	await wait(0.6)
	check("timer hidden after reset", not timer_ui.visible)

	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
