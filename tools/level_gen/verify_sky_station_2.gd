extends Node
## Test driver for world_local_sky_station_2.tscn, start to finish:
## 1. The range: the firing line frames the nine idle melee mechs across the gap, real fork-cannon fire takes a pack,
##    clearing them sets Checkpoint2 and projects the bridge, walking over it switches it off; a death respawns with
##    the bridge up.
## 2. The flyer: landing wakes the 30 HP winged mech; downing it sets Checkpoint3 and projects the east bridge.
## 3. The hold: crossing east switches that bridge off and starts the survival wave and the two 15 HP grenadiers; a
##    death respawns at Checkpoint3 with both reset. The barge only comes once both are done (Checkpoint4).
## 4. The crossing: boarding flies the carriers to the end island, and its end area finishes the level.
## The survival wave is shortened to 8 s in this driver only, after checking the scene's real 60 s.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_sky_station_2.gd res://src/world/levels/world_local_sky_station_2.tscn <out_dir> 240

const CELL := 2.999
const GROUP := "Enemies/EnemyGroup"
## The bridge's two cells, and the first row of the island past it.
const BRIDGE_CELLS := [Vector2i(0, -5), Vector2i(0, -6)]
const ISLAND_SOUTH_Z := -7 * CELL + CELL  # world z of the island's south edge (row -7)
const BRIDGE2_CELLS := [Vector2i(6, -12), Vector2i(7, -12)]
const ISLAND3_WEST_X := 8 * CELL  # world x of island 3's west edge (column 8)

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
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func info(text: String) -> void:
	print("INFO " + text)


func state() -> String:
	return "" if gsm.current == null else String(gsm.current.name).to_lower()


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


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


func w(cx: float, cz: float, y: float = 0.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func _players_middle() -> Vector3:
	var sum := Vector3.ZERO
	for p in players():
		sum += p.global_position
	return sum / players().size()


func lowest_player_y() -> float:
	var lowest := INF
	for p in players():
		lowest = minf(lowest, p.global_position.y)
	return lowest


func mechs() -> Array:
	return world.get_node(GROUP).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


func on_screen(node: Node3D, height: float = 1.0) -> bool:
	var cam := get_viewport().get_camera_3d()
	var pos := node.global_position + Vector3.UP * height
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos))


## Solid floor under both bridge cells: the hard-light bridge is up.
func bridge_up() -> bool:
	var space := world.get_world_3d().direct_space_state
	for cell in BRIDGE_CELLS:
		var at := w(cell.x, cell.y)
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5.0, at + Vector3.DOWN * 10.0, 4)
		if space.intersect_ray(query).is_empty():
			return false
	return true


func path_reaches(from: Vector3, to: Vector3) -> bool:
	var map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return path.size() > 0 and path[path.size() - 1].distance_to(NavigationServer3D.map_get_closest_point(map, to)) < 0.6


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)


func walk_north_until(cond: Callable, timeout: float) -> bool:
	var list := players()
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var ok: bool = await wait_until(cond, timeout)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	await get_tree().physics_frame
	return ok


## Both carriers inside the island's trigger, which starts a row in from its south edge.
func both_on_island() -> bool:
	return players().all(func(p): return p.global_position.z < ISLAND_SOUTH_Z - CELL - 2.0)

func enemies_in(group: String) -> Array:
	var holder := world.get_node(group)
	var parent: Node = holder.get_node_or_null("InstancedEnemies")
	if parent == null:
		parent = holder.get_node("Enemies")
	return parent.get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func kill_all(group: String) -> void:
	for e in enemies_in(group):
		Health.apply_damage(e, 9999, e.global_position)


func barge(name: String = "Barge") -> RotorBarge:
	return world.get_node("Level/" + name) as RotorBarge


func barge_at(stop: int, name: String = "Barge") -> bool:
	var b := barge(name)
	var want: Vector3 = b.global_position + b.stops[stop]
	return Vector2(b.body.global_position.x - want.x, b.body.global_position.z - want.z).length() < 0.1


func holding_at(stop: int, name: String = "Barge2") -> bool:
	return barge_at(stop, name) and not barge(name).is_moving()


