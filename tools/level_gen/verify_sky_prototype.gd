extends Node
## Test driver for world_local_sky.tscn. Copy it for a new level: keep the helpers, rewrite _run().
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
	get_tree().create_timer(190.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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
	place(pos + Vector3(0, 0, 2.6), pos)


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
	check(label, players_seen == 2 and near_seen == near.size(), "players %d/2, enemies within %.0f m %d/%d, camera y=%.1f" % [players_seen, reach, near_seen, near.size(), get_viewport().get_camera_3d().global_position.y])


func check_mages_in_range(label: String) -> void:
	var in_range := group_enemies("Enemies/EnemyGroup3").filter(_can_cast_at_a_player)
	check(label, in_range.size() > 0 and visible_count(in_range) == in_range.size(), "%d/%d in range on screen" % [visible_count(in_range), in_range.size()])


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


func clear_and_wait(group: String, expected_cp: String, bridge_index: int) -> void:
	kill_group(group)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check(group.get_file() + " cleared sets " + expected_cp, cp() == expected_cp, cp())
	check("bridge platform %d raised" % bridge_index, bridge_y(bridge_index) > -2.0, "y=%.2f" % bridge_y(bridge_index))
	check("camera focus released", focal_count() == 0, str(focal_count()))


func fall_off_edge() -> void:
	var list := players()
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	Input.action_press(list[0].action_right)
	Input.action_press(list[1].action_right)
	var over_edge: bool = await wait_until(func(): return lowest[0] < -4.0, 6.0)
	await shot("sky_falling.png")
	var died: bool = await wait_until(func(): return state() == "gameoverlost", 6.0)
	Input.action_release(list[0].action_right)
	Input.action_release(list[1].action_right)
	get_tree().physics_frame.disconnect(watch)
	check("real input: walking off the edge falls and ends in game over", over_edge and died, "lowest y=%.1f, state=%s" % [lowest[0], state()])
	await wait(1.0)
	await shot("sky_died.png")
	var back: bool = await wait_until(func(): return state() == "playing", 12.0)
	await wait(1.0)
	var safe: bool = list[0].global_position.y > -1.3 and list[1].global_position.y > -1.3
	check("respawn after a fall returns to the island", back and safe, "state=%s y=%.2f" % [state(), list[0].global_position.y])


func platform_state(index: int) -> String:
	var body := world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D" % index)
	var seen: bool = body.get_node("Visual").is_visible_in_tree()
	var solid: bool = not body.get_node("CollisionShape3D").disabled
	return "visible=%s solid=%s" % [seen, solid]


## Steps into the gap, then lets go of the controls: a hidden platform must not catch the player.
func fall_into_gap() -> void:
	var list := players()
	var cx: float = w(0, -5).x
	place(Vector3(cx, 0, w(0, -5).z + 2.6), Vector3(cx, 0, w(0, -5).z))
	await wait(0.5)
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	await wait_until(func(): return list[1].global_position.y < -1.4, 3.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	var died: bool = await wait_until(func(): return state() == "gameoverlost", 5.0)
	check("real input: stepping into a closed bridge's gap is a fall, nothing catches you", died, "state=%s y=%.1f" % [state(), list[1].global_position.y])
	await wait_until(func(): return state() == "playing", 12.0)
	await wait(1.0)


func cross_bridge(label: String, from_cell: int, min_moved: float) -> void:
	var list := players()
	var cx: float = w(0, 0).x
	var z: float = w(0, from_cell).z
	place(Vector3(cx, 0, z + 2.6), Vector3(cx, 0, z))
	await wait(0.5)
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	var z0: float = list[0].global_position.z
	await hold([list[0].action_up, list[1].action_up], 2.2)
	get_tree().physics_frame.disconnect(watch)
	var moved: float = z0 - list[0].global_position.z
	check("real input: cross " + label, moved >= min_moved and lowest[0] > -1.3 and state() == "playing", "moved %.1f, lowest y=%.2f, state=%s" % [moved, lowest[0], state()])


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(2.0)
	await shot("sky_start.png")
	print("INFO fps at start: ", Engine.get_frames_per_second())
	check("cloud layers present and no water", world.has_node("Level/CloudLayers") and not world.has_node("Level/Water"))
	check("distant islands present", world.get_node("Level/DistantIslands").get_child_count() == 7)
	var island := world.get_node("Level/DistantIslands/IslandB") as Node3D
	var island_y := island.position.y
	await wait(1.0)
	check("distant island bobs", absf(island.position.y - island_y) > 0.001, "moved %.3f" % absf(island.position.y - island_y))

	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 170.0
	top.far = 500.0
	top.position = Vector3(1.5, 200, -50)
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot("sky_overhead.png")
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()
	await wait(0.5)

	await fall_off_edge()
	check("lowered bridge is hidden and not solid", platform_state(1) == "visible=false solid=false", platform_state(1))
	await fall_into_gap()
	protect_players()

	path_ok(w(0, -9), w(0, -17), true, "nav: ring connects around the pit")
	path_ok(w(0, -22), w(0, -29), true, "nav: causeway connects")
	path_ok(w(0, -22), w(-7, -26), false, "nav: mage perch is unreachable")
	path_ok(w(0, 0), w(0, -9), false, "nav: start separate from ring")

	# Firing line: targets on screen, then a real rocket.
	move_players(w(0, -4))
	await wait(2.5)
	check("firing line: focal points active", focal_count() == 4, str(focal_count()))
	check_view("firing line view", group_enemies("Enemies/EnemyGroup"), 100.0)
	await shot("sky_firing_line.png")
	var before := group_enemies("Enemies/EnemyGroup").size()
	var specifics := world.get_active_weapon().get_node("WeaponSpecifics") as BazookaSpecifics
	specifics._request_fire_bullet()
	var hit: bool = await wait_until(func(): return group_enemies("Enemies/EnemyGroup").size() < before, 10.0)
	await wait(0.5)
	var killed: int = before - group_enemies("Enemies/EnemyGroup").size()
	check("real rocket kills a whole pack across the gap", hit and killed == 3, "killed %d of a pack of 3" % killed)
	kill_group("Enemies/EnemyGroup")
	await wait(1.3)
	await shot("sky_bridge_rising.png")
	await clear_and_wait("Enemies/EnemyGroup", "Checkpoint2", 1)
	check("raised bridge is visible and solid", platform_state(1) == "visible=true solid=true", platform_state(1))
	await shot("sky_bridge_raised.png")
	await cross_bridge("the raised sky bridge", -5, 8.0)

	# Ring.
	var g2 := group_enemies("Enemies/EnemyGroup2")
	move_players(w(0, -10))
	await wait(3.0)
	check("ring trigger starts the fight", g2[0].is_offensive)
	var closed: bool = await wait_until(func(): return platform_state(1) == "visible=false solid=false", 6.0)
	check("bridge disappears again when it closes", closed, platform_state(1))
	check("ring: focal points active", focal_count() == 4, str(focal_count()))
	check_view("ring entry view", group_enemies("Enemies/EnemyGroup2"), 100.0)
	await shot("sky_ring.png")
	await clear_and_wait("Enemies/EnemyGroup2", "Checkpoint3", 3)
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("respawn keeps the opened bridge raised and the closed one hidden", platform_state(3) == "visible=true solid=true" and platform_state(1) == "visible=false solid=false", "bridge 2: %s, bridge 1: %s" % [platform_state(3), platform_state(1)])

	# Causeway.
	move_players(w(0, -23))
	await wait(3.0)
	check("causeway trigger starts group 3", group_enemies("Enemies/EnemyGroup3").all(func(e): return e.is_offensive))
	check("causeway: focal points active", focal_count() == 4, str(focal_count()))
	check_view("causeway view", group_enemies("Enemies/EnemyGroup3"))
	check_mages_in_range("causeway start: mages in range on screen")
	await wait(3.0)
	var fired: int = world.get_children().filter(func(c): return c is Fireball).size()
	print("INFO fireballs in flight on the causeway: ", fired)
	await shot("sky_causeway.png")
	move_players(w(0, -28))
	await wait(2.0)
	check_mages_in_range("causeway end: mages in range on screen")
	print("INFO fps in the busiest view: ", Engine.get_frames_per_second())
	check("no death on the causeway", state() == "playing", state())
	await clear_and_wait("Enemies/EnemyGroup3", "Checkpoint4", 5)
	await cross_bridge("the last sky bridge", -30, 8.0)

	move_players(w(0, -36))
	await wait(1.5)
	check("end area finishes the level", state() == "levelfinished", state())
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
