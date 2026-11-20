extends Node
## Test driver for world_local_world_of_memories.tscn ("World of Memories" opening prototype):
## - Verifies semi-transparent floor & cloud layers render priority order, stone footstep surfaces, navmesh over all
##   three 9 m bridges & around obelisks, real-input walking + Sword dash combat, Section 1 wake & Bridge 1 open,
##   Section 2 Cloud Well landing/close/spawn + mid-round checkpoint restart, Section 3 Sanctum Guardians + Survival
##   convergence wave gated by GroupsDefeatedGate, Bridge 3 to Portal Dais, EndLevelArea -> LevelSucceeded, and
##   captures landmark screenshots across the entire level.

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
	get_tree().create_timer(220.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func _sample_walk_frame(lowest: Array, last_surface: Array[StringName]) -> void:
	for p in players():
		lowest[0] = minf(lowest[0], p.global_position.y)
		var surf := FootstepSurface.under(p as CharacterBody3D)
		if surf != FootstepSurface.UNKNOWN:
			last_surface[0] = surf


func walk_north_until(target_z: float, max_seconds: float, label: String) -> StringName:
	var list := players()
	var actions := [list[0].action_up, list[1].action_up]
	var lowest := [INF]
	var last_surface: Array[StringName] = [&""]
	var watch := func(): _sample_walk_frame(lowest, last_surface)
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


func dash_north_swing() -> void:
	var list := players()
	var move_actions := [list[0].action_up, list[1].action_up]
	var dash_actions := [list[0].action_dash, list[1].action_dash]
	for a in move_actions:
		Input.action_press(a)
	for step in range(3):
		await get_tree().physics_frame
		for a in dash_actions:
			Input.action_press(a)
		await wait(0.14)
		for a in dash_actions:
			Input.action_release(a)
		await wait(0.14)
	for a in move_actions:
		Input.action_release(a)
	await wait(0.15)


func group_enemies(group: String) -> Array:
	return world.get_node("Enemies/%s/InstancedEnemies" % group).get_children().filter(func(c): return c is EnemyLocal)


func survival_enemies() -> Array:
	return world.get_node("Enemies/SurvivalEnemyGroup/Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func total_hp(enemies: Array) -> int:
	var total := 0
	for enemy in enemies:
		var h := enemy.get_node_or_null("Health") as Health
		if h != null and enemy.is_alive():
			total += h.current_hp
	return total


func kill_enemies(enemies: Array) -> void:
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.is_alive():
			Health.apply_damage(enemy, 9999, enemy.global_position)


func bridge_up(index: int) -> bool:
	var shape := world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D/CollisionShape3D" % index) as CollisionShape3D
	return not shape.disabled


func bridge_all_up(number: int) -> bool:
	var first := 1 + (number - 1) * 6
	for i in range(first, first + 6):
		if not bridge_up(i):
			return false
	return true


func bridge_all_down(number: int) -> bool:
	var first := 1 + (number - 1) * 6
	for i in range(first, first + 6):
		if bridge_up(i):
			return false
	return true


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


func check_render_priorities() -> void:
	var floor_grid := world.get_node("Level/NavigationRegion3D/GridMapFloor") as GridMap
	var slab_mesh := floor_grid.mesh_library.get_item_mesh(0)
	var floor_mat := slab_mesh.surface_get_material(0) as ShaderMaterial
	var upper_cloud := world.get_node("Level/MemoriesCloudLayers/UpperWisps") as MeshInstance3D
	var cloud_mat := upper_cloud.material_override as ShaderMaterial
	check(
		"clouds render underneath semi-transparent floor",
		floor_mat != null and cloud_mat != null and cloud_mat.render_priority < floor_mat.render_priority and floor_mat.render_priority < 0,
		"cloud=%d floor=%d" % [cloud_mat.render_priority, floor_mat.render_priority]
	)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.2)

	check("save disabled on prototype", world.skip_save)
	check("both carriers stand on Threshold of Sorrow", lowest_player_y() > -1.3, "y=%.2f" % lowest_player_y())
	check("carrying the sword", world.get_active_weapon_id() == "sword", world.get_active_weapon_id())
	check("starts on Checkpoint", cp() == "Checkpoint", cp())
	check("spawn view shows both players", visible_players() == 2, "%d/2" % visible_players())
	check_render_priorities()

	# ---- Navmesh checks across all 4 platforms, 3 bridges, Cloud Well, and Obelisks. ----
	path_ok(w(0, 1), w(0, -14), true, "navmesh connects Threshold across Bridge 1 to Court of Reflections")
	path_ok(w(0, -14), w(0, -20), true, "navmesh routes around the central Cloud Well")
	path_ok(w(0, -20), w(0, -32), true, "navmesh connects Court across Bridge 2 to Sanctum of Remembrance")
	path_ok(w(0, -35), w(0, -44), true, "navmesh connects Sanctum across Bridge 3 to Portal Dais")
	var obelisk_gap := distance_to_navmesh(w(-4, -2, -0.55))
	check("navmesh carves around Obelisk1", obelisk_gap > 0.65, "gap=%.2f m" % obelisk_gap)
	var well_gap := distance_to_navmesh(w(0, -16.5, -0.55))
	check("Cloud Well pit has no navmesh inside", well_gap > 2.2, "gap=%.2f m" % well_gap)

	await shot("01_arrival_threshold.png")

	# ---- Section 1: Threshold of Sorrow. ----
	check("all three bridges start lowered", bridge_all_down(1) and bridge_all_down(2) and bridge_all_down(3))
	check("Threshold has 5 dormant echoes", group_enemies("ThresholdEchoes").size() == 5 and group_enemies("ThresholdEchoes").all(func(e): return not e.is_offensive))
	check("Court echoes wait unspawned", group_enemies("CourtEchoes").is_empty())

	var start_surface := await walk_north_until(2.2, 4.0, "step into ThresholdTrigger")
	check("Threshold floor footstep surface is stone", start_surface == FootstepSurface.STONE, String(start_surface))
	var woke1 := await wait_until(func(): return group_enemies("ThresholdEchoes").all(func(e): return e.is_offensive), 3.0)
	check("stepping forward wakes ThresholdEchoes", woke1)
	await shot("02_threshold_awakened.png")

	var hp_before := total_hp(group_enemies("ThresholdEchoes"))
	await dash_north_swing()
	var hp_after := total_hp(group_enemies("ThresholdEchoes"))
	check("real Sword dash swing damages awakened echoes", hp_after < hp_before, "hp %d -> %d" % [hp_before, hp_after])

	kill_enemies(group_enemies("ThresholdEchoes"))
	var rose1 := await wait_until(func(): return bridge_all_up(1), 6.0)
	check("clearing ThresholdEchoes raises Bridge 1", rose1 and bridge_all_down(2))
	check("clearing ThresholdEchoes saves Checkpoint2", cp() == "Checkpoint2", cp())
	await wait(0.5)

	# ---- Cross Bridge 1 into Section 2: Court of Reflections. ----
	var bridge1_surface := await walk_north_until(-21.0, 5.5, "walk onto Bridge 1 mid-span")
	check("Bridge 1 footstep surface is stone", bridge1_surface == FootstepSurface.STONE, String(bridge1_surface))
	check("Bridge 1 view shows both players", visible_players() == 2, "%d/2" % visible_players())
	await shot("03_memory_bridge1.png")

	await walk_north_until(-33.5, 4.5, "cross Bridge 1 onto Court of Reflections")
	var closed1 := await wait_until(func(): return bridge_all_down(1), 6.5)
	var spawned2 := await wait_until(func(): return group_enemies("CourtEchoes").size() == 8 and group_enemies("CourtEchoes").all(func(e): return e.is_offensive), 4.0)
	check("landing on Court closes Bridge 1", closed1)
	check("and manifests all 8 CourtEchoes awake", spawned2, "%d" % group_enemies("CourtEchoes").size())
	await wait(0.8)
	await shot("04_court_cloud_well.png")

	# ---- Mid-round death/restart check on Court of Reflections -> restores Checkpoint2 & Bridge 1. ----
	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("mid-round restart restores Checkpoint2 with Bridge 1 up", cp() == "Checkpoint2" and bridge_all_up(1) and lowest_player_y() > -1.3, cp())
	check("CourtEchoes unspawned again after restart", group_enemies("CourtEchoes").filter(func(e): return e.is_alive()).is_empty())

	await walk_north_until(-33.5, 6.0, "re-cross Bridge 1 onto Court after restart")
	var restarted2 := await wait_until(func(): return group_enemies("CourtEchoes").filter(func(e): return e.is_alive() and e.is_offensive).size() == 8 and bridge_all_down(1), 8.0)
	check("landing again re-triggers CourtEchoes and closes Bridge 1", restarted2)

	# Walk around the west side of the Cloud Well so we frame the Cloud Well & north Court mages.
	kill_enemies(group_enemies("CourtEchoes"))
	var rose2 := await wait_until(func(): return bridge_all_up(2), 6.0)
	check("clearing CourtEchoes raises Bridge 2 and saves Checkpoint3", rose2 and cp() == "Checkpoint3", cp())

	# ---- Cross Bridge 2 into Section 3: Sanctum of Remembrance. ----
	var survival := world.get_node("Enemies/SurvivalEnemyGroup") as SurvivalEnemyGroup
	check("authored survival duration is 28 s", is_equal_approx(survival.fight_duration, 28.0), str(survival.fight_duration))
	survival.fight_duration = 5.5

	# Teleport cleanly to Checkpoint3 just south of Bridge 2 and walk across Bridge 2 by real input.
	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	survival = world.get_node("Enemies/SurvivalEnemyGroup") as SurvivalEnemyGroup
	survival.fight_duration = 5.5

	await walk_north_until(-84.5, 6.5, "walk from Checkpoint3 across Bridge 2 into SanctumLanding")
	var closed2 := await wait_until(func(): return bridge_all_down(2), 6.5)
	var guardians_awake := await wait_until(func(): return group_enemies("SanctumGuardians").size() == 4 and group_enemies("SanctumGuardians").all(func(e): return e.is_offensive), 4.0)
	var wave_spawned := await wait_until(func(): return survival_enemies().size() > 0, 4.0)
	check("landing on Sanctum closes Bridge 2", closed2)
	check("SanctumGuardians (2 Mechs + 2 Robots) spawn awake", guardians_awake, "%d" % group_enemies("SanctumGuardians").size())
	check("SurvivalEnemyGroup spawns convergence wave", wave_spawned, "%d" % survival_enemies().size())
	await wait(0.8)
	await shot("05_sanctum_convergence.png")

	# Defeating only SanctumGuardians must NOT open Bridge 3 while SurvivalEnemyGroup is still running!
	kill_enemies(group_enemies("SanctumGuardians"))
	await wait(0.6)
	check("GroupsDefeatedGate waits for SurvivalEnemyGroup too", bridge_all_down(3) and cp() == "Checkpoint3", cp())

	var clear_deadline := Time.get_ticks_msec() + 18000
	while Time.get_ticks_msec() < clear_deadline and not survival.signal_emitted:
		kill_enemies(survival_enemies())
		await wait(0.4)

	var rose3 := await wait_until(func(): return bridge_all_up(3) and cp() == "Checkpoint4", 8.0)
	check("clearing both SanctumGuardians and SurvivalEnemyGroup saves Checkpoint4 and raises Bridge 3", rose3, cp())

	# ---- Cross Bridge 3 onto Portal Dais -> EndLevelArea -> LevelSucceeded. ----
	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("Checkpoint4 places carriers before Bridge 3 with Bridge 3 open", cp() == "Checkpoint4" and bridge_all_up(3))

	await walk_north_until(-127.0, 5.5, "walk across Bridge 3 onto Portal Dais")
	await shot("06_portal_dais.png")

	var list := players()
	for a in [list[0].action_up, list[1].action_up]:
		Input.action_press(a)
	var finished := await wait_until(func(): return state() == "levelfinished", 5.0)
	for a in [list[0].action_up, list[1].action_up]:
		Input.action_release(a)
	check("stepping into EndLevelArea on Portal Dais finishes the level", finished, state())

	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
