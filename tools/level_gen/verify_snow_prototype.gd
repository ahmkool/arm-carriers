extends Node
## Test driver for world_local_snow.tscn. Copy it for a new level: keep the helpers, rewrite _run().
## Run through godot.sh, see docs/level-creation-for-agents.md.
## Uses real input where it matters. Save tracking is disabled, so save.json stays untouched.

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
	get_tree().create_timer(400.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func w(cx: int, cz: int, y: float = 0.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func state() -> String:
	return "" if gsm.current == null else String(gsm.current.name).to_lower()


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


func place(a: Vector3, b: Vector3) -> void:
	var list := players()
	list[0].velocity = Vector3.ZERO
	list[1].velocity = Vector3.ZERO
	list[0].global_position = a
	list[1].global_position = b


func move_players(pos: Vector3) -> void:
	place(pos + Vector3(3, 0, 0), pos + Vector3(-3, 0, 0))


func gap() -> float:
	var l := players()
	return Vector2(l[0].global_position.x - l[1].global_position.x, l[0].global_position.z - l[1].global_position.z).length()


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func group_enemies(path: String) -> Array:
	return world.get_node(path).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func kill_group(path: String) -> void:
	for e in group_enemies(path):
		Health.apply_damage(e, 9999, e.global_position)


func visible_count(enemies: Array) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for e in enemies:
		var pos: Vector3 = e.global_position + Vector3(0, 1, 0)
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen


func check_all_visible(label: String, enemies: Array) -> void:
	var seen := visible_count(enemies)
	check(label, enemies.size() > 0 and seen == enemies.size(), "%d/%d, camera y=%.1f" % [seen, enemies.size(), get_viewport().get_camera_3d().global_position.y])


func _player_distance(enemy: EnemyLocal) -> float:
	var nearest := INF
	for p in players():
		var d: Vector3 = p.global_position - enemy.global_position
		nearest = minf(nearest, Vector2(d.x, d.z).length())
	return nearest


func _can_cast_at_a_player(enemy: EnemyLocal) -> bool:
	if not enemy.has_node("MageBehavior"):
		return false
	return _player_distance(enemy) <= enemy.get_node("MageBehavior").cast_max_distance


## Both players on screen, and every living enemy within reach of them too.
func check_view(label: String, enemies: Array, reach: float = 14.0) -> void:
	var players_seen := visible_count(players())
	var near := enemies.filter(func(e): return is_instance_valid(e) and e.is_alive() and _player_distance(e) <= reach)
	var near_seen := visible_count(near)
	var detail := "players %d/2, enemies within %.0f m %d/%d, camera y=%.1f" % [players_seen, reach, near_seen, near.size(), get_viewport().get_camera_3d().global_position.y]
	# At normal zoom (no framing), enemies at the edge of the view may be off screen: only the players must show.
	if focal_count() == 0:
		check(label + " (normal zoom: players on screen)", players_seen == 2, detail)
		return
	check(label, players_seen == 2 and near_seen == near.size(), detail)


func check_mages_in_range(label: String) -> void:
	var in_range := group_enemies("Enemies/EnemyGroup4").filter(_can_cast_at_a_player)
	var detail := "%d/%d in range on screen" % [visible_count(in_range), in_range.size()]
	# At normal zoom, finding a mage that fires from off screen is part of the challenge: it only has to be a threat.
	if focal_count() == 0:
		check(label.replace("on screen", "(off screen allowed)"), in_range.size() > 0, detail)
		return
	check(label, in_range.size() > 0 and visible_count(in_range) == in_range.size(), detail)


func bridge_y(index: int) -> float:
	return (world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D" % index) as Node3D).global_position.y


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


func path_ok(from: Vector3, to: Vector3, should: bool, label: String) -> void:
	var map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var reached := path.size() > 0 and path[path.size() - 1].distance_to(NavigationServer3D.map_get_closest_point(map, to)) < 0.6
	check(label, reached == should, "points=%d" % path.size())


func walk(label: String, seconds: float, min_moved: float) -> void:
	var list := players()
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	var a0: float = list[0].global_position.z
	var b0: float = list[1].global_position.z
	await hold([list[0].action_up, list[1].action_up], seconds)
	get_tree().physics_frame.disconnect(watch)
	var ma: float = a0 - list[0].global_position.z
	var mb: float = b0 - list[1].global_position.z
	check("real input: " + label, ma > min_moved and mb > min_moved and lowest[0] > -1.3 and state() == "playing", "moved %.1f/%.1f, lowest y=%.2f, gap=%.1f, state=%s" % [ma, mb, lowest[0], gap(), state()])

func strike_test(enemy: EnemyLocal, side_action: String, side: Vector3, label: String) -> void:
	var sword := world.get_active_weapon()
	var blade_mid: Vector3 = (sword.get_node("WeaponSpecifics/HitArea/CollisionShape3D") as Node3D).global_position
	var spot: Vector3 = blade_mid + side * 2.0
	spot.y = enemy.global_position.y
	enemy.global_position = spot
	await get_tree().physics_frame
	var list := players()
	var acts: Array = [list[0].get(side_action), list[1].get(side_action)]
	for attempt in 3:
		for a in acts:
			Input.action_press(a)
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_press(list[0].action_dash)
		Input.action_press(list[1].action_dash)
		await wait(0.2)
		Input.action_release(list[0].action_dash)
		Input.action_release(list[1].action_dash)
		for a in acts:
			Input.action_release(a)
		await wait(0.6)
		if not enemy.is_alive():
			break
	check(label, not enemy.is_alive())


func clear_and_wait(group: String, expected_cp: String, bridge_index: int) -> void:
	kill_group(group)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check(group.get_file() + " cleared sets " + expected_cp, cp() == expected_cp, cp())
	check("bridge platform %d raised" % bridge_index, bridge_y(bridge_index) > -2.0, "y=%.2f" % bridge_y(bridge_index))


# ---- Snow helpers. ----

func centre(cx: int, cz: int) -> Vector3:
	var p := w(cx, cz)
	p.x = w(0, 0).x if cx == 0 else p.x
	return p


## Real input: walk in a direction for `seconds`, release, and measure how far the front carrier keeps going.
func slide_after_release(label: String, start: Vector3, action: String, seconds: float) -> Array:
	var list := players()
	move_players(start)
	await wait(0.8)
	var acts: Array = [list[0].get(action), list[1].get(action)]
	for a in acts:
		Input.action_press(a)
	var t0: Vector3 = list[1].global_position
	await wait(0.3)
	var early: float = Vector2(list[1].global_position.x - t0.x, list[1].global_position.z - t0.z).length()
	await wait(seconds - 0.3)
	for a in acts:
		Input.action_release(a)
	await get_tree().physics_frame
	var released: Vector3 = list[1].global_position
	await wait(2.0)
	var slid: float = Vector2(list[1].global_position.x - released.x, list[1].global_position.z - released.z).length()
	print("INFO %s: moved %.2f m in the first 0.3 s, slid %.2f m after letting go, on ice=%s" % [label, early, slid, list[1].is_on_ice()])
	return [early, slid]


func check_ice_feel() -> void:
	var snow: Array = await slide_after_release("snow", w(-5, -16) + Vector3(0, 0, 3), "action_up", 1.0)
	var ice: Array = await slide_after_release("ice", w(1, -13) + Vector3(0, 0, -1), "action_left", 1.0)
	check("real input: on snow the carriers stop at once", snow[1] < 0.3, "slid %.2f m" % snow[1])
	check("real input: on ice they keep sliding after letting go", ice[1] > 1.2 and ice[1] < 4.5, "slid %.2f m" % ice[1])
	check("real input: on ice they get going more slowly", ice[0] < snow[0] * 0.8, "%.2f m vs %.2f m in 0.3 s" % [ice[0], snow[0]])


## The lake's ice runs to its east cliff: let go too late and the slide carries you into the sea.
func check_slide_into_sea() -> void:
	var list := players()
	move_players(w(4, -15))
	await wait(0.8)
	Input.action_press(list[0].action_right)
	Input.action_press(list[1].action_right)
	await wait_until(func(): return list[1].global_position.x > w(6, -15).x, 4.0)
	Input.action_release(list[0].action_right)
	Input.action_release(list[1].action_right)
	var died: bool = await wait_until(func(): return state() == "gameoverlost", 5.0)
	check("real input: letting go at the ice edge still slides you into the sea", died, "state=%s x=%.1f" % [state(), list[1].global_position.x])
	await shot("snow_slid_into_sea.png")
	await wait_until(func(): return state() == "playing", 15.0)
	await wait(1.0)


func check_props_block() -> void:
	var map := world.get_world_3d().navigation_map
	var on_tree := NavigationServer3D.map_get_closest_point(map, w(-5, -11))
	check("nav: a snowy pine is solid, enemies path around it", on_tree.distance_to(Vector3(w(-5, -11).x, on_tree.y, w(-5, -11).z)) > 0.8, "closest nav point %.2f m from its centre" % on_tree.distance_to(Vector3(w(-5, -11).x, on_tree.y, w(-5, -11).z)))


func overhead() -> void:
	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 150.0
	top.far = 400.0
	top.position = Vector3(1.5, 150, -55)
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot("snow_overhead.png")
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	await shot("snow_start.png")
	print("INFO fps at start: ", Engine.get_frames_per_second())
	var orcs := group_enemies("Enemies/EnemyGroup")
	check("enemies are orcs", orcs.size() == 5 and orcs.all(func(e): return e.has_node("Orc")), str(orcs.size()))
	var skin: Mesh = (orcs[0].get_node("Orc/Rig_Medium/Skeleton3D/OrcRaider_Head") as MeshInstance3D).mesh
	check("orcs wear the blue texture", skin.surface_get_material(0).resource_path.ends_with("orc_raider_blue.tres"), str(skin.surface_get_material(0).resource_path))
	check_view("spawn view", orcs, 14.0)
	await overhead()
	path_ok(w(-6, -12), w(6, -20), true, "nav: the lake connects, across and around the ice")
	path_ok(w(0, -27), w(0, -36), true, "nav: the frozen river can be crossed")
	path_ok(w(0, 0), w(0, -12), false, "nav: shore separate from the lake")
	check_props_block()

	# A real sword strike on an orc.
	protect_players()
	await wait_until(func(): return not orcs[1].enemy_state_machine.is_in_state("spawning"), 5.0)
	# Strike from the spawn: teleporting the carriers first can leave the sword lying sideways.
	await strike_test(orcs[1], "action_right", Vector3.RIGHT, "real dash: the blade kills an orc")
	await shot("snow_strike.png")
	await clear_and_wait("Enemies/EnemyGroup", "Checkpoint2", 1)

	# Lake. The ice tests run first, past the trigger, while the orcs still wait.
	var g2 := group_enemies("Enemies/EnemyGroup2")
	check("lake orcs wait", g2.size() == 10 and not g2[0].is_offensive, str(g2.size()))
	await check_ice_feel()
	await check_slide_into_sea()
	protect_players()
	g2 = group_enemies("Enemies/EnemyGroup2")
	check("the lake orcs never woke during the ice tests", g2.size() == 10 and g2.all(func(e): return not e.is_offensive), str(g2.size()))
	move_players(w(0, -11))
	await wait(3.0)
	check("lake trigger starts the fight", g2[0].is_offensive)
	check("lake: normal zoom, every orc can be walked to", focal_count() == 0, str(focal_count()))
	await shot("snow_lake.png")
	await clear_and_wait("Enemies/EnemyGroup2", "Checkpoint3", 5)

	# River.
	move_players(w(0, -27))
	await wait(3.0)
	var g3 := group_enemies("Enemies/EnemyGroup3")
	check("river trigger starts the fight", g3.size() == 7 and g3[0].is_offensive, str(g3.size()))
	for spot in [[0, -28, "near bank"], [0, -31, "on the ice"], [0, -35, "far bank"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.3)
		check_view("river %s view" % spot[2], group_enemies("Enemies/EnemyGroup3"))
	await shot("snow_river.png")
	print("INFO fps on the river: ", Engine.get_frames_per_second())
	await clear_and_wait("Enemies/EnemyGroup3", "Checkpoint4", 9)

	# A mid-level respawn.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("respawn keeps bridge 3 up and bridge 2 down", bridge_y(9) > -2.0 and bridge_y(5) < -2.0, "%.2f / %.2f" % [bridge_y(9), bridge_y(5)])
	check("respawn leaves the river clear", group_enemies("Enemies/EnemyGroup3").is_empty())
	move_players(w(0, -38))
	await wait(0.5)
	await walk("over the last bridge", 1.6, 4.0)
	move_players(w(0, -44))
	await wait(1.5)
	check("end area finishes the level", state() == "levelfinished", state())
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
