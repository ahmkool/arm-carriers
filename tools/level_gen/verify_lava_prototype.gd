extends Node
## Test driver for world_local_lava.tscn. Copy it for a new level: keep the helpers, rewrite _run().
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
	get_tree().create_timer(420.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func clear_and_wait(group: String, expected_cp: String, bridge_index: int) -> void:
	kill_group(group)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check(group.get_file() + " cleared sets " + expected_cp, cp() == expected_cp, cp())
	check("bridge platform %d raised" % bridge_index, bridge_y(bridge_index) > -2.0, "y=%.2f" % bridge_y(bridge_index))


# ---- Lava helpers. ----

var burns: Array = []  # carriers a vent reached, recorded even while they are invulnerable


func vents() -> Array:
	return world.get_node("Level/Vents").get_children()


func vent_at(cx: int, cz: int) -> LavaVent:
	for vent in vents():
		if vent.global_position.distance_to(w(cx, cz, -1.0)) < 0.5:
			return vent
	return null


func watch_burns() -> void:
	for vent in vents():
		vent.burned.connect(func(body):
			if body is PlayerLocal:
				burns.append(body.name)
		)


## Waits for the vent's next quiet moment, so a test doesn't start in the middle of an eruption.
func wait_for_vent_clock(vent: LavaVent, clock: float) -> void:
	await wait_until(func(): return absf(vent._elapsed - clock) < 0.05, 6.0)


func wait_for_eruption(vent: LavaVent) -> void:
	await wait_until(func(): return not vent.is_erupting(), 6.0)
	await wait_until(func(): return vent.is_erupting(), 6.0)


## Carriers side by side around a point, spaced as the saw holds them.
func place_side_by_side(center: Vector3) -> void:
	place(center + Vector3(3, 0, 0), center + Vector3(-3, 0, 0))


func check_vent_timing() -> void:
	var vent := vent_at(-3, -12)
	await wait_for_eruption(vent)
	var started := Time.get_ticks_msec()
	await wait_until(func(): return not vent.is_erupting(), 3.0)
	var lasted := (Time.get_ticks_msec() - started) / 1000.0
	await wait_until(func(): return vent.is_erupting(), 6.0)
	var period := (Time.get_ticks_msec() - started) / 1000.0
	check("vent erupts for about 0.9 s", absf(lasted - 0.9) < 0.2, "%.2f s" % lasted)
	check("vent repeats about every 4 s", absf(period - 4.0) < 0.3, "%.2f s" % period)


func check_vent_kills() -> void:
	var vent := vent_at(3, -12)
	await wait_for_vent_clock(vent, 2.5)
	var center := vent.global_position
	center.y = 0.0
	place(center, center + Vector3(-6, 0, 0))
	await wait_for_eruption(vent)
	var died: bool = await wait_until(func(): return state() == "gameoverlost", 2.0)
	check("standing on a vent when it erupts is a game over", died, state())
	await shot("lava_vent_death.png")
	await wait_until(func(): return state() == "playing", 15.0)
	await wait(1.0)


func check_vent_edge() -> void:
	var vent := vent_at(3, -12)
	await wait_for_vent_clock(vent, 2.5)
	var center := vent.global_position
	center.y = 0.0
	burns.clear()
	place(center + Vector3(vent.radius + 0.35, 0, 0), center + Vector3(vent.radius + 0.35 - 6.0, 0, 0))
	await wait_for_eruption(vent)
	await shot("lava_vent_edge.png")
	await wait_until(func(): return not vent.is_erupting(), 2.0)
	check("just outside the marked circle is safe", burns.is_empty(), str(burns))


func check_straddle() -> void:
	var vent := vent_at(0, -15)
	await wait_for_vent_clock(vent, 2.5)
	var center := vent.global_position
	center.y = 0.0
	burns.clear()
	place_side_by_side(center)
	await wait_for_eruption(vent)
	await wait(0.25)
	await shot("lava_straddle.png")
	await wait_until(func(): return not vent.is_erupting(), 2.0)
	check("carriers can straddle an erupting vent", burns.is_empty(), str(burns))


func check_enemy_burns() -> void:
	var vent := vent_at(0, -21)
	var guards := group_enemies("Enemies/EnemyGroup2")
	var guard: EnemyLocal = guards[1]
	var center := vent.global_position
	center.y = 0.0
	await wait_for_vent_clock(vent, 2.5)
	guard.global_position = center
	await wait_for_eruption(vent)
	var burned: bool = await wait_until(func(): return not guard.is_alive(), 1.5)
	check("an enemy on a vent burns", burned)


## Walks straight across the field from several moments in the vents' cycle. A rough measure, not a difficulty rating.
func sweep_straight_walk() -> void:
	var clock_vent := vent_at(0, -15)
	var clean := 0
	var list := players()
	for start in range(0, 8):
		await wait_for_vent_clock(clock_vent, start * 0.5)
		var center := w(0, -10)
		center.x = 1.5
		burns.clear()
		place_side_by_side(center)
		await wait(0.1)
		var deadline_z := w(0, -23).z
		Input.action_press(list[0].action_up)
		Input.action_press(list[1].action_up)
		await wait_until(func(): return list[0].global_position.z < deadline_z, 14.0)
		Input.action_release(list[0].action_up)
		Input.action_release(list[1].action_up)
		print("INFO straight walk from clock %.1f s: burned %d times" % [start * 0.5, burns.size()])
		if burns.is_empty():
			clean += 1
	print("INFO straight walks across the field untouched: %d of 8" % clean)
	check("the field can be crossed untouched by walking straight, at some timing", clean > 0, "%d of 8" % clean)
	check("the field isn't free: some timings get burned", clean < 8, "%d of 8" % clean)


func check_gap_fall() -> void:
	var list := players()
	var center := w(0, -5)
	center.x = 1.5
	place_side_by_side(center)
	await wait(0.4)
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var died: bool = await wait_until(func(): return state() == "gameoverlost", 6.0)
	var low: float = minf(list[0].global_position.y, list[1].global_position.y)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	check("real input: walking off the edge into the lava is a game over", died, state())
	check("the raised-to-be bridge doesn't catch a faller; death at the surface", low < -3.8 and low > -6.5, "y=%.2f" % low)
	await shot("lava_fall.png")
	await wait_until(func(): return state() == "playing", 15.0)
	await wait(1.0)


func overhead() -> void:
	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 230.0
	top.far = 400.0
	top.position = Vector3(1.5, 150, -96)
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot("lava_overhead.png")
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	watch_burns()
	await wait(1.0)
	var box := world.get_node("UI/InfoMessageBottomRight") as Control
	check("hint shows at launch", box.is_visible_in_tree() and box.modulate.a > 0.1)
	await shot("lava_start.png")
	print("INFO fps at start: ", Engine.get_frames_per_second())
	var list := players()
	check("carriers spawn side by side", absf(list[0].global_position.z - list[1].global_position.z) < 1.0 and gap() >= 5.4 and gap() <= 7.1, "gap=%.1f" % gap())
	check_view("spawn view", group_enemies("Enemies/EnemyGroup"), 100.0)
	await overhead()

	path_ok(w(0, -10), w(0, -23), true, "nav: vent field connects")
	path_ok(w(0, -28), w(0, -41), true, "nav: caldera connects around the pit")
	path_ok(w(-7, -46), w(7, -59), true, "nav: forge connects around the pools")
	path_ok(w(0, 0), w(0, -10), false, "nav: yard separate from field")

	# Lava kills, with real walking.
	await check_gap_fall()
	list = players()

	# A real kill, then the bridge.
	var target: EnemyLocal = world.get_node("Enemies/EnemyGroup/InstancedEnemies/EnemyLocal1")
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var killed: bool = await wait_until(func(): return not target.is_alive(), 5.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	check("real input: walking the saw into a skeleton kills it", killed)
	await wait(0.3)
	await shot("lava_kill.png")
	kill_group("Enemies/EnemyGroup")
	await wait(1.2)
	await shot("lava_bridge_rising.png")
	await clear_and_wait("Enemies/EnemyGroup", "Checkpoint2", 1)
	var yard_edge := w(0, -5)
	yard_edge.x = 1.5
	place_side_by_side(yard_edge)
	await wait(0.4)
	await walk("across the rising slabs", 2.0, 5.0)

	# Vents.
	await check_vent_timing()
	await wait_until(func(): return vent_at(-3, -12).is_erupting(), 6.0)
	await shot("lava_first_vent.png")
	await check_vent_kills()
	# The death respawns them at the yard, and the bridge stays open.
	check("respawn keeps bridge 1 up", bridge_y(1) > -2.0, "y=%.2f" % bridge_y(1))
	protect_players()
	await check_vent_edge()
	await check_straddle()
	await check_enemy_burns()
	var center := w(0, -13)
	center.x = 1.5
	place_side_by_side(center)
	await wait(1.5)
	var close_vents := vents().filter(func(v): return absf(v.global_position.z - center.z) < 8.0 and absf(v.global_position.x - center.x) < 12.0)
	check("field: nearby vents on screen", close_vents.size() > 0 and visible_count(close_vents) == close_vents.size(), "%d/%d" % [visible_count(close_vents), close_vents.size()])
	await shot("lava_field.png")

	# The trigger past the third row.
	var g2 := group_enemies("Enemies/EnemyGroup2")
	check("guards wait", g2.size() == 6 and not g2[0].is_offensive, str(g2.size()))
	var trigger_spot := w(0, -19)
	trigger_spot.x = 1.5
	place_side_by_side(trigger_spot)
	await wait(3.0)
	check("field trigger sends the guards", is_instance_valid(g2[0]) and g2[0].is_offensive)
	var sank: bool = await wait_until(func(): return bridge_y(1) < -2.0, 6.0)
	check("bridge 1 sinks behind the carriers", sank, "y=%.2f" % bridge_y(1))
	await shot("lava_guards.png")
	await clear_and_wait("Enemies/EnemyGroup2", "Checkpoint3", 7)

	await sweep_straight_walk()

	# Twin rails over the lava: one carrier on each, the saw over nothing.
	var rail_start := w(0, -24)
	rail_start.x = 1.5
	place_side_by_side(rail_start)
	await wait(0.6)
	await walk("along the twin rails", 1.0, 3.0)
	await shot("lava_rails.png")
	await walk("off the far end of the twin rails", 1.2, 4.0)

	# Caldera.
	var caldera := w(0, -29)
	caldera.x = 1.5
	place_side_by_side(caldera)
	await wait(3.0)
	var g3 := group_enemies("Enemies/EnemyGroup3")
	check("caldera trigger starts the fight", g3[0].is_offensive, str(g3.size()))
	var sank2: bool = await wait_until(func(): return bridge_y(7) < -2.0, 6.0)
	check("bridge 2 sinks behind", sank2, "y=%.2f" % bridge_y(7))
	check("caldera: normal zoom, since every enemy here can be walked to", focal_count() == 0, str(focal_count()))
	check_view("caldera view", group_enemies("Enemies/EnemyGroup3"))
	await shot("lava_caldera.png")
	for spot in [[-6, -30, "south-west"], [6, -30, "south-east"], [-6, -39, "north-west"], [6, -39, "north-east"]]:
		place_side_by_side(w(spot[0], spot[1]))
		await wait(1.3)
		check_view("caldera %s view" % spot[2], group_enemies("Enemies/EnemyGroup3"))
	print("INFO fps in the caldera: ", Engine.get_frames_per_second())
	await clear_and_wait("Enemies/EnemyGroup3", "Checkpoint4", 11)

	# A mid-level respawn.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("respawn keeps bridge 3 up and bridge 2 down", bridge_y(11) > -2.0 and bridge_y(7) < -2.0, "%.2f / %.2f" % [bridge_y(11), bridge_y(7)])
	check("respawn leaves the caldera clear", group_enemies("Enemies/EnemyGroup3").is_empty())
	await shot("lava_respawn.png")

	# Forge.
	var forge := w(0, -47)
	forge.x = 1.5
	place_side_by_side(forge)
	await wait(3.0)
	check("forge trigger starts group 4", group_enemies("Enemies/EnemyGroup4").all(func(e): return e.is_offensive))
	for spot in [[0, -47, "entrance"], [-6, -48, "west"], [6, -53, "east"], [0, -58, "far side"]]:
		place_side_by_side(w(spot[0], spot[1]))
		await wait(1.6)
		check_view("forge %s view" % spot[2], group_enemies("Enemies/EnemyGroup4"))
		check_mages_in_range("forge %s: mages in range on screen" % spot[2])
	await shot("lava_forge.png")
	print("INFO fps in the forge: ", Engine.get_frames_per_second())
	await clear_and_wait("Enemies/EnemyGroup4", "Checkpoint5", 17)
	var pad_edge := w(0, -59)
	pad_edge.x = 1.5
	place_side_by_side(pad_edge)
	await wait(0.5)
	await walk("over the last slabs", 2.0, 8.0)
	place_side_by_side(w(0, -67))
	await wait(1.5)
	check("end area finishes the level", state() == "levelfinished", state())
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