func aboard(name: String) -> bool:
	return players().all(func(p): return barge(name).deck.contains(p.global_position))


## Solid floor under every given cell.
func floor_under(cells: Array) -> bool:
	var space := world.get_world_3d().direct_space_state
	for cell in cells:
		var at := w(cell.x, cell.y)
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 5.0, at + Vector3.DOWN * 10.0, 4)
		if space.intersect_ray(query).is_empty():
			return false
	return true


## Puts the pair in single file along a line through `front`, the back carrier `gap` metres behind along `back_dir`.
func place_in_line(front: Vector3, back_dir: Vector3, gap: float = 2.6) -> void:
	var carry: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	for p in players():
		p.velocity = Vector3.ZERO
	carry.secondary_carrier.global_position = front
	carry.main_carrier.global_position = front + back_dir.normalized() * gap


func walk_until(action: String, cond: Callable, timeout: float) -> bool:
	var list := players()
	for p in list:
		Input.action_press(p.get(action))
	var ok: bool = await wait_until(cond, timeout)
	for p in list:
		Input.action_release(p.get(action))
	await get_tree().physics_frame
	return ok


func on_screen_count(list: Array) -> int:
	return list.filter(func(e): return is_instance_valid(e) and on_screen(e, 1.2)).size()



func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(2.5)
	check("both carriers on the station floor", lowest_player_y() > -1.6, "lowest y=%.2f" % lowest_player_y())
	check("carrying the fork cannon", world.get_active_weapon() != null and world.get_active_weapon().scene_file_path.ends_with("fork_cannon.tscn"))
	var list := mechs()
	check("nine melee mechs, idle", list.size() == 9 and list.all(func(m): return not m.is_offensive and m.scene_file_path.ends_with("enemy_melee_mech.tscn")), "%d" % list.size())
	check("they stand on the island's floor", list.all(func(m): return m.is_on_floor() and m.global_position.z < ISLAND_SOUTH_Z))
	check("the bridge is down at the start", not bridge_up())
	check("no walking path from the station to the island before the bridge", not path_reaches(w(0, 1), w(0, -10)))
	check("both carriers on screen at the spawn", players().all(on_screen))
	await shot("01_spawn.png")

	# ---- The firing line. ----
	await hold([players()[0].action_up, players()[1].action_up], 1.8)
	await wait(1.5)
	check("real input: walking to the firing line frames the range", focal_count() == 4, "%d focal points" % focal_count())
	var seen := mechs().filter(func(m): return on_screen(m, 1.2)).size()
	check("all nine mechs on screen from the firing line", seen == 9, "%d/9" % seen)
	check("both carriers on screen at the firing line", players().all(on_screen))
	check("still on the station", lowest_player_y() > -1.6 and state() == "playing", "lowest y=%.2f" % lowest_player_y())
	await shot("02_firing_line.png")

	# Real fire: the front carrier's missile straight ahead at the middle pack, then the back carrier's bolts.
	var carry: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	var before := mechs().size()
	await hold([carry.secondary_carrier.action_shoot], 0.2)
	await wait(5.0)
	var after_missile := mechs().size()
	await hold([carry.main_carrier.action_shoot], 3.0)
	await wait(1.0)
	info("real fire: %d of %d mechs down after one missile, %d after 3 s of bolts" % [before - after_missile, before, before - mechs().size()])
	check("real fire: one missile takes a pack across the gap", before - after_missile >= 3, "%d down" % (before - after_missile))
	# The bolts fly straight on, past the side packs; a player turns the gun to reach them, which this test doesn't do.
	await shot("03_after_fire.png")

	for m in mechs():
		Health.apply_damage(m, 9999, m.global_position)
	var cleared: bool = await wait_until(func(): return bridge_up(), 6.0)
	check("clearing the mechs sets Checkpoint2", cp() == "Checkpoint2", cp())
	check("clearing the mechs projects the bridge", cleared)
	await wait_until(func(): return focal_count() == 0, 3.0)
	check("clearing the mechs releases the camera", focal_count() == 0, "%d" % focal_count())
	await shot("04_bridge_up.png")

	# ---- Over the bridge. ----
	check("real input: walking over the bridge onto the island", await walk_north_until(both_on_island, 8.0) and state() == "playing", "lowest y=%.2f, state %s" % [lowest_player_y(), state()])
	var closed: bool = await wait_until(func(): return not bridge_up(), 4.0)
	check("stepping onto the island switches the bridge off behind them", closed)
	await shot("05_on_island.png")

	# ---- A death on the island respawns at Checkpoint2 with the bridge up and the mechs gone. ----
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.5)
	protect_players()
	check("respawn at Checkpoint2 on the station", cp() == "Checkpoint2" and players().all(func(p): return p.global_position.z > ISLAND_SOUTH_Z + 3.0), cp())
	check("after a death the bridge is up and the mechs stay dead", bridge_up() and mechs().is_empty(), "%d mechs" % mechs().size())
	check("real input: crossing again", await walk_north_until(both_on_island, 10.0))
	check("crossing again switches the bridge off", await wait_until(func(): return not bridge_up(), 4.0))

	# ---- 2. The flyer. Landing on island 2 woke it. ----
	var winged: Array = enemies_in("Enemies/WingedGroup")
	check("landing on island 2 wakes the winged mech", winged.size() == 1 and winged[0].is_offensive)
	if winged.is_empty():
		get_tree().quit(1)
		return
	var flyer: EnemyLocal = winged[0]
	check("the winged mech has 30 HP", flyer.get_node("Health").max_hp == 30 and flyer.get_node("Health").current_hp == 30, "max %d, now %d" % [flyer.get_node("Health").max_hp, flyer.get_node("Health").current_hp])
	await wait(2.0)  # it starts a row past the landing trigger, so give it time to close in
	var flyer_seen := 0
	for i in 6:
		await wait(1.0)
		flyer_seen += 1 if on_screen(flyer, 1.2) else 0
		if i == 2:
			await shot("06_winged.png")
	check("the winged mech stays on screen while it fights", flyer_seen >= 4, "%d/6" % flyer_seen)
	check("the east bridge stays down while it lives", not floor_under(BRIDGE2_CELLS))
	kill_all("Enemies/WingedGroup")
	var east_up: bool = await wait_until(func(): return floor_under(BRIDGE2_CELLS), 6.0)
	check("downing it sets Checkpoint3", cp() == "Checkpoint3", cp())
	check("downing it projects the east bridge", east_up)
	await shot("07_east_bridge.png")

	# ---- 3. The hold. Single file along the one-cell bridge, as a player has to turn to cross it. ----
	place_in_line(w(4, -12, lowest_player_y()), Vector3.LEFT)
	await wait(0.8)
	var crossed: bool = await walk_until("action_right", func(): return players().all(func(p): return p.global_position.x > ISLAND3_WEST_X + CELL + 2.0), 10.0)
	check("real input: crossing the east bridge onto island 3", crossed and state() == "playing", "lowest y=%.2f, state %s" % [lowest_player_y(), state()])
	var survival := world.get_node("Enemies/SurvivalEnemyGroup") as SurvivalEnemyGroup
	var started: bool = await wait_until(func(): return survival.is_running(), 3.0)
	check("landing on island 3 starts the survival wave", started)
	check("the survival wave lasts 60 s", is_equal_approx(survival.fight_duration, 60.0), "%.0f s" % survival.fight_duration)
	check("and switches the east bridge off behind them", await wait_until(func(): return not floor_under(BRIDGE2_CELLS), 4.0))
	var grenadiers := enemies_in("Enemies/Grenadiers")
	check("two grenadiers wake with it, 15 HP each", grenadiers.size() == 2 and grenadiers.all(func(g): return g.is_offensive and g.get_node("Health").max_hp == 15 and g.get_node("Health").current_hp == 15),
		str(grenadiers.map(func(g): return g.get_node("Health").current_hp)))
	await wait(6.0)
	var melee := enemies_in("Enemies/SurvivalEnemyGroup")
	check("the wave spawns melee mechs", melee.size() > 0 and melee.all(func(e): return e.scene_file_path.ends_with("enemy_melee_mech.tscn")), "%d" % melee.size())
	var grenades := get_tree().current_scene.get_children().filter(func(c): return c is MechGrenade).size()
	info("after 6 s of the hold: %d melee mechs up, %d grenades in play, grenadiers on screen %d/2" % [melee.size(), grenades, on_screen_count(grenadiers)])
	await shot("08_hold.png")
	check("the barge stays at the end island during the hold", barge_at(0) and not barge().is_moving())

	# A death mid-hold respawns at Checkpoint3, with the wave and the grenadiers waiting again.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.5)
	protect_players()
	check("a death mid-hold respawns at Checkpoint3", cp() == "Checkpoint3", cp())
	check("after it the wave is reset and the grenadiers wait again", not survival.is_running() and enemies_in("Enemies/SurvivalEnemyGroup").is_empty()
		and enemies_in("Enemies/Grenadiers").size() == 2 and enemies_in("Enemies/Grenadiers").all(func(g): return not g.is_offensive))
	check("after it the east bridge is up again", floor_under(BRIDGE2_CELLS))
	place_in_line(w(4, -12, lowest_player_y()), Vector3.LEFT)
	await wait(0.8)
	check("real input: crossing east again", await walk_until("action_right", func(): return players().all(func(p): return p.global_position.x > ISLAND3_WEST_X + CELL + 2.0), 10.0))
	check("crossing again restarts the hold", await wait_until(func(): return survival.is_running(), 3.0))
	survival.fight_duration = 8.0  # this driver only: the scene's 60 s was checked above
	kill_all("Enemies/Grenadiers")
	await wait(0.5)
	check("downing the grenadiers alone doesn't call the barge", barge_at(0) and not barge().is_moving() and survival.is_running())
	var hold_cleared: bool = await wait_until(func():
		kill_all("Enemies/SurvivalEnemyGroup")
		return survival.signal_emitted, 20.0)
	check("the wave ends once its time is up and its mechs are down", hold_cleared)
	var called: bool = await wait_until(func(): return barge().is_moving() and barge().target_stop() == 1, 3.0)
	check("clearing the hold sets Checkpoint4", cp() == "Checkpoint4", cp())
	check("clearing the hold calls the barge", called)
	check("the camera frames the barge's dock while it comes", focal_count() == 4, "%d focal points" % focal_count())
	var docked: bool = await wait_until(func(): return barge_at(1) and not barge().is_moving(), 15.0)
	check("the barge docks at island 3's south edge", docked, str(barge().body.global_position))
	check("the docked barge and both carriers are on screen", on_screen(barge().body, 0.0) and players().all(on_screen))
	await shot("09_barge_docked.png")

	# ---- 4. The crossing. ----
	place_in_line(w(13, -8, lowest_player_y()), Vector3.FORWARD)
	await wait(0.8)
	var on_barge: bool = await walk_until("action_down", func(): return players().all(func(p): return barge().deck.contains(p.global_position, 2.0)), 8.0)
	check("real input: walking south onto the barge", on_barge and state() == "playing", "lowest y=%.2f" % lowest_player_y())
	check("standing on it releases the camera", await wait_until(func(): return focal_count() == 0, 3.0), "%d" % focal_count())
	check("boarding sets it off south", await wait_until(func(): return barge().is_moving() and barge().target_stop() == 2, 4.0))
	var landed: bool = await wait_until(func(): return holding_at(2, "Barge"), 15.0)
	check("it docks at island 4 with the carriers aboard", landed and aboard("Barge"), str(barge().body.global_position))
	check("landing on island 4 sets Checkpoint5", await wait_until(func(): return cp() == "Checkpoint5", 2.0), cp())
	check("the second barge waits at island 4's east edge", await wait_until(func(): return holding_at(1), 2.0))
	await shot("10_island4.png")

	# ---- 5. The voyage east. ----
	var gunners := world.get_node("Enemies/GunnerWave") as SurvivalEnemyGroup
	check("the gunner wave lasts 60 s", is_equal_approx(gunners.fight_duration, 60.0), "%.0f s" % gunners.fight_duration)
	check("real input: walking east onto the second barge", await board_east())
	check("boarding sets the second barge off east", await wait_until(func(): return barge("Barge2").is_moving() and barge("Barge2").target_stop() == 2, 4.0))
	check("the gunner wave starts on the way", await wait_until(func(): return gunners.is_running(), 4.0))
	check("the camera frames the gunner island for the wave", await wait_until(func(): return focal_count() == 4, 2.0), "%d" % focal_count())
	check("the barge holds beside the gunner island", await wait_until(func(): return holding_at(2), 15.0), str(barge("Barge2").body.global_position))
	var bolts := [0]
	var count_bolt := func(node: Node): bolts[0] += 1 if node is FireballSpawn else 0
	get_tree().node_added.connect(count_bolt)
	await wait(8.0)
	get_tree().node_added.disconnect(count_bolt)
	var up := enemies_in("Enemies/GunnerWave")
	check("the wave spawns mech gunners on their island", up.size() > 0 and up.all(func(g): return g.scene_file_path.ends_with("enemy_ground_mech.tscn") and _on_gunner_island(g)), "%d" % up.size())
	check("the gunners fire at the barge from their island", bolts[0] > 0, "%d bolts in 8 s" % bolts[0])
	check("the gunners are on screen", on_screen_count(up) == up.size(), "%d/%d" % [on_screen_count(up), up.size()])
	check("the carriers stay aboard and on screen", aboard("Barge2") and players().all(on_screen) and state() == "playing")
	await shot("11_gunners.png")
	check("the barge holds while the wave runs", holding_at(2) and gunners.is_running())

	# A death mid-voyage respawns at Checkpoint5, with the barge back at its dock and both waves waiting.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.5)
	protect_players()
	check("a death mid-voyage respawns at Checkpoint5", cp() == "Checkpoint5", cp())
	check("after it the second barge is back at its dock", holding_at(1), str(barge("Barge2").body.global_position))
	check("after it both waves wait again", not gunners.is_running() and enemies_in("Enemies/GunnerWave").is_empty() and enemies_in("Enemies/WingedWave").size() == 1)
	check("real input: boarding again", await board_east())
	await wait_until(func(): return gunners.is_running(), 6.0)
	gunners.fight_duration = 6.0  # this driver only: the scene's 60 s was checked above
	var wave_done: bool = await wait_until(func():
		kill_all("Enemies/GunnerWave")
		return gunners.signal_emitted, 30.0)
	check("the gunner wave ends once its time is up and its gunners are down", wave_done)
	check("the barge sets off for the next hold", await wait_until(func(): return barge("Barge2").target_stop() == 3 and barge("Barge2").is_moving(), 4.0))
	check("and the camera lets go of the gunner island", await wait_until(func(): return focal_count() == 0, 2.0), "%d" % focal_count())
	var flyer2: Array = enemies_in("Enemies/WingedWave")
	var flew_in: bool = await wait_until(func(): return flyer2.size() == 1 and flyer2[0].visible and flyer2[0].process_mode == Node.PROCESS_MODE_INHERIT, 8.0)
	check("a winged mech flies in over the deck", flew_in and flyer2[0].is_offensive)
	check("it has 30 HP", flyer2.size() == 1 and flyer2[0].get_node("Health").max_hp == 30)
	var seen2 := 0
	for i in 6:
		await wait(1.0)
		seen2 += 1 if is_instance_valid(flyer2[0]) and on_screen(flyer2[0], 1.2) else 0
		if is_instance_valid(flyer2[0]):
			var off: Vector3 = flyer2[0].global_position - _players_middle()
			info("t=%d winged over the barge: %s offset=(%.1f, %.1f, %.1f) on_screen=%s" % [i, flyer2[0].enemy_state_machine.current_state.name, off.x, off.y, off.z, on_screen(flyer2[0], 1.2)])
		if i == 2:
			await shot("12_winged_wave.png")
	check("it keeps up with the moving barge and stays on screen", seen2 >= 4, "%d/6, from the moment it switches on" % seen2)
	check("the barge holds for it", await wait_until(func(): return holding_at(3), 15.0))
	check("the barge keeps holding while it lives", holding_at(3) and aboard("Barge2"))
	kill_all("Enemies/WingedWave")
	check("downing it sends the barge to the end island", await wait_until(func(): return barge("Barge2").target_stop() == 4 and barge("Barge2").is_moving(), 4.0))
	var docked_end: bool = await wait_until(func(): return holding_at(4), 20.0)
	check("it docks at the end island with the carriers aboard", docked_end and aboard("Barge2"), str(barge("Barge2").body.global_position))
	check("landing on the end island sets Checkpoint6", await wait_until(func(): return cp() == "Checkpoint6", 3.0), cp())
	check("the third barge waits at the end island's north edge", await wait_until(func(): return holding_at(1, "Barge3"), 2.0), str(barge("Barge3").body.global_position))
	await shot("13_end_island.png")

	# ---- 6. The last flight north. ----
	var pair := world.get_node("Enemies/WingedPair") as EnemyGroup
	check("two winged mechs wait for the last flight", enemies_in("Enemies/WingedPair").size() == 2)
	check("real input: walking north onto the third barge", await board_north())
	check("boarding sets it off north", await wait_until(func(): return barge("Barge3").is_moving() and barge("Barge3").target_stop() == 2, 4.0))
	var flyers: Array = enemies_in("Enemies/WingedPair")
	var both_in: bool = await wait_until(func(): return flyers.size() == 2 and flyers.all(func(f): return f.visible and f.process_mode == Node.PROCESS_MODE_INHERIT), 8.0)
	check("both winged mechs fly in over the deck", both_in and flyers.all(func(f): return f.is_offensive))
	check("each has 30 HP", flyers.size() == 2 and flyers.all(func(f): return f.get_node("Health").max_hp == 30))
	var seen3 := 0
	for i in 6:
		await wait(1.0)
		seen3 += on_screen_count(flyers)
		if i == 2:
			await shot("14_winged_pair.png")
	check("the pair stays on screen over the moving barge", seen3 >= 6, "%d/12 mech-samples" % seen3)
	check("the barge holds for them", await wait_until(func(): return holding_at(2, "Barge3"), 15.0))
	check("it keeps holding while one lives", holding_at(2, "Barge3") and aboard("Barge3"))
	var first: Node = flyers[0]
	Health.apply_damage(first, 9999, first.global_position)
	await wait(1.5)
	check("downing only one keeps it holding", holding_at(2, "Barge3") and not pair.get("signal_emitted"))
	kill_all("Enemies/WingedPair")
	check("downing both sends the barge to the final island", await wait_until(func(): return barge("Barge3").target_stop() == 3 and barge("Barge3").is_moving(), 4.0))
	var docked_final: bool = await wait_until(func(): return holding_at(3, "Barge3"), 25.0)
	check("it docks at the final island with the carriers aboard", docked_final and aboard("Barge3"), str(barge("Barge3").body.global_position))
	check("carriers on screen at the final dock", players().all(on_screen))
	await shot("15_final_dock.png")
	var finished: bool = await walk_north_until(func(): return state() == "levelfinished", 8.0)
	check("real input: walking north into the end area finishes the level", finished, "%s, lowest y=%.2f" % [state(), lowest_player_y()])
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


## Single file heading east from island 4 onto the second barge, as the first barge leaves them facing south.
func board_east() -> bool:
	place_in_line(w(16, 5.5, lowest_player_y()), Vector3.LEFT)
	await wait(0.8)
	var on: bool = await walk_until("action_right", func(): return players().all(func(p): return barge("Barge2").deck.contains(p.global_position, 2.0)), 8.0)
	return on and state() == "playing"


## Single file heading north from the end island onto the third barge.
func board_north() -> bool:
	place_in_line(w(54, 5.5, lowest_player_y()), Vector3.BACK)
	await wait(0.8)
	var on: bool = await walk_north_until(func(): return players().all(func(p): return barge("Barge3").deck.contains(p.global_position, 2.0)), 8.0)
	return on and state() == "playing"


func _on_gunner_island(gunner: Node3D) -> bool:
	var cell := Vector2(gunner.global_position.x / CELL - 0.5, gunner.global_position.z / CELL - 0.5)
	return cell.x > 25.5 and cell.x < 34.5 and cell.y > -3.5 and cell.y < 2.6
