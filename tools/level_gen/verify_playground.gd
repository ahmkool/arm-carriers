extends Node
## Test driver for world_playground.tscn: spawn, wake trigger, respawn reset.
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
	var detail := "players %d/2, enemies within %.0f m %d/%d, camera y=%.1f" % [players_seen, reach, near_seen, near.size(), get_viewport().get_camera_3d().global_position.y]
	# At normal zoom (no framing), enemies at the edge of the view may be off screen: only the players must show.
	if focal_count() == 0:
		check(label + " (normal zoom: players on screen)", players_seen == 2, detail)
		return
	check(label, players_seen == 2 and near_seen == near.size(), detail)

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

const GROUP := "Enemies/Prototype"

func offensive_count() -> int:
	return group_enemies(GROUP).filter(func(e): return e.is_offensive).size()

func lowest_player_y() -> float:
	var lowest := INF
	for p in players():
		lowest = minf(lowest, p.global_position.y)
	return lowest

## The pit is cells (3..4, -8..-7); its centre is the corner those four cells share.
func pit_distance_to_navmesh() -> float:
	var map := world.get_world_3d().navigation_map
	var centre := w(4, -7) - Vector3(CELL / 2.0, 0, CELL / 2.0)
	var nearest := NavigationServer3D.map_get_closest_point(map, centre)
	return Vector2(nearest.x - centre.x, nearest.z - centre.z).length()

func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.5)
	check("both carriers on the floor", lowest_player_y() > -1.3, "y=%.2f" % lowest_player_y())
	check("carrying the weapon", world.get_active_weapon() != null)
	check("save disabled", world.skip_save)
	check("4 prototype enemies (winged, ground, grenadier and melee mech), waiting", group_enemies(GROUP).size() == 4 and offensive_count() == 0, "%d alive, %d offensive" % [group_enemies(GROUP).size(), offensive_count()])
	for e in group_enemies(GROUP):
		path_ok(e.global_position, w(0, 1), true, "navmesh path from %s to spawn" % e.name)
	var pit_gap := pit_distance_to_navmesh()
	check("pit is not in the navmesh", pit_gap > 1.0, "nearest navmesh point %.1f m from the pit centre" % pit_gap)
	check_view("spawn view", group_enemies(GROUP))
	await shot("01_spawn.png")

	await walk("walk forward into the wake trigger", 2.2, 4.0)
	await wait(0.5)
	check("wake trigger makes the group offensive", offensive_count() == 4, "%d/4" % offensive_count())
	await wait(2.0)
	check_view("after waking", group_enemies(GROUP))
	await shot("02_awake.png")

	kill_group(GROUP)
	await wait(1.0)
	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.0)
	protect_players()
	check("respawn brings the group back, waiting", group_enemies(GROUP).size() == 4 and offensive_count() == 0, "%d alive, %d offensive" % [group_enemies(GROUP).size(), offensive_count()])
	await walk("walk forward again", 2.2, 4.0)
	await wait(0.5)
	check("wake trigger fires again after respawn", offensive_count() == 4, "%d/4" % offensive_count())
	await shot("03_rewoken.png")

	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
