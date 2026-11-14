extends Node
## Test driver for world_local_night_rooftops.tscn: Building 1, Metallic Bridge, Building 2,
## footstep surfaces (stone -> metal -> stone), navmesh over bridge & around rooftop props, and screenshots.

const CELL := 2.999
var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(200.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	var prefix := "PASS " if ok else "FAIL "
	var suffix := "" if detail.is_empty() else "  [" + detail + "]"
	print(prefix + label + suffix)
	if not ok:
		fails += 1


func w(cx: float, cz: float, y: float = 0.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func state() -> String:
	if gsm.current == null:
		return ""
	return String(gsm.current.name).to_lower()


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func wait_until(cond: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func shot(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func lowest_player_y() -> float:
	var lowest := INF
	for p in players():
		lowest = minf(lowest, p.global_position.y)
	return lowest


func mean_player_z() -> float:
	var list := players()
	return (list[0].global_position.z + list[1].global_position.z) * 0.5


func visible_players() -> int:
	var cam := get_viewport().get_camera_3d()
	var view_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for p in players():
		var pos: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		if _is_point_on_screen(cam, view_rect, pos):
			seen += 1
	return seen


func _is_point_on_screen(cam: Camera3D, view_rect: Rect2, pos: Vector3) -> bool:
	if cam.is_position_behind(pos):
		return false
	return view_rect.has_point(cam.unproject_position(pos))


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func walk_north_until(target_z: float, max_seconds: float, label: String) -> StringName:
	var list := players()
	var actions := [list[0].action_up, list[1].action_up]
	var lowest := [INF]
	var last_surface: Array[StringName] = [&""]
	var watch := func():
		_sample_walk_frame(lowest, last_surface)
	get_tree().physics_frame.connect(watch)
	for a in actions:
		Input.action_press(a)
	var reached := await wait_until(func(): return mean_player_z() <= target_z, max_seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame
	get_tree().physics_frame.disconnect(watch)
	check(
		"real input: " + label,
		reached and lowest[0] > -1.35 and state() == "playing",
		"mean_z=%.1f (target %.1f), lowest_y=%.2f, surface=%s" % [mean_player_z(), target_z, lowest[0], String(last_surface[0])]
	)
	return last_surface[0]


func _sample_walk_frame(lowest: Array, last_surface: Array[StringName]) -> void:
	for p in players():
		lowest[0] = minf(lowest[0], p.global_position.y)
		var surf := FootstepSurface.under(p as CharacterBody3D)
		if surf != FootstepSurface.UNKNOWN:
			last_surface[0] = surf


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func path_ok(from: Vector3, to: Vector3, should: bool, label: String) -> void:
	var map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var target_nav := NavigationServer3D.map_get_closest_point(map, to)
	var reached := path.size() > 0 and path[path.size() - 1].distance_to(target_nav) < 0.6
	check(label, reached == should, "points=%d" % path.size())


func distance_to_navmesh(centre: Vector3) -> float:
	var map := world.get_world_3d().navigation_map
	var nearest := NavigationServer3D.map_get_closest_point(map, centre)
	return nearest.distance_to(centre)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.2)

	check("save disabled on prototype", world.skip_save)
	check("both carriers stand on Building 1", lowest_player_y() > -1.3, "y=%.2f" % lowest_player_y())
	check("carrying the shuriken launcher", world.get_active_weapon_id() == "shuriken_launcher", world.get_active_weapon_id())
	check("starts on Checkpoint", cp() == "Checkpoint", cp())
	check("spawn view shows both players", visible_players() == 2, "%d/2" % visible_players())

	path_ok(w(-0.5, -1.0), w(-0.5, -13.0), true, "navmesh connects Building 1 across metallic bridge to Building 2")
	var penthouse_gap := distance_to_navmesh(Vector3(-10.5, -0.5, -8.8))
	check("navmesh carves around PenthouseB1 floor", penthouse_gap > 1.0, "gap=%.2f m" % penthouse_gap)

	await shot("01_building1_spawn.png")

	var b1_surface := await walk_north_until(-8.5, 4.0, "walk north across Building 1 toward bridge")
	check("Building 1 footstep surface is stone", b1_surface == FootstepSurface.STONE, String(b1_surface))
	check("bridge approach view shows both players", visible_players() == 2, "%d/2" % visible_players())
	await shot("02_bridge_approach.png")

	var bridge_surface := await walk_north_until(-18.0, 4.0, "walk onto metallic bridge mid-span")
	check("Metallic bridge footstep surface is metal", bridge_surface == FootstepSurface.METAL, String(bridge_surface))
	check("mid-bridge view shows both players", visible_players() == 2, "%d/2" % visible_players())
	await shot("03_on_metallic_bridge.png")

	var b2_surface := await walk_north_until(-29.5, 4.5, "cross metallic bridge onto Building 2")
	await wait(0.3)
	check("Building 2 landing sets Checkpoint2", cp() == "Checkpoint2", cp())
	check("Building 2 footstep surface is stone", b2_surface == FootstepSurface.STONE, String(b2_surface))
	await shot("04_building2_landing.png")

	await walk_north_until(-37.5, 3.5, "walk onto Building 2 helipad")
	check("helipad view shows both players", visible_players() == 2, "%d/2" % visible_players())
	await shot("05_building2_helipad.png")

	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.2)
	protect_players()
	check("respawn stays on Building 2 Checkpoint2", cp() == "Checkpoint2" and lowest_player_y() > -1.3, "cp=%s y=%.2f" % [cp(), lowest_player_y()])

	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
