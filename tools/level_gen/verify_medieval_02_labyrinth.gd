extends Node
## Test driver for the island labyrinth at the start of world_local_02_medieval.tscn
## (built by add_medieval_02_labyrinth.py). Run through godot.sh, see docs/level-creation-for-agents.md.
## Checks the spawn, the raised walkways, the navmesh (islands joined by the walkways), that skeletons come over them,
## that the carriers really walk the bending walkways (real input, steering each carrier round the corners), what
## killing the nine mages does, the walk into the arena, and respawns either side. Save tracking is disabled.

const CELL := 2.999
const MAGES := "Enemies/LabyrinthMages"
const SKELETONS := "Enemies/LabyrinthSkeletons"
## Island rectangles (x0, x1, z0, z1), as in the build script.
const ISLANDS := {
	"Exit": [-6, -3, 17, 19], "NorthWest": [-15, -12, 19, 21], "NorthEast": [1, 4, 20, 22],
	"West": [-17, -15, 27, 29], "Centre": [-8, -5, 26, 29], "East": [4, 7, 27, 29],
	"SouthWest": [-14, -11, 35, 37], "SouthEast": [1, 4, 35, 37], "Start": [-6, -3, 38, 41],
}
## Walkways to walk for real: corner cells, from a cell inside the first island to one inside the second.
const WALKS := {
	"the U onto the south-east island": [Vector2i(-4, 40), Vector2i(-2, 40), Vector2i(6, 40), Vector2i(6, 36), Vector2i(3, 36)],
	"the double S to the centre": [Vector2i(-5, 39), Vector2i(-5, 33), Vector2i(-3, 33), Vector2i(-3, 31), Vector2i(-6, 31), Vector2i(-6, 28)],
	"the hairpin onto the north-east island": [Vector2i(6, 28), Vector2i(6, 18), Vector2i(3, 18), Vector2i(3, 21)],
}

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
	get_tree().create_timer(380.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


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


func w(cx: int, cz: int, y: float = 0.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func group_living(path: String) -> Array:
	return world.get_node(path).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func kill_group(path: String) -> void:
	for e in group_living(path):
		Health.apply_damage(e, 9999, e.global_position)


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


func platform_y(node_path: String) -> float:
	return (world.get_node(node_path + "/AnimatableBody3D") as Node3D).global_position.y


func walk_platforms() -> Array:
	return world.get_node("Level/Bridges/Labyrinth").get_children()


func island_of(pos: Vector3) -> String:
	var cx := floori(pos.x / CELL)
	var cz := floori(pos.z / CELL)
	for name in ISLANDS:
		var r: Array = ISLANDS[name]
		if cx >= r[0] and cx <= r[1] and cz >= r[2] and cz <= r[3]:
			return name
	return ""


func visible_count(nodes: Array, lift: float = 1.0) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(-6.0)
	var seen := 0
	for n in nodes:
		var pos: Vector3 = n.global_position + Vector3(0, lift, 0)
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen


func nav_reaches(from: Vector3, to: Vector3) -> bool:
	var map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return path.size() > 0 and Vector2(path[-1].x - to.x, path[-1].z - to.z).length() < 1.0


func island_centre(name: String) -> Vector3:
	var r: Array = ISLANDS[name]
	return Vector3((r[0] + r[1] + 1) * 0.5 * CELL, -1.0, (r[2] + r[3] + 1) * 0.5 * CELL)


# ---------------------------------------------------------------- walking a bending walkway for real
## Cell centres along straight runs between corner cells.
func expand(corners: Array) -> Array:
	var points: Array = [w(corners[0].x, corners[0].y, -1.0)]
	for i in range(1, corners.size()):
		var a: Vector2i = corners[i - 1]
		var b: Vector2i = corners[i]
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var c := a
		while c != b:
			c += step
			points.append(w(c.x, c.y, -1.0))
	return points


func release_moves() -> void:
	for p in players():
		for a in [p.action_up, p.action_down, p.action_left, p.action_right]:
			Input.action_release(a)


## Presses one carrier's direction keys towards a point (8 directions).
func steer(p: PlayerLocal, to: Vector3) -> void:
	var d := Vector2(to.x - p.global_position.x, to.z - p.global_position.z)
	var n := d.normalized()
	var keys := {p.action_right: n.x > 0.38, p.action_left: n.x < -0.38, p.action_down: n.y > 0.38, p.action_up: n.y < -0.38}
	for a in keys:
		if keys[a]:
			Input.action_press(a)
		else:
			Input.action_release(a)


func stop(p: PlayerLocal) -> void:
	for a in [p.action_up, p.action_down, p.action_left, p.action_right]:
		Input.action_release(a)


## Each carrier walks the cell centres in turn, as two players would: the leader (the direction setter, which the
## blade points past) goes first; the other follows the same cells and waits while closer than 2.2 m.
func walk_route(label: String, corners: Array) -> void:
	var points := expand(corners)
	var list := players()
	var leader: PlayerLocal = list[1]
	var follower: PlayerLocal = list[0]
	var start: Vector3 = points[0]
	var behind: Vector3 = points[0] - (points[1] - points[0]).normalized() * 2.4
	behind = Vector3(start.x, -1.0, start.z) if island_of(behind) == "" else behind
	leader.global_position = start + Vector3.UP
	follower.global_position = behind + Vector3.UP
	leader.velocity = Vector3.ZERO
	follower.velocity = Vector3.ZERO
	await wait(1.0)
	var target_island := island_of(points[-1])
	var lead_i := 1
	var follow_i := 0
	var lowest := INF
	var deadline := Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < deadline and state() == "playing":
		await get_tree().physics_frame
		lowest = minf(lowest, minf(leader.global_position.y, follower.global_position.y))
		if lead_i < points.size() and Vector2(leader.global_position.x - points[lead_i].x, leader.global_position.z - points[lead_i].z).length() < 0.6:
			lead_i += 1
		if follow_i < points.size() and Vector2(follower.global_position.x - points[follow_i].x, follower.global_position.z - points[follow_i].z).length() < 0.6:
			follow_i += 1
		if lead_i < points.size():
			steer(leader, points[lead_i])
		else:
			stop(leader)
		var gap := leader.global_position.distance_to(follower.global_position)
		if follow_i < points.size() and (gap > 2.2 or lead_i >= points.size()) and follow_i < lead_i:
			steer(follower, points[follow_i])
		else:
			stop(follower)
		if lead_i >= points.size() and follow_i >= points.size() - 1 and island_of(follower.global_position) == target_island:
			break
	release_moves()
	await wait(0.5)
	var both_there: bool = island_of(leader.global_position) == target_island and island_of(follower.global_position) == target_island
	check("real input: the carriers walk " + label, both_there and lowest > -1.6 and state() == "playing",
		"leader %s, follower %s, lowest y %.2f, state %s" % [island_of(leader.global_position), island_of(follower.global_position), lowest, state()])


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	# The level now opens on the skull platform (verify_medieval_02_skull_platform.gd): respawn at the labyrinth.
	if cp() != "CheckpointLabyrinth":
		world.checkpoint_manager.set_current_checkpoint(world.get_node("CheckpointManager/CheckpointLabyrinth"))
		gsm.transition_to("resettingcheckpoint")
		await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.0)
	protect_players()

	# ---- Spawn. ----
	check("the labyrinth starts at CheckpointLabyrinth", cp() == "CheckpointLabyrinth", cp())
	var list := players()
	check("both carriers on the start island", list.all(func(p): return island_of(p.global_position) == "Start" and absf(p.global_position.y + 1.0) < 0.3),
		"%s %s" % [list[0].global_position, list[1].global_position])
	var raised := walk_platforms().filter(func(p): return platform_y(String(world.get_path_to(p))) > -1.5)
	check("every walkway platform is up", raised.size() == walk_platforms().size() and raised.size() > 90, "%d/%d" % [raised.size(), walk_platforms().size()])
	check("the bridge to the arena is down", platform_y("Level/Bridges/LabyrinthExitPlatform1") < -4.0)
	check("nine mages, one per island", group_living(MAGES).size() == 9 and ISLANDS.keys().all(func(n): return group_living(MAGES).filter(func(m): return island_of(m.global_position) == n).size() == 1))
	check("ten skeletons", group_living(SKELETONS).size() == 10)
	check("no camera framing (everything can be walked to)", focal_count() == 0, str(focal_count()))
	check("the start island's mage is a threat at spawn", group_living(MAGES).any(func(m): return island_of(m.global_position) == "Start" and m.global_position.distance_to(list[0].global_position) < m.get_node("MageBehavior").cast_max_distance))
	check("both carriers on screen", visible_count(list, 0.0) == 2)
	await shot("01_spawn.png")

	# ---- Navmesh: every island, joined by the walkways, and nothing past the labyrinth. ----
	var islands_ok := ISLANDS.keys().all(func(n): return nav_reaches(island_centre(n) + Vector3(1, 0, 0), island_centre(n) - Vector3(1, 0, 0)))
	check("nav: every island has navmesh", islands_ok)
	var joined := ISLANDS.keys().filter(func(n): return not nav_reaches(island_centre("Start"), island_centre(n)))
	check("nav: the walkways join every island to the start island", joined.is_empty(), "unreachable: %s" % str(joined))
	check("nav: the hairpin and the U are walkable", nav_reaches(island_centre("East"), island_centre("NorthEast")) and nav_reaches(island_centre("Start"), island_centre("SouthEast")))
	check("nav: the labyrinth doesn't join the arena or the horde island (their bridges aren't walkways)",
		not nav_reaches(island_centre("Exit"), Vector3(-9, -1, 37.5)) and not nav_reaches(island_centre("Start"), Vector3(-15, -1, 156)))
	check("nav: the courtyard still has its navmesh", nav_reaches(Vector3(-6, -1, 6), Vector3(3, -1, 0)))

	# ---- Skeletons come over the walkways, and none fall in. ----
	var skeletons := group_living(SKELETONS)
	var start_distance := {}
	for s in skeletons:
		start_distance[s] = s.global_position.distance_to(list[0].global_position)
	var lowest := [INF]
	var on_walkway := [0]
	var watch := func():
		for s in group_living(SKELETONS):
			lowest[0] = minf(lowest[0], s.global_position.y)
			if island_of(s.global_position) == "":
				on_walkway[0] += 1
	get_tree().physics_frame.connect(watch)
	var reached_start := await wait_until(func(): return group_living(SKELETONS).any(func(s): return island_of(s.global_position) == "Start"), 30.0)
	await wait(2.0)
	get_tree().physics_frame.disconnect(watch)
	var closer := skeletons.filter(func(s): return is_instance_valid(s) and s.global_position.distance_to(list[0].global_position) < start_distance[s] - 8.0)
	check("skeletons cross walkways onto the carriers' island", reached_start and on_walkway[0] > 0)
	check("... at least three of them close in", closer.size() >= 3, "%d/10 came 8 m closer" % closer.size())
	check("... and none falls in", group_living(SKELETONS).size() == 10 and lowest[0] > -1.6, "%d alive, lowest y %.2f" % [group_living(SKELETONS).size(), lowest[0]])
	await shot("01b_skeletons_arrive.png")

	# ---- Walking the bends for real. Skeletons are cleared first: the walks test the walkways, not the fights. ----
	kill_group(SKELETONS)
	for label in WALKS:
		await walk_route(label, WALKS[label])
		await shot("02_walk_%d.png" % WALKS.keys().find(label))
		if state() != "playing":
			await wait_until(func(): return state() == "playing", 20.0)
			protect_players()

	# ---- Killing the mages. ----
	kill_group(MAGES)
	await wait(3.5)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.5)
	check("killing the nine mages sets CheckpointStart", cp() == "CheckpointStart", cp())
	check("... and raises the bridge to the arena", platform_y("Level/Bridges/LabyrinthExitPlatform1") > -1.5 and platform_y("Level/Bridges/LabyrinthExitPlatform2") > -1.5)
	check("... and doesn't frame the arena yet", focal_count() == 0, str(focal_count()))

	# Into the arena, for real.
	list = players()
	list[1].global_position = w(-4, 18, 0.0)
	list[0].global_position = w(-4, 19, 0.0) + Vector3(0, 0, 0.6)
	await wait(1.0)
	for p in list:
		Input.action_press(p.action_up)
	var arrived := await wait_until(func(): return focal_count() == 4, 6.0)
	release_moves()
	check("real input: over the bridge onto the arena, which frames the camera", arrived and state() == "playing", "focal %d, z %.1f / %.1f" % [focal_count(), list[1].global_position.z, list[0].global_position.z])
	await wait(0.5)
	await shot("03_arena.png")

	# ---- Respawns. ----
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.5)
	protect_players()
	check("a death in the arena respawns there", cp() == "CheckpointStart" and players().all(func(p): return p.global_position.z < 45.0), cp())
	check("... with the labyrinth cleared and its bridge up", group_living(MAGES).is_empty() and group_living(SKELETONS).is_empty() and platform_y("Level/Bridges/LabyrinthExitPlatform2") > -1.5)
	check("... and the arena framed", focal_count() == 4, str(focal_count()))

	world.checkpoint_manager.set_current_checkpoint(world.get_node("CheckpointManager/CheckpointLabyrinth"))
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.5)
	protect_players()
	check("a death in the labyrinth respawns on the start island", cp() == "CheckpointLabyrinth" and players().all(func(p): return island_of(p.global_position) == "Start"), cp())
	check("... with every mage and skeleton back", group_living(MAGES).size() == 9 and group_living(SKELETONS).size() == 10, "%d mages, %d skeletons" % [group_living(MAGES).size(), group_living(SKELETONS).size()])
	# The arena bridge stays up here: the driver stepped back a checkpoint, which the game never does.
	check("... with the walkways up and no framing", walk_platforms().all(func(p): return platform_y(String(world.get_path_to(p))) > -1.5) and focal_count() == 0, "focal %d" % focal_count())
	await shot("04_respawn.png")

	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
