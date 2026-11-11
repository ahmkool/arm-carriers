extends Node
## Test driver for the south deck hold of world_local_rotor_decks_2.tscn (add_rotor_decks_2_south_hold.py).
## Run through godot.sh, see docs/level-creation-for-agents.md:
##   tools/level_gen/godot.sh test tools/level_gen/verify_rotor_decks_2_south_hold.gd res://src/world/levels/world_local_rotor_decks_2.tscn /tmp/rd2 300
## The first group is killed by script; the carriers then walk to the hold deck with real input. A death a few
## seconds into the wave is tested, then the real 40 s wave of gunners on the separate gunner deck runs with the
## carriers invulnerable. Save tracking is disabled, so save.json stays untouched.

const CELL := 2.999
const WAVE := "Enemies/SouthHold"
const BEHIND := ["BridgePlatform2", "BridgePlatform3", "BridgePlatform4"]
const DECKS := {
	"start": [-3, 3, -3, 3],
	"right": [5, 8, -2, 2],
	"hold": [10, 13, 3, 4],
	"gunner": [10, 13, 7, 8],
}
const TO_HOLD := [Vector2i(0, 1), Vector2i(0, 0), Vector2i(8, 0), Vector2i(8, 3), Vector2i(12, 3)]

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
	get_tree().create_timer(280.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func w(cx: int, cz: int, y: float = -1.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func wave() -> SurvivalEnemyGroup:
	return world.get_node(WAVE) as SurvivalEnemyGroup


func gunners() -> Array:
	return world.get_node(WAVE + "/Enemies").get_children().filter(func(c): return c is EnemyLocal)


func living_gunners() -> Array:
	return gunners().filter(func(e): return e.is_alive())


func deck_of(pos: Vector3) -> String:
	var cx := floori(pos.x / CELL)
	var cz := floori(pos.z / CELL)
	for name in DECKS:
		var r: Array = DECKS[name]
		if cx >= r[0] and cx <= r[1] and cz >= r[2] and cz <= r[3]:
			return name
	return ""


func bridge_up(name: String) -> bool:
	var shape := world.get_node("Level/Bridges/%s/AnimatableBody3D/CollisionShape3D" % name) as CollisionShape3D
	return not shape.disabled


func all_on(deck: String) -> bool:
	return players().all(func(p): return deck_of(p.global_position) == deck)


func all_bridges_up() -> bool:
	return bridge_up("BridgePlatform1") and BEHIND.all(bridge_up)


func respawn() -> void:
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.0)
	protect_players()


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


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


# ---------------------------------------------------------------- walking with real input
func expand(corners: Array) -> Array:
	var points: Array = [w(corners[0].x, corners[0].y)]
	for i in range(1, corners.size()):
		var a: Vector2i = corners[i - 1]
		var b: Vector2i = corners[i]
		var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
		var c := a
		while c != b:
			c += step
			points.append(w(c.x, c.y))
	return points


func steer(p: PlayerLocal, to: Vector3) -> void:
	var n := Vector2(to.x - p.global_position.x, to.z - p.global_position.z).normalized()
	var keys := {p.action_right: n.x > 0.38, p.action_left: n.x < -0.38, p.action_down: n.y > 0.38, p.action_up: n.y < -0.38}
	for a in keys:
		if keys[a]:
			Input.action_press(a)
		else:
			Input.action_release(a)


func stop(p: PlayerLocal) -> void:
	for a in [p.action_up, p.action_down, p.action_left, p.action_right]:
		Input.action_release(a)


## The leader walks the cell centres in turn; the other carrier follows the same cells, waiting while closer than
## 2.2 m, as two players crossing one-cell bridges in single file would.
func walk_route(label: String, corners: Array) -> void:
	var list := players()
	var leader: PlayerLocal = list[1]
	var follower: PlayerLocal = list[0]
	var points := expand(corners)
	var lead_i := 0
	var follow_i := 0
	var lowest := INF
	var deadline := Time.get_ticks_msec() + 45000
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
		if lead_i >= points.size() and follow_i >= points.size() - 1:
			break
	stop(leader)
	stop(follower)
	await wait(0.5)
	var target := deck_of(points[-1])
	var there: bool = deck_of(leader.global_position) == target and deck_of(follower.global_position) == target
	check("real input: the carriers walk " + label, there and lowest > -1.6 and state() == "playing",
		"leader %s, follower %s, lowest y %.2f, state %s" % [deck_of(leader.global_position), deck_of(follower.global_position), lowest, state()])


# ---------------------------------------------------------------- the run
func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	protect_players()
	check_scene_values()
	check_navigation()
	await open_the_way()
	await walk_route("from the start island to the hold deck", TO_HOLD)
	await shot("hold_arrival.png")
	await check_wave_starts()
	await check_death_mid_wave()
	await run_the_wave()
	await check_checkpoint3_respawn()
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_scene_values() -> void:
	var g := wave()
	check("the wave lasts 40 s", is_equal_approx(g.fight_duration, 40.0), str(g.fight_duration))
	check("a gunner every 5 s", is_equal_approx(g.spawn_interval_curve.sample(0.0), 5.0) and is_equal_approx(g.spawn_interval_curve.sample(1.0), 5.0))
	check("its enemies are aviator gunners with 6 HP", g.enemy_scene.resource_path.ends_with("enemy_aviator_gunner.tscn") and g.enemy_max_hp == 6)
	var spawns := world.get_node(WAVE + "/SpawnPoints").get_children()
	check("every spawn point is on the gunner deck", spawns.size() == 4 and spawns.all(func(s): return deck_of(s.global_position) == "gunner"))
	check("the wave waits for the carriers", not g.is_running() and gunners().is_empty())


func check_navigation() -> void:
	check("the gunner deck has a navmesh", nav_reaches(w(10, 7), w(13, 8)))
	check("the hold deck has a navmesh", nav_reaches(w(10, 3), w(13, 4)))
	check("nothing walks between the gunner deck and the hold", not nav_reaches(w(11, 7), w(11, 4)))


func open_the_way() -> void:
	check("every bridge starts lowered", not bridge_up("BridgePlatform1") and not BEHIND.any(bridge_up))
	for e in world.get_node("Enemies/EnemyGroup/InstancedEnemies").get_children():
		if e is EnemyLocal:
			Health.from_target(e).kill(e.global_position)
	await wait_until(all_bridges_up, 10.0)
	await wait(1.0)
	check("clearing the first group raises the bridges to the hold deck", all_bridges_up() and cp() == "Checkpoint2", cp())


func check_wave_starts() -> void:
	var started := await wait_until(func(): return wave().is_running(), 4.0)
	check("both carriers on the hold deck start the wave", started)
	var sunk := await wait_until(func(): return not BEHIND.any(bridge_up), 6.0)
	check("the bridges behind them sink", sunk)
	check("the camera frames the hold and the gunner deck", focal_count() == 4, str(focal_count()))
	check("the HUD countdown shows", (world.get_node("UI/SurvivalTimer") as CanvasItem).visible)
	check("the first gunner appears straight away, on the gunner deck", gunners().size() == 1 and deck_of(gunners()[0].global_position) == "gunner")
	if gunners().is_empty():
		return
	var hp: int = Health.from_target(gunners()[0]).max_hp
	check("a gunner has 6 HP", hp == 6, str(hp))


## A death a few seconds into the wave: back to Checkpoint2 with every bridge up, the wave reset and the trigger
## armed. Walking back onto the hold deck starts the wave from the beginning.
func check_death_mid_wave() -> void:
	await wait(6.0)
	await respawn()
	check("a death mid-wave respawns on the start island", cp() == "Checkpoint2" and all_on("start"), cp())
	check("... with the bridges up", all_bridges_up())
	check("... the wave reset and no framing", not wave().is_running() and not wave().signal_emitted and gunners().is_empty() and focal_count() == 0)
	await walk_route("back to the hold deck after a respawn", TO_HOLD)
	var restarted := await wait_until(func(): return wave().is_running(), 4.0)
	await wait(0.5)
	check("the trigger starts the wave again from the top", restarted and gunners().size() == 1, str(gunners().size()))


func nearest_carrier_distance(e: Node3D) -> float:
	var best := INF
	for p in players():
		best = minf(best, Vector2(p.global_position.x - e.global_position.x, p.global_position.z - e.global_position.z).length())
	return best


func run_the_wave() -> void:
	var missed := 0
	var bolts := [0]
	var watch := func(n: Node): if n is FireballSpawn: bolts[0] += 1
	get_tree().node_added.connect(watch)
	for i in 8:
		await wait(5.0)
		protect_players()
		var living := living_gunners()
		var seen := visible_count(living)
		missed += living.size() - seen
		var distances := living.map(func(e): return "%.0f" % nearest_carrier_distance(e))
		print("INFO t=%ds gunners=%d on screen=%d players on screen=%d distances=%s" % [(i + 1) * 5, living.size(), seen, visible_count(players()), ", ".join(distances)])
		if i == 2:
			await shot("south_hold_15s.png")
		if i == 6:
			await shot("south_hold_35s.png")
	get_tree().node_added.disconnect(watch)
	check("eight gunners appear in 40 s", gunners().size() == 8, str(gunners().size()))
	check("the gunners stay on the gunner deck", gunners().all(func(e): return deck_of(e.global_position) == "gunner"))
	check("living gunners stay on screen", missed == 0, "%d misses over the samples" % missed)
	check("both carriers stay on screen", visible_count(players()) == 2)
	check("the gunners shoot across the gap", bolts[0] > 5, "%d bolts" % bolts[0])
	check("the wave isn't over while gunners live", not wave().signal_emitted)
	var cleared := await wait_until(func():
		for e in living_gunners():
			Health.from_target(e).kill(e.global_position)
		return wave().signal_emitted, 8.0)
	await wait(0.5)
	check("clearing the wave saves Checkpoint3", cleared and cp() == "Checkpoint3", cp())
	var raised := await wait_until(func(): return bridge_up("BridgePlatform5") and bridge_up("BridgePlatform6"), 8.0)
	check("and raises the bridge to the gunner deck", raised)
	await wait_until(func(): return state() == "playing" and focal_count() == 0, 8.0)
	check("and clears the camera framing", focal_count() == 0, str(focal_count()))


func check_checkpoint3_respawn() -> void:
	await respawn()
	check("respawning at Checkpoint3 lands on the hold deck", all_on("hold"))
	check("... with the wave done and the bridges behind down", not wave().is_running() and living_gunners().is_empty() and not BEHIND.any(bridge_up))
	await shot("checkpoint3_respawn.png")
