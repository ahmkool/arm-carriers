extends Node
## Test driver for the barge run of world_local_rotor_decks_2.tscn (add_rotor_decks_2_barge_run.py).
## Run through godot.sh, see docs/level-creation-for-agents.md:
##   tools/level_gen/godot.sh test tools/level_gen/verify_rotor_decks_2_barge_run.gd res://src/world/levels/world_local_rotor_decks_2.tscn /tmp/rd2_barge 400
## Starts at Checkpoint4 (the guard dead), on the guard island. The carriers board the barge with real input and ride it; each enemy barge
## is checked as it flies in, sways and fights, then its crew is killed by script (aiming at a swaying barge is for a
## person to judge). A death mid-wave is tested. At the end the carriers walk onto the final island.
## Save tracking is disabled, so save.json stays untouched.

const CELL := 2.999
const WAVES := ["BargeWave1", "BargeWave2"]
const ISLANDS := {
	"gunner": [10, 13, 7, 8],
	"guard": [9, 14, 11, 14],
	"final": [36, 41, 11, 14],
}

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var lowest_rider := INF


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


func barge() -> RotorBarge:
	return world.get_node("Level/Barges/PlayerBarge") as RotorBarge


func enemy_barge(wave: String) -> RotorBarge:
	return world.get_node("Level/Barges/%sBarge" % wave) as RotorBarge


func group(wave: String) -> BargeCrewGroup:
	return world.get_node("Enemies/" + wave) as BargeCrewGroup


func crew(wave: String) -> Array:
	return world.get_node("Enemies/%s/InstancedEnemies" % wave).get_children().filter(func(c): return c is EnemyLocal)


func living_crew(wave: String) -> Array:
	return crew(wave).filter(func(e): return e.is_alive())


func voyage() -> BargeVoyageEvent:
	return world.get_node("Level/Events/BargeRun") as BargeVoyageEvent


func island_of(pos: Vector3) -> String:
	var cx := floori(pos.x / CELL)
	var cz := floori(pos.z / CELL)
	for name in ISLANDS:
		var r: Array = ISLANDS[name]
		if cx >= r[0] and cx <= r[1] and cz >= r[2] and cz <= r[3]:
			return name
	return ""


func all_on(island: String) -> bool:
	return players().all(func(p): return island_of(p.global_position) == island)


func aboard(b: RotorBarge, nodes: Array) -> bool:
	return nodes.all(func(n): return b.deck.contains(n.global_position))


func barge_x() -> float:
	return barge().body.global_position.x


func focal_names() -> Array:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.map(func(n): return String(n.name))


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


func respawn_at(checkpoint: String) -> void:
	world.checkpoint_manager.set_current_checkpoint(world.get_node("CheckpointManager/" + checkpoint))
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.5)
	protect_players()


## Waits while watching the riders, so a carrier sliding off a moving barge is caught.
func ride(seconds: float) -> void:
	var end := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < end:
		await get_tree().physics_frame
		protect_players()
		for p in players():
			lowest_rider = minf(lowest_rider, p.global_position.y)


# ---------------------------------------------------------------- walking with real input
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


## The leader walks the cell centres in turn; the other carrier follows the same cells, waiting while closer than
## 2.2 m. `arrived` says when both are where they should be.
func walk_route(label: String, corners: Array, arrived: Callable) -> void:
	var list := players()
	var leader: PlayerLocal = list[1]
	var follower: PlayerLocal = list[0]
	var points := expand(corners)
	var lead_i := 0
	var follow_i := 0
	var lowest := INF
	var deadline := Time.get_ticks_msec() + 30000
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
	await wait(0.3)
	check("real input: the carriers walk " + label, arrived.call() and lowest > -1.6 and state() == "playing",
		"lowest y %.2f, state %s" % [lowest, state()])


func board() -> void:
	await walk_route("from the guard island onto the barge", [Vector2i(12, 12), Vector2i(16, 12)],
		func(): return aboard(barge(), players()))


# ---------------------------------------------------------------- the run
func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	check_layout()
	await respawn_at("Checkpoint4")
	check_waiting_at_dock("starting at Checkpoint4")
	await shot("barge_docked.png")
	await board()
	var start_x := barge_x()
	await wait_until(func(): return barge().is_moving(), 3.0)
	check("once both are aboard the barge sets off east", barge().is_moving())
	await check_wave_arrives(0, start_x + 18.0)
	await check_death_mid_wave()
	start_x = barge_x()
	await wait_until(func(): return barge().is_moving(), 4.0)
	await check_wave_arrives(0, start_x + 18.0)
	await clear_wave(0)
	await check_wave_arrives(1, start_x + 36.0)
	await clear_wave(1)
	await check_final_leg(start_x)
	await check_checkpoint5()
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_layout() -> void:
	check("the final island has a navmesh", nav_reaches(w(37, 12), w(40, 13)))
	check("and nothing walks there from the guard island", not nav_reaches(w(13, 12), w(37, 12)))
	for wave in WAVES:
		check(wave + " and its barge start hidden", not group(wave).visible and not enemy_barge(wave).visible)
	check("wave 1 is one shield and three gunners", crew("BargeWave1").filter(func(e): return FrontalGuard.find_on(e) != null).size() == 1 and crew("BargeWave1").size() == 4)
	check("wave 2 is two shields", crew("BargeWave2").size() == 2 and crew("BargeWave2").all(func(e): return FrontalGuard.find_on(e) != null))
	check("every crew member starts on its own barge", WAVES.all(func(wave): return aboard(enemy_barge(wave), crew(wave))))


