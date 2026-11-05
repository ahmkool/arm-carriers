extends Node
## Test driver for world_local_saw.tscn. Copy it for a new level: keep the helpers, rewrite _run().
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
	get_tree().create_timer(240.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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
	check(label, players_seen == 2 and near_seen == near.size(), "players %d/2, enemies within %.0f m %d/%d, camera y=%.1f" % [players_seen, reach, near_seen, near.size(), get_viewport().get_camera_3d().global_position.y])


func check_mages_in_range(label: String) -> void:
	var in_range := group_enemies("Enemies/EnemyGroup4").filter(_can_cast_at_a_player)
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


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.0)
	var box := world.get_node("UI/InfoMessageBottomRight") as Control
	check("saw hint shows at launch", box.is_visible_in_tree() and box.modulate.a > 0.1)
	await shot("saw_start.png")
	var list := players()
	check("carriers spawn side by side", absf(list[0].global_position.z - list[1].global_position.z) < 1.0 and gap() >= 5.4 and gap() <= 7.1, "gap=%.1f dz=%.1f" % [gap(), absf(list[0].global_position.z - list[1].global_position.z)])
	check_view("spawn view", group_enemies("Enemies/EnemyGroup"), 100.0)

	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 300.0
	top.far = 400.0
	top.position = Vector3(1.5, 150, -125)
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot("saw_overhead.png")
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()

	path_ok(w(0, -10), w(0, -19), true, "nav: arena connects")
	path_ok(w(0, -38), w(0, -25), true, "nav: funnel connects through the neck")
	path_ok(w(0, -60), w(0, -47), true, "nav: lane connects")
	path_ok(w(0, -66), w(0, -78), true, "nav: finale connects")
	path_ok(w(0, 0), w(0, -10), false, "nav: yard separate from arena")

	var saw := world.get_active_weapon()
	var carry: CarryInfo = saw.get_node("PickAndDropHandler").get_carry_info()
	check("both players carry the saw", is_instance_valid(carry.main_carrier) and is_instance_valid(carry.secondary_carrier))
	var hit := saw.get_node("WeaponSpecifics/HitBox/CollisionShape3D") as Node3D
	var mid: Vector3 = (list[0].global_position + list[1].global_position) * 0.5
	print("INFO saw disc at ", hit.global_position, " carriers mid ", mid, " offset %.2f m" % Vector2(hit.global_position.x - mid.x, hit.global_position.z - mid.z).length())

	# A real kill: only walking input, the idle skeleton straight ahead dies on the blade.
	var target: EnemyLocal = world.get_node("Enemies/EnemyGroup/InstancedEnemies/EnemyLocal1")
	var before := group_enemies("Enemies/EnemyGroup").size()
	var dz: float = list[0].global_position.z - target.global_position.z
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var killed: bool = await wait_until(func(): return not target.is_alive(), 5.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	check("real input: walking the saw into a skeleton kills it", killed, "started %.1f m away, alive %d -> %d" % [dz, before, group_enemies("Enemies/EnemyGroup").size()])
	await wait(0.3)
	await shot("saw_kill.png")

	await clear_and_wait("Enemies/EnemyGroup", "Checkpoint2", 1)

	# Triple bridge, side by side.
	move_players(w(0, -6))
	await wait(0.5)
	await walk("cross the triple bridge side by side", 2.0, 7.0)

	# Arena.
	var g2 := group_enemies("Enemies/EnemyGroup2")
	check("arena has 14 idle chasers", g2.size() == 14 and not g2[0].is_offensive, str(g2.size()))
	move_players(w(0, -11))
	await wait(3.0)
	check("arena trigger starts the fight", g2[0].is_offensive)
	var closed1: bool = await wait_until(func(): return bridge_y(1) < -5.5, 8.0)
	check("bridge 1 closes behind players", closed1)
	check("arena: 4 focal points", focal_count() == 4, str(focal_count()))
	check_view("arena entry view", group_enemies("Enemies/EnemyGroup2"), 100.0)
	await shot("saw_arena.png")
	for spot in [[-4, -10, "south-west"], [4, -10, "south-east"], [-4, -19, "north-west"], [4, -19, "north-east"], [0, -14, "centre"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.3)
		check_view("arena %s view" % spot[2], group_enemies("Enemies/EnemyGroup2"))
	await clear_and_wait("Enemies/EnemyGroup2", "Checkpoint3", 7)
	check("camera focus released", focal_count() == 0, str(focal_count()))

	# Twin rails.
	var rail_l: float = w(-1, -20).x
	var rail_r: float = w(1, -20).x
	var rz: float = w(0, -20).z
	place(Vector3(rail_r, 0, rz), Vector3(rail_l, 0, rz))
	await wait(0.5)
	await walk("twin rails, one carrier on each", 2.0, 7.0)
	await shot("saw_rails.png")
	place(Vector3(rail_l, 0, rz + 3.0), Vector3(rail_l, 0, rz - 3.0))
	await wait(0.5)
	await walk("twin rails, single file on one rail", 2.0, 7.0)

	# Funnel.
	var g3 := group_enemies("Enemies/EnemyGroup3")
	check("funnel has 12 idle chasers", g3.size() == 12 and not g3[0].is_offensive, str(g3.size()))
	move_players(w(0, -25))
	await wait(3.0)
	check("funnel trigger starts the fight", g3[0].is_offensive)
	var closed2: bool = await wait_until(func(): return bridge_y(7) < -5.5, 8.0)
	check("twin rails close behind players", closed2)
	check("funnel: 4 focal points", focal_count() == 4, str(focal_count()))
	check_view("funnel entry view", group_enemies("Enemies/EnemyGroup3"))
	await shot("saw_funnel.png")
	await wait(5.0)
	var in_neck := group_enemies("Enemies/EnemyGroup3").filter(func(e): return e.global_position.z > w(0, -34).z)
	print("INFO chasers through or inside the neck after about 12 s: ", in_neck.size(), "/12")
	for spot in [[0, -29, "at the neck"], [0, -36, "north bowl"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.3)
		check_view("funnel %s view" % spot[2], group_enemies("Enemies/EnemyGroup3"))
	await shot("saw_funnel_neck.png")
	await clear_and_wait("Enemies/EnemyGroup3", "Checkpoint4", 11)

	# Respawn in the middle of the level.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	list = players()
	check("respawn at Checkpoint4 works", state() == "playing" and bridge_y(11) > -2.0 and group_enemies("Enemies/EnemyGroup3").is_empty(), state())
	check("respawn: carriers side by side on floor", gap() >= 5.4 and gap() <= 7.1 and list[0].global_position.y > -1.3, "gap=%.1f y=%.2f" % [gap(), list[0].global_position.y])
	check("respawn keeps group 4 intact", group_enemies("Enemies/EnemyGroup4").size() == 9, str(group_enemies("Enemies/EnemyGroup4").size()))

	# Mage lane.
	move_players(w(0, -48))
	await wait(3.0)
	check("lane trigger starts group 4", group_enemies("Enemies/EnemyGroup4").all(func(e): return e.is_offensive))
	var closed3: bool = await wait_until(func(): return bridge_y(11) < -5.5, 8.0)
	check("bridge 3 closes behind players", closed3)
	check_view("lane start view", group_enemies("Enemies/EnemyGroup4"), 11.0)
	await shot("saw_lane.png")
	for spot in [[0, -52, "lower"], [-3, -55, "west"], [3, -55, "east"], [0, -60, "far end"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.5)
		check_mages_in_range("lane %s: mages in range on screen" % spot[2])
		check_view("lane %s view" % spot[2], group_enemies("Enemies/EnemyGroup4"), 11.0)
	check("no death in the lane", state() == "playing", state())
	await clear_and_wait("Enemies/EnemyGroup4", "Checkpoint5", 17)

	# Finale.
	var survival := world.get_node("Enemies/SurvivalEnemyGroup") as SurvivalEnemyGroup
	check("survival lasts 60 s in the scene", is_equal_approx(survival.fight_duration, 60.0), str(survival.fight_duration))
	survival.fight_duration = 14.0
	place(Vector3(rail_r, 0, w(0, -62).z), Vector3(rail_l, 0, w(0, -62).z))
	await wait(0.5)
	await walk("second twin rails, one carrier on each", 2.0, 7.0)
	move_players(w(0, -67))
	await wait(3.5)
	check("finale: 4 focal points", focal_count() == 4, str(focal_count()))
	var live := func(): return world.get_node("Enemies/SurvivalEnemyGroup/Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())
	check_view("finale entry view", live.call())
	await shot("saw_finale.png")
	for spot in [[-6, -72, "west"], [6, -72, "east"], [0, -77, "north"], [0, -72, "centre"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.6)
		check_view("finale %s view" % spot[2], live.call())
	await wait(5.0)
	var spawned: Array = live.call()
	check("survival spawns enemies", spawned.size() > 0, str(spawned.size()))
	check_view("finale after spawns view", spawned)
	# Keep clearing until the group reports done: spawners can still be mid-spawn at this point.
	var cleared_at := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < cleared_at and not survival.signal_emitted:
		for e in live.call():
			Health.apply_damage(e, 9999, e.global_position)
		await wait(0.5)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("survival cleared sets Checkpoint6", cp() == "Checkpoint6", cp())
	check("bridge 5 raised", bridge_y(21) > -2.0)
	check("still Playing before the end", state() == "playing", state())
	move_players(w(0, -85))
	await wait(1.5)
	check("end area finishes the level", state() == "levelfinished", state())
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