func check_waiting_at_dock(label: String) -> void:
	var dock_x: float = barge().global_position.x
	check(label + ": the barge waits at the guard island's east edge", absf(barge_x() - dock_x) < 0.05 and not barge().is_moving() and voyage().is_running())
	check("... with the carriers on the guard island", all_on("guard"))
	check("... and both waves hidden and asleep", WAVES.all(func(wave): return not group(wave).visible and crew(wave).all(func(e): return not e.is_offensive)))


func check_wave_arrives(index: int, stop_x: float) -> void:
	var wave: String = WAVES[index]
	await wait_until(func(): return enemy_barge(wave).visible, 5.0)
	check(wave + ": its barge shows and flies in during the leg", enemy_barge(wave).visible and enemy_barge(wave).is_moving())
	await ride(0.0)
	var arrived := await wait_until(func(): return not barge().is_moving() and not enemy_barge(wave).is_moving(), 20.0)
	check(wave + ": both barges stop", arrived and absf(barge_x() - stop_x) < 0.1, "barge x %.1f, expected %.1f" % [barge_x(), stop_x])
	await ride(0.5)
	check(wave + ": the crew turns offensive on arrival", crew(wave).all(func(e): return e.is_offensive))
	check(wave + ": the camera frames both barges", focal_count() == 4, str(focal_count()))
	var xs: Array[float] = []
	var bolts := [0]
	var watch := func(n: Node): if n is FireballSpawn: bolts[0] += 1
	get_tree().node_added.connect(watch)
	var seen_min := 99
	for i in 16:
		await ride(0.5)
		xs.append(enemy_barge(wave).body.global_position.x)
		seen_min = mini(seen_min, visible_count(living_crew(wave)) - living_crew(wave).size())
		if i == 9:
			await shot("%s_fight.png" % wave.to_lower())
	get_tree().node_added.disconnect(watch)
	var swing: float = xs.max() - xs.min()
	check(wave + ": its barge sways left and right", enemy_barge(wave).is_swaying() and swing > 5.0 and swing < 9.5, "%.1f m in 8 s" % swing)
	check(wave + ": the crew stays aboard while it sways", aboard(enemy_barge(wave), living_crew(wave)) and living_crew(wave).size() == crew(wave).size())
	check(wave + ": the crew shoots at the carriers", bolts[0] >= 3, "%d bolts" % bolts[0])
	check(wave + ": the crew stays on screen", seen_min == 0)
	check(wave + ": both carriers stay on screen and aboard", visible_count(players()) == 2 and aboard(barge(), players()) and lowest_rider > -1.6, "lowest y %.2f" % lowest_rider)


func clear_wave(index: int) -> void:
	var wave: String = WAVES[index]
	check(wave + ": the barge waits while the crew lives", not barge().is_moving())
	var cleared := await wait_until(func():
		for e in living_crew(wave):
			Health.from_target(e).kill(e.global_position)
		return group(wave).signal_emitted, 6.0)
	await ride(1.0)
	check(wave + ": once the crew is dead its barge stops swaying and stays", cleared and not enemy_barge(wave).is_swaying() and enemy_barge(wave).visible)
	var framed := focal_names()
	check(wave + ": and its framing clears", not framed.any(func(n): return n.begins_with("Focus" + wave)), ", ".join(framed))
	var moving := await wait_until(func(): return barge().is_moving(), 3.0)
	check(wave + ": and the carriers' barge moves on", moving)


func check_death_mid_wave() -> void:
	await respawn_at("Checkpoint4")
	check_waiting_at_dock("a death mid-wave")
	check("... wave 1's barge is back at its parking spot with a fresh crew", not enemy_barge("BargeWave1").is_swaying() and living_crew("BargeWave1").size() == 4 and aboard(enemy_barge("BargeWave1"), crew("BargeWave1")))
	check("... and the framing cleared", focal_count() == 0)
	await board()


func check_final_leg(start_x: float) -> void:
	var docked := await wait_until(func(): return not barge().is_moving() and absf(barge_x() - (start_x + 53.99)) < 0.2, 20.0)
	await ride(0.3)
	check("the last leg docks at the final island", docked and not voyage().is_running(), "barge x %.1f" % barge_x())
	check("the carriers rode the whole way without falling off", lowest_rider > -1.6 and aboard(barge(), players()), "lowest y %.2f" % lowest_rider)
	await shot("final_dock.png")
	await walk_route("off the barge onto the final island", [Vector2i(34, 12), Vector2i(39, 12)], func(): return all_on("final"))
	var saved := await wait_until(func(): return cp() == "Checkpoint5", 3.0)
	check("stepping onto the final island saves Checkpoint5", saved, cp())


func check_checkpoint5() -> void:
	await respawn_at("Checkpoint5")
	check("respawning at Checkpoint5 lands on the final island", all_on("final"))
	check("... with both enemy barges empty and in view of their fights", WAVES.all(func(wave): return enemy_barge(wave).visible and living_crew(wave).is_empty() and not enemy_barge(wave).is_swaying()))
	await shot("checkpoint5.png")
