extends Node
## Test driver for world_local_storm_isles.tscn (build_storm_isles.py). Helpers copied from verify_saw_gauntlet.gd.
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
	get_tree().create_timer(1150.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func rain() -> Rain:
	return world.get_node("Level/Rain") as Rain


func overhead(file_name: String) -> void:
	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 90.0
	top.far = 400.0
	top.position = Vector3(1.5, 150, -22)
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot(file_name)
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()


## Columns of the warm-up grid, west to east: enemies are numbered row by row from the south, three to a row.
func grid_column(index: int) -> Array:
	var out := []
	for row in 3:
		out.append(world.get_node("Enemies/EnemyGroup/InstancedEnemies/EnemyLocal%d" % (row * 3 + index + 1)))
	return out


func horde_live() -> Array:
	return world.get_node("Enemies/SurvivalEnemyGroup/Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


## Walks the pair from the start island's north edge over bridge 1 into the horde trigger, with real input.
func cross_to_second_island() -> void:
	move_players(w(0, -5))
	await wait(0.6)
	await walk("cross bridge 1 to the second island side by side", 3.2, 12.0)
	var list := players()
	check("both carriers reach the second island", list[0].global_position.z < w(0, -9).z + 1.5 and list[1].global_position.z < w(0, -9).z + 1.5, "z=%.1f/%.1f" % [list[0].global_position.z, list[1].global_position.z])


func walk_east(label: String, seconds: float, min_moved: float) -> void:
	var list := players()
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	var a0: float = list[0].global_position.x
	var b0: float = list[1].global_position.x
	await hold([list[0].action_right, list[1].action_right], seconds)
	get_tree().physics_frame.disconnect(watch)
	var ma: float = list[0].global_position.x - a0
	var mb: float = list[1].global_position.x - b0
	check("real input: " + label, ma > min_moved and mb > min_moved and lowest[0] > -1.3 and state() == "playing", "moved %.1f/%.1f, lowest y=%.2f, gap=%.1f, state=%s" % [ma, mb, lowest[0], gap(), state()])


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.0)
	var box := world.get_node("UI/InfoMessageBottomRight") as Control
	check("saw hint shows at launch", box.is_visible_in_tree() and box.modulate.a > 0.1)
	await shot("storm_start.png")
	var list := players()
	check("carriers spawn side by side", absf(list[0].global_position.z - list[1].global_position.z) < 1.0 and gap() >= 5.4 and gap() <= 7.1, "gap=%.1f" % gap())
	var saw := world.get_active_weapon()
	var carry: CarryInfo = saw.get_node("PickAndDropHandler").get_carry_info()
	check("both players carry the saw", is_instance_valid(carry.main_carrier) and is_instance_valid(carry.secondary_carrier))
	var grid := group_enemies("Enemies/EnemyGroup")
	check("warm-up has 9 idle skeletons", grid.size() == 9 and grid.all(func(e): return not e.is_offensive), str(grid.size()))
	check("warm-up: normal zoom", focal_count() == 0, str(focal_count()))
	check_view("spawn view", grid, 100.0)
	print("INFO skeletons on screen from the spawn: %d/9" % visible_count(grid))

	# Rain.
	var drops := rain().get_node("Drops") as GPUParticles3D
	var splashes := rain().get_node("Splashes") as GPUParticles3D
	var cam := get_viewport().get_camera_3d()
	check("rain falls", drops.emitting and drops.amount > 500)
	check("rain follows the camera", (drops.global_position - cam.global_position).distance_to(rain().drops_offset) < 0.5, str(drops.global_position - cam.global_position))
	var points: int = (splashes.process_material as ParticleProcessMaterial).emission_point_count
	check("splashes cover the open floor cells", splashes.emitting and points >= 6 * 250, "points=%d" % points)
	var water := world.get_node("Level/Water") as MeshInstance3D
	check("sea has rain ripples", (water.material_override as ShaderMaterial).get_shader_parameter("rain_ripples") > 0.1)
	var sun := world.get_node("DirectionalLight3D") as DirectionalLight3D
	var base_energy := sun.light_energy
	rain()._play_flash()
	await wait(0.05)
	check("lightning flashes the sun", sun.light_energy > base_energy + 0.5, "%.2f -> %.2f" % [base_energy, sun.light_energy])
	await shot("storm_lightning.png")
	await wait(1.0)
	check("lightning fades back", is_equal_approx(sun.light_energy, base_energy), "%.2f" % sun.light_energy)
	await overhead("storm_overhead.png")

	path_ok(w(0, 3), w(0, -5), true, "nav: start island connects")
	path_ok(w(0, -10), w(0, -19), true, "nav: second island connects")
	path_ok(w(0, 0), w(0, -12), false, "nav: islands separate (bridges aren't in the navmesh)")
	path_ok(w(10, -12), w(14, -16), true, "nav: third island connects")
	path_ok(w(3, -15), w(11, -15), false, "nav: second and third islands separate")
	path_ok(w(20, -16), w(34, -8), true, "nav: the grid's walkways connect")
	path_ok(w(26, -5), w(34, 9), true, "nav: the mage grid's walkways connect")
	path_ok(w(26, -10), w(26, -4), false, "nav: the two grids separate")
	path_ok(w(16, -15), w(21, -15), false, "nav: third island and grid separate")

	# A real sweep: walking only, the carriers straddle the middle column and the disc cuts all three skeletons.
	var middle := grid_column(1)
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	var swept: bool = await wait_until(func(): return middle.all(func(e): return not e.is_alive()), 10.0)
	get_tree().physics_frame.disconnect(watch)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	await shot("storm_sweep.png")
	check("real input: one pass cuts down the middle column", swept, "alive in column: %d" % middle.filter(func(e): return e.is_alive()).size())
	check("the side columns are untouched by that pass", grid_column(0).all(func(e): return e.is_alive()) and grid_column(2).all(func(e): return e.is_alive()))
	check("carriers stay on the island while sweeping", lowest[0] > -1.3 and state() == "playing", "lowest y=%.2f" % lowest[0])

	for spot in [[-2, 4, "south-west"], [2, 4, "south-east"], [-2, -4, "north-west"], [2, -4, "north-east"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.3)
		check_view("start island %s view" % spot[2], group_enemies("Enemies/EnemyGroup"))
	await shot("storm_corner.png")

	check("bridge stays down while skeletons stand", bridge_y(1) < -5.5, "y=%.2f" % bridge_y(1))
	kill_group("Enemies/EnemyGroup")
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("clearing the grid sets Checkpoint2", cp() == "Checkpoint2", cp())
	for i in range(1, 7):
		check("bridge platform %d raised" % i, bridge_y(i) > -2.0, "y=%.2f" % bridge_y(i))
	await shot("storm_bridge.png")

	# The horde waits for both carriers on the second island.
	var survival := world.get_node("Enemies/SurvivalEnemyGroup") as SurvivalEnemyGroup
	check("horde lasts 60 s in the scene", is_equal_approx(survival.fight_duration, 60.0), str(survival.fight_duration))
	check("a skeleton every 2 s, start to end", is_equal_approx(survival.spawn_interval_curve.sample(0.0), 2.0) and is_equal_approx(survival.spawn_interval_curve.sample(1.0), 2.0))
	check("horde idle before the carriers arrive", not survival.is_running())
	var spawned := [0]
	var horde_parent := world.get_node("Enemies/SurvivalEnemyGroup/Enemies")
	horde_parent.child_entered_tree.connect(func(n): if n is EnemyLocal: spawned[0] += 1)
	await cross_to_second_island()
	var started: bool = await wait_until(func(): return survival.is_running(), 6.0)
	check("stepping onto the second island starts the horde", started)
	var closed1: bool = await wait_until(func(): return bridge_y(1) < -5.5, 8.0)
	check("bridge 1 lowers behind the carriers", closed1, "y=%.2f" % bridge_y(1))
	check("horde: normal zoom, every skeleton comes to the carriers", focal_count() == 0, str(focal_count()))
	var timer_ui := world.get_node("UI/SurvivalTimer") as Control
	check("survival timer shows", timer_ui.is_visible_in_tree())

	# Watch the horde for a while: the carriers stand still and let the skeletons run into the saw.
	var spawned_at_start: int = spawned[0]
	var watch_from := Time.get_ticks_msec()
	await wait(4.5)
	var runners := horde_live().filter(func(e): return e.is_offensive)
	var before_dist := runners.map(func(e): return _player_distance(e))
	await wait(1.5)
	var closed_in := 0
	for i in runners.size():
		if is_instance_valid(runners[i]) and runners[i].is_alive() and _player_distance(runners[i]) < before_dist[i] - 1.5:
			closed_in += 1
	check("skeletons run at the carriers", closed_in > 0, "%d of %d closed in by 1.5 m+ in 1.5 s" % [closed_in, runners.size()])
	await shot("storm_horde.png")
	await wait(6.0)
	var seconds := (Time.get_ticks_msec() - watch_from) / 1000.0
	var count: int = spawned[0] - spawned_at_start
	check("about one skeleton every 2 s", count >= int(seconds / 2.0) - 1 and count <= int(seconds / 2.0) + 2, "%d in %.1f s" % [count, seconds])
	check_view("horde view", horde_live())
	print("INFO saw kills while standing still: %d of %d spawned" % [spawned[0] - horde_live().size(), spawned[0]])
	check("no death during the horde (carriers invulnerable)", state() == "playing", state())

	# A death mid-horde: back to Checkpoint2, horde reset, and stepping on again restarts it.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("respawn mid-horde: back at Checkpoint2", cp() == "Checkpoint2" and players()[0].global_position.z > w(0, -6).z - 1.5, cp())
	check("respawn mid-horde: horde reset", not survival.is_running() and horde_live().is_empty(), "live=%d" % horde_live().size())
	check("respawn mid-horde: bridge 1 back up", bridge_y(1) > -2.0, "y=%.2f" % bridge_y(1))
	await cross_to_second_island()
	var restarted: bool = await wait_until(func(): return survival.is_running(), 6.0)
	check("the horde starts again after the respawn", restarted)

	# Clear it: shorten the wave in the driver only, then keep killing until the group reports done.
	survival.fight_duration = 6.0
	var cleared_by := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < cleared_by and not survival.signal_emitted:
		for e in horde_live():
			Health.apply_damage(e, 9999, e.global_position)
		await wait(0.5)
	check("horde cleared", survival.signal_emitted)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("clearing the horde sets Checkpoint3", cp() == "Checkpoint3", cp())
	for i in range(7, 13):
		check("east bridge platform %d raised" % i, bridge_y(i) > -2.0, "y=%.2f" % bridge_y(i))
	await shot("storm_east_bridge.png")

	# Respawn at Checkpoint3: carriers face the east bridge, one north of the other.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	list = players()
	var dx: float = absf(list[0].global_position.x - list[1].global_position.x)
	var dz: float = absf(list[0].global_position.z - list[1].global_position.z)
	check("respawn at Checkpoint3: carriers north and south of each other, facing east", dx < 1.0 and dz >= 5.4 and dz <= 7.1 and list[0].global_position.y > -1.3, "dx=%.1f dz=%.1f" % [dx, dz])
	carry = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	check("respawn at Checkpoint3: both carry the saw", is_instance_valid(carry.main_carrier) and is_instance_valid(carry.secondary_carrier))
	check("respawn at Checkpoint3: horde stays done, east bridge up, bridge 1 down", not survival.is_running() and horde_live().is_empty() and bridge_y(7) > -2.0 and bridge_y(1) < -5.5)
	check("mages stay out of the level before the carriers land", group_enemies("Enemies/MageGroup").is_empty())
	await walk_east("cross the east bridge to the third island", 4.0, 14.0)
	list = players()
	check("both carriers reach the third island", list[0].global_position.x > w(9, 0).x - 1.5 and list[1].global_position.x > w(9, 0).x - 1.5, "x=%.1f/%.1f" % [list[0].global_position.x, list[1].global_position.x])
	await shot("storm_third_island.png")

	# The mages: stepping further onto the island lowers bridge 2 and spawns them, already shooting.
	var fireballs := [0]
	get_tree().node_added.connect(func(n): if n is Fireball: fireballs[0] += 1)
	await arrive_at_mages()
	var mages := group_enemies("Enemies/MageGroup")
	check("six mages appear", mages.size() == 6, str(mages.size()))
	check("the mages are offensive", mages.all(func(e): return e.is_offensive))
	check("mages: normal zoom, every mage can be walked to", focal_count() == 0, str(focal_count()))
	var closed2: bool = await wait_until(func(): return bridge_y(7) < -5.5, 8.0)
	check("bridge 2 lowers behind the carriers", closed2, "y=%.2f" % bridge_y(7))
	print("INFO mages in range at the landing: %d/6" % mages.filter(func(e): return _can_cast_at_a_player(e)).size())
	await wait(3.0)
	await shot("storm_mages.png")
	await overhead("storm_mages_overhead.png")
	place(w(13, -16), w(13, -14))
	await wait(0.5)
	check("from the island's middle all six mages are in range", mages.all(func(e): return _can_cast_at_a_player(e)), "%d/6" % mages.filter(func(e): return _can_cast_at_a_player(e)).size())
	await wait(4.0)
	check("the mages shoot", fireballs[0] >= 3, "%d fireballs" % fireballs[0])
	check_view("mage island middle view", mages, 100.0)
	await shot("storm_mages_middle.png")

	# An edge mage, cut with real input: the carriers straddle it along the edge and walk north into it.
	var north_mage := mage_at(13, -20)
	place(w(14, -17), w(12, -17))
	await wait(0.6)
	list = players()
	lowest[0] = INF
	get_tree().physics_frame.connect(watch)
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var cut: bool = await wait_until(func(): return not north_mage.is_alive(), 5.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	await wait(0.3)
	get_tree().physics_frame.disconnect(watch)
	check("real input: the saw cuts the north mage along its edge", cut)
	check("carriers stay on the island cutting it", lowest[0] > -1.3 and state() == "playing", "lowest y=%.2f" % lowest[0])
	# A corner mage, straddled along the diagonal past the cut corner.
	var corner_mage := mage_at(10, -19)
	var corner := corner_mage.global_position
	place(corner + Vector3(2.2, 0, -2.2), corner + Vector3(-2.2, 0, 2.2))
	var corner_cut: bool = await wait_until(func(): return not corner_mage.is_alive(), 3.0)
	check("the saw reaches a corner mage straddled diagonally", corner_cut)
	check("carriers stand on the island across the corner", players().all(func(p): return p.global_position.y > -1.3) and state() == "playing")

	# A death among the mages: back to Checkpoint3, mages gone until the carriers land again.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("respawn among the mages: back at Checkpoint3", cp() == "Checkpoint3" and players()[0].global_position.x < w(7, 0).x, cp())
	check("respawn among the mages: mages gone, bridge 2 back up", group_enemies("Enemies/MageGroup").is_empty() and bridge_y(7) > -2.0, "mages=%d y=%.2f" % [group_enemies("Enemies/MageGroup").size(), bridge_y(7)])
	await walk_east("cross bridge 2 again", 4.0, 14.0)
	await arrive_at_mages()
	check("the mages appear again, all six", group_enemies("Enemies/MageGroup").size() == 6, str(group_enemies("Enemies/MageGroup").size()))

	check("bridge 3 stays down while mages stand", bridge_y(13) < -5.5, "y=%.2f" % bridge_y(13))
	kill_group("Enemies/MageGroup")
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("killing the mages sets Checkpoint4", cp() == "Checkpoint4", cp())
	for i in range(13, 19):
		check("bridge 3 platform %d raised" % i, bridge_y(i) > -2.0, "y=%.2f" % bridge_y(i))
	await shot("storm_bridge3.png")

	# Respawn at Checkpoint4: facing bridge 3, mages stay dead.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	list = players()
	dx = absf(list[0].global_position.x - list[1].global_position.x)
	dz = absf(list[0].global_position.z - list[1].global_position.z)
	check("respawn at Checkpoint4: carriers north and south of each other on the third island", dx < 1.0 and dz >= 5.4 and dz <= 7.1 and list[0].global_position.x > w(9, 0).x and list[0].global_position.y > -1.3, "dx=%.1f dz=%.1f" % [dx, dz])
	check("respawn at Checkpoint4: mages stay dead, bridge 3 up, bridge 2 down", group_enemies("Enemies/MageGroup").is_empty() and bridge_y(13) > -2.0 and bridge_y(7) < -5.5)

	# (4) The grid horde: the fourth island is a lattice of one-cell walkways.
	var grid_horde := world.get_node("Enemies/SurvivalEnemyGroup2") as SurvivalEnemyGroup
	check("grid horde lasts 60 s in the scene", is_equal_approx(grid_horde.fight_duration, 60.0), str(grid_horde.fight_duration))
	check("grid horde: a skeleton every 3 s, start to end", is_equal_approx(grid_horde.spawn_interval_curve.sample(0.0), 3.0) and is_equal_approx(grid_horde.spawn_interval_curve.sample(1.0), 3.0))
	check("grid horde idle before the carriers arrive", not grid_horde.is_running())
	var grid_spawned := [0]
	world.get_node("Enemies/SurvivalEnemyGroup2/Enemies").child_entered_tree.connect(func(n): if n is EnemyLocal: grid_spawned[0] += 1)
	await arrive("right", "real input: crossing bridge 3 onto the grid starts the horde", func(): return grid_horde.is_running())
	var closed3: bool = await wait_until(func(): return bridge_y(13) < -5.5, 8.0)
	check("bridge 3 lowers behind the carriers", closed3, "y=%.2f" % bridge_y(13))
	check("grid horde: normal zoom", focal_count() == 0, str(focal_count()))
	var grid_from := Time.get_ticks_msec()
	var spawned_before: int = grid_spawned[0]
	var x0: float = players()[0].global_position.x
	var walked: Array = await hold_until(["right"], func(): return players()[0].global_position.x > x0 + 12.0, 5.0)
	check("real input: the pair walks east along two walkways, the disc over the holes", walked[0] and walked[1] > -1.3, "lowest y=%.2f" % walked[1])
	await wait(4.0)
	var grid_runners := grid_horde_live()
	var grid_before := grid_runners.map(func(e): return _player_distance(e))
	await wait(1.5)
	var grid_closed := 0
	for i in grid_runners.size():
		if is_instance_valid(grid_runners[i]) and grid_runners[i].is_alive() and _player_distance(grid_runners[i]) < grid_before[i] - 1.5:
			grid_closed += 1
	check("grid skeletons run at the carriers across the lattice", grid_closed > 0, "%d of %d closed in" % [grid_closed, grid_runners.size()])
	await shot("storm_grid_horde.png")
	await overhead("storm_grid_overhead.png")
	await wait(3.0)
	var grid_seconds := (Time.get_ticks_msec() - grid_from) / 1000.0
	var grid_count: int = grid_spawned[0] - spawned_before
	check("about one grid skeleton every 3 s", grid_count >= int(grid_seconds / 3.0) - 1 and grid_count <= int(grid_seconds / 3.0) + 2, "%d in %.1f s" % [grid_count, grid_seconds])
	check("no grid skeleton fell through a hole", grid_horde_live().all(func(e): return e.global_position.y > -1.5), str(grid_horde_live().map(func(e): return snappedf(e.global_position.y, 0.1))))
	check_view("grid horde view", grid_horde_live())

	# A death mid-horde: back to Checkpoint4, horde reset, landing again restarts it.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("respawn mid grid horde: back at Checkpoint4", cp() == "Checkpoint4", cp())
	check("respawn mid grid horde: horde reset, bridge 3 back up", not grid_horde.is_running() and grid_horde_live().is_empty() and bridge_y(13) > -2.0, "live=%d y=%.2f" % [grid_horde_live().size(), bridge_y(13)])
	await arrive("right", "real input: landing on the grid again restarts the horde", func(): return grid_horde.is_running())
	grid_horde.fight_duration = 6.0
	var grid_cleared_by := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < grid_cleared_by and not grid_horde.signal_emitted:
		for e in grid_horde_live():
			Health.apply_damage(e, 9999, e.global_position)
		await wait(0.5)
	check("grid horde cleared", grid_horde.signal_emitted)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("clearing the grid horde sets Checkpoint5", cp() == "Checkpoint5", cp())
	for i in range(19, 25):
		check("bridge 4 platform %d raised" % i, bridge_y(i) > -2.0, "y=%.2f" % bridge_y(i))
	await shot("storm_bridge4.png")

	# (5) The grid mages, south. Respawn at Checkpoint5: side by side over column 27, facing bridge 4.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	list = players()
	dx = absf(list[0].global_position.x - list[1].global_position.x)
	dz = absf(list[0].global_position.z - list[1].global_position.z)
	check("respawn at Checkpoint5: carriers side by side on the grid", dz < 1.0 and dx >= 5.4 and dx <= 7.1 and list[0].global_position.y > -1.3, "dx=%.1f dz=%.1f" % [dx, dz])
	check("respawn at Checkpoint5: grid horde stays done, bridge 4 up, bridge 3 down", not grid_horde.is_running() and bridge_y(19) > -2.0 and bridge_y(13) < -5.5)
	check("grid mages stay out of the level before the carriers land", group_enemies("Enemies/MageGroup2").is_empty())
	fireballs[0] = 0
	await arrive("down", "real input: crossing bridge 4 south brings the grid mages", func(): return not group_enemies("Enemies/MageGroup2").is_empty())
	var grid_mages := group_enemies("Enemies/MageGroup2")
	check("eight grid mages appear", grid_mages.size() == 8, str(grid_mages.size()))
	check("the grid mages are offensive", grid_mages.all(func(e): return e.is_offensive))
	var closed4: bool = await wait_until(func(): return bridge_y(19) < -5.5, 8.0)
	check("bridge 4 lowers behind the carriers", closed4, "y=%.2f" % bridge_y(19))
	print("INFO grid mages in range at the landing: %d/8" % grid_mages.filter(func(e): return _can_cast_at_a_player(e)).size())
	await overhead("storm_grid_mages_overhead.png")
	# Walk on down columns 26 and 28: the disc runs down column 27 and cuts the mage standing on row 5 there.
	var row_mage := mage_in("Enemies/MageGroup2", 27, 5)
	var in_range_seen := [0]
	var count_in_range := func(): in_range_seen[0] = maxi(in_range_seen[0], grid_mages.filter(func(e): return is_instance_valid(e) and e.is_alive() and _can_cast_at_a_player(e)).size())
	get_tree().physics_frame.connect(count_in_range)
	var down: Array = await hold_until(["down"], func(): return not row_mage.is_alive(), 8.0)
	get_tree().physics_frame.disconnect(count_in_range)
	await shot("storm_grid_mages.png")
	check("real input: walking down two walkways, the disc cuts the mage between them", down[0] and down[1] > -1.3, "lowest y=%.2f" % down[1])
	check("grid mages threaten the walk in", in_range_seen[0] >= 2, "most in range at once: %d" % in_range_seen[0])
	check("the grid mages shoot", fireballs[0] >= 2, "%d fireballs" % fireballs[0])
	# Single file: both carriers on column 30, the disc runs down the walkway itself into the mage at (30, 0).
	var file_mage := mage_in("Enemies/MageGroup2", 30, 0)
	place(w(30, -2), w(30, -4))
	await wait(0.6)
	var file: Array = await hold_until(["down"], func(): return not file_mage.is_alive(), 5.0)
	check("real input: in single file down one walkway, the disc cuts the mage on it", file[0] and file[1] > -1.3, "lowest y=%.2f" % file[1])

	# A death among the grid mages: back to Checkpoint5, mages gone until the carriers land again.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("respawn among the grid mages: back at Checkpoint5", cp() == "Checkpoint5", cp())
	check("respawn among the grid mages: mages gone, bridge 4 back up", group_enemies("Enemies/MageGroup2").is_empty() and bridge_y(19) > -2.0)
	await arrive("down", "real input: landing on the mage grid again", func(): return not group_enemies("Enemies/MageGroup2").is_empty())
	check("the grid mages appear again, all eight", group_enemies("Enemies/MageGroup2").size() == 8, str(group_enemies("Enemies/MageGroup2").size()))
	check("bridge 5 stays down while grid mages stand", bridge_y(25) < -5.5, "y=%.2f" % bridge_y(25))
	kill_group("Enemies/MageGroup2")
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("killing the grid mages sets Checkpoint6", cp() == "Checkpoint6", cp())
	for i in range(25, 31):
		check("bridge 5 platform %d raised" % i, bridge_y(i) > -2.0, "y=%.2f" % bridge_y(i))

	# Respawn at Checkpoint6, facing bridge 5 and the tracks beyond.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	list = players()
	dx = absf(list[0].global_position.x - list[1].global_position.x)
	dz = absf(list[0].global_position.z - list[1].global_position.z)
	check("respawn at Checkpoint6: carriers north and south of each other, facing bridge 5", dx < 1.0 and dz >= 5.4 and dz <= 7.1 and list[0].global_position.y > -1.3, "dx=%.1f dz=%.1f" % [dx, dz])
	check("respawn at Checkpoint6: grid mages stay dead", group_enemies("Enemies/MageGroup2").is_empty())
	# (6) Twin tracks. Both sinking platforms rose with bridge 5; the track mages stand idle on their pillars.
	check("both sinking platforms are up", bridge_y(31) > -2.0 and bridge_y(32) > -2.0, "y=%.2f/%.2f" % [bridge_y(31), bridge_y(32)])
	var track_mages := group_enemies("Enemies/TrackMages")
	check("four track mages stand idle on their pillars", track_mages.size() == 4 and track_mages.all(func(e): return not e.is_offensive and e.global_position.y > -1.3), str(track_mages.map(func(e): return snappedf(e.global_position.y, 0.1))))
	path_ok(w(37, 2), w(69, 2), false, "nav: the tracks aren't in the navmesh")

	# The first track mage stays out of sight from anywhere on the pad, then shows a few steps onto the tracks.
	var first_mage := mage_in("Enemies/TrackMages", 46, 2)
	var seen_from_pad := 0
	for x in [37, 38]:
		place(w(x, 1), w(x, 3))
		await wait(1.3)
		seen_from_pad += visible_count([first_mage])
	await shot("storm_tracks_from_pad.png")
	check("the first track mage is out of sight from the pad", seen_from_pad == 0, "seen from %d of 2 spots" % seen_from_pad)
	place(w(42, 1), w(42, 3))
	await wait(1.3)
	check("a few cells onto the tracks, the first track mage shows", visible_count([first_mage]) == 1)
	await shot("storm_tracks_first_mage.png")
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("back at Checkpoint6 with both platforms up", cp() == "Checkpoint6" and bridge_y(31) > -2.0 and bridge_y(32) > -2.0, "%s y=%.2f/%.2f" % [cp(), bridge_y(31), bridge_y(32)])

	# Single file on one track: the front carrier's step onto the track sinks its platform under the back one.
	place(w(38, 1), w(36, 1))
	await wait(0.6)
	var single: Array = await hold_until(["right"], func(): return bridge_y(31) < -3.0 or state() != "playing", 6.0)
	await wait(1.5)
	check("single file: the first carrier onto track 1 sinks its platform", single[0] and bridge_y(31) < -3.0, "y=%.2f" % bridge_y(31))
	check("single file: the other track's platform stays up", bridge_y(32) > -2.0, "y=%.2f" % bridge_y(32))
	var dropped: bool = await wait_until(func(): return state() != "playing" or players().any(func(p): return p.global_position.y < -2.5), 4.0)
	check("single file: the back carrier drops into the sea", dropped, "state=%s" % state())
	await wait_until(func(): return state() == "playing", 25.0)
	await wait(1.0)
	protect_players()
	check("after the drop: back at Checkpoint6, both platforms up again", cp() == "Checkpoint6" and bridge_y(31) > -2.0 and bridge_y(32) > -2.0, "%s y=%.2f/%.2f" % [cp(), bridge_y(31), bridge_y(32)])
	check("after the drop: the track mages are still idle", group_enemies("Enemies/TrackMages").size() == 4 and group_enemies("Enemies/TrackMages").all(func(e): return not e.is_offensive))

	# The real run: one carrier per track, with real input all the way from the respawn.
	fireballs[0] = 0
	await arrive("right", "real input: both carriers onto the tracks wakes the mages", func(): return group_enemies("Enemies/TrackMages").any(func(e): return e.is_offensive))
	var both_sank: bool = await wait_until(func(): return bridge_y(31) < -3.0 and bridge_y(32) < -3.0, 4.0)
	check("each carrier took its own track (both platforms sank behind them)", both_sank, "y=%.2f/%.2f" % [bridge_y(31), bridge_y(32)])
	list = players()
	check("the carriers stand on rows 1 and 3, the disc over the gap", absf(absf(list[0].global_position.z - list[1].global_position.z) - 6.0) < 1.0)
	await shot("storm_tracks.png")
	var run: Array = await hold_until(["right"], func(): return group_enemies("Enemies/TrackMages").is_empty(), 30.0)
	check("real input: walking the tracks, the disc cuts all four mages", run[0], "left=%d" % group_enemies("Enemies/TrackMages").size())
	check("real input: neither carrier falls off a track", run[1] > -1.3 and state() == "playing", "lowest y=%.2f" % run[1])
	check("the track mages shoot", fireballs[0] >= 1, "%d fireballs" % fireballs[0])
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("killing the track mages sets Checkpoint7", cp() == "Checkpoint7", cp())
	for i in range(33, 39):
		check("bridge 8 platform %d raised" % i, bridge_y(i) > -2.0, "y=%.2f" % bridge_y(i))
	await overhead_at("storm_tracks_overhead.png", Vector3(165, 150, 6), 70.0)

	# Respawn at Checkpoint7, facing bridge 8 to the north pad.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	list = players()
	dx = absf(list[0].global_position.x - list[1].global_position.x)
	dz = absf(list[0].global_position.z - list[1].global_position.z)
	check("respawn at Checkpoint7: carriers north and south of each other on the far pad", dx < 1.0 and dz >= 5.4 and dz <= 7.1 and list[0].global_position.x > w(68, 0).x - 1.5 and list[0].global_position.y > -1.3, "dx=%.1f dz=%.1f" % [dx, dz])
	check("respawn at Checkpoint7: track mages stay dead", group_enemies("Enemies/TrackMages").is_empty())
	# (7) Winding tracks, north of the north pad.
	var north := world.get_node("Level/NorthTracks")
	var centre_line: PackedVector3Array = north.get_meta("centre")
	var west_line: PackedVector3Array = north.get_meta("west")
	var east_line: PackedVector3Array = north.get_meta("east")
	check("north sinking platforms are up", bridge_y(39) > -2.0 and bridge_y(40) > -2.0, "y=%.2f/%.2f" % [bridge_y(39), bridge_y(40)])
	var north_mages := group_enemies("Enemies/NorthMages")
	check("four north mages stand idle on their pillars", north_mages.size() == 4 and north_mages.all(func(e): return not e.is_offensive and e.global_position.y > -1.3))
	var worst_gap := 0.0
	for p in sample_line(west_line):
		worst_gap = maxf(worst_gap, distance_to_line(p, east_line))
	check("every spot on one track has the other within the saw's 7 m", worst_gap <= 7.0, "farthest %.2f m" % worst_gap)
	var east_out: Array = await hold_until(["right"], func(): return players().all(func(p): return p.global_position.x > w(74, 0).x), 8.0)
	check("real input: across bridge 8 onto the north pad", east_out[0] and east_out[1] > -1.3, "lowest y=%.2f" % east_out[1])
	var north_seen := 0
	for row in [1, -1]:
		place(w(75, row), w(77, row))
		await wait(1.3)
		north_seen += visible_count(group_enemies("Enemies/NorthMages"))
	await shot("storm_north_from_pad.png")
	check("no north mage is in sight from the pad", north_seen == 0, "%d sightings" % north_seen)
	fireballs[0] = 0
	var drive: Dictionary = await drive_tracks(west_line, east_line, centre_line, func(): return group_enemies("Enemies/NorthMages").is_empty(), 45.0)
	check("real input: steering along the winding tracks, the disc cuts all four north mages", drive["done"], "left=%d" % group_enemies("Enemies/NorthMages").size())
	check("real input: neither carrier falls off a winding track", drive["lowest"] > -1.3 and state() == "playing", "lowest y=%.2f state=%s" % [drive["lowest"], state()])
	check("the carriers stay on their own tracks", drive["off_track"] <= 0.75, "farthest from a track's middle: %.2f m" % drive["off_track"])
	print("INFO winding run: %.1f s, carrier gap %.2f to %.2f m, ended at %s" % [drive["seconds"], drive["min_gap"], drive["max_gap"], drive["progress"]])
	check("both north platforms sank behind the carriers", bridge_y(39) < -3.0 and bridge_y(40) < -3.0, "y=%.2f/%.2f" % [bridge_y(39), bridge_y(40)])
	check("the north mages shoot", fireballs[0] >= 1, "%d fireballs" % fireballs[0])
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("killing the north mages sets Checkpoint8", cp() == "Checkpoint8", cp())
	for i in range(41, 47):
		check("bridge 11 platform %d raised" % i, bridge_y(i) > -2.0, "y=%.2f" % bridge_y(i))
	await overhead_at("storm_north_overhead.png", Vector3(222, 150, -48), 100.0)

	# Respawn at Checkpoint8, facing bridge 11 and the three tracks beyond.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	list = players()
	dx = absf(list[0].global_position.x - list[1].global_position.x)
	dz = absf(list[0].global_position.z - list[1].global_position.z)
	check("respawn at Checkpoint8: carriers side by side on the north end pad", dz < 1.0 and dx >= 5.4 and dx <= 7.1 and list[0].global_position.z < w(0, -28).z and list[0].global_position.y > -1.3, "dx=%.1f dz=%.1f" % [dx, dz])
	check("respawn at Checkpoint8: north mages stay dead", group_enemies("Enemies/NorthMages").is_empty())
	# (8) Three tracks: the carriers walk the outer two, the disc over the middle one, against a 60 s wave.
	var tri := world.get_node("Enemies/SurvivalEnemyGroup3") as SurvivalEnemyGroup
	check("tri wave lasts 60 s, one skeleton every 10 s", is_equal_approx(tri.fight_duration, 60.0) and is_equal_approx(tri.spawn_interval_curve.sample(0.0), 10.0) and is_equal_approx(tri.spawn_interval_curve.sample(1.0), 10.0))
	check("tri wave idle before the carriers arrive", not tri.is_running())
	var left_x := w(75, 0).x
	var middle_x := w(76, 0).x
	var right_x := w(77, 0).x
	path_ok(w(76, -57), w(75, -37), true, "nav: from the middle track's far end to the left track (via a crossing)")
	path_ok(w(76, -57), w(77, -37), true, "nav: from the middle track's far end to the right track (via a crossing)")
	path_ok(w(75, -37), w(77, -37), true, "nav: left track to right track")
	path_ok(w(76, -36), w(76, -31), false, "nav: the tracks don't join the north end pad (bridges aren't in the navmesh)")
	path_ok(w(76, -50), w(76, -63), false, "nav: the tracks end at bridge 12 (raised bridges aren't in the navmesh)")
	var tri_spawned := [0]
	world.get_node("Enemies/SurvivalEnemyGroup3/Enemies").child_entered_tree.connect(func(n): if n is EnemyLocal: tri_spawned[0] += 1)
	# Nothing but the saw hurts skeletons before the time is up, so every one that dies before then was cut by it.
	# Watched each frame, as a dead skeleton's body stays a while before it leaves the tree.
	var cut_by_saw := [0]
	var spawned_north := [0]
	var counted := {}
	var count_cuts := func():
		for e in world.get_node("Enemies/SurvivalEnemyGroup3/Enemies").get_children():
			if e is not EnemyLocal or counted.has(e.get_instance_id()):
				continue
			if not counted.has(-e.get_instance_id()):
				counted[-e.get_instance_id()] = true
				if e.global_position.z < w(0, -46).z:
					spawned_north[0] += 1
			if not e.is_alive() and tri.get_time_remaining() > 0.0:
				counted[e.get_instance_id()] = true
				cut_by_saw[0] += 1
	get_tree().physics_frame.connect(count_cuts)
	await arrive("up", "real input: from Checkpoint8 north onto the outer tracks starts the wave", func(): return tri.is_running(), 14.0)
	list = players()
	check("the carriers stand on the left and right tracks", list.all(func(p): return absf(p.global_position.x - left_x) < 0.75 or absf(p.global_position.x - right_x) < 0.75) and absf(list[0].global_position.x - list[1].global_position.x) > 5.0, "x=%.1f/%.1f" % [list[0].global_position.x, list[1].global_position.x])
	var closed11: bool = await wait_until(func(): return bridge_y(41) < -5.5, 8.0)
	check("bridge 11 lowers behind the carriers", closed11, "y=%.2f" % bridge_y(41))
	var saw_node := world.get_active_weapon().get_node("WeaponSpecifics/HitBox") as Node3D
	check("the disc hangs over the middle track", absf(saw_node.global_position.x - middle_x) < 0.75, "disc x=%.1f, middle %.1f" % [saw_node.global_position.x, middle_x])
	# Walk north along the outer tracks to row -53, past every crossing. Skeletons spawn at either end of the middle
	# track, at random: those from the far end come down it into the disc; those from the near end can go round it.
	var tri_live := func(): return world.get_node("Enemies/SurvivalEnemyGroup3/Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())
	var crossed := [0]
	var lowest_skeleton := [INF]
	var watch_tri := func():
		for e in tri_live.call():
			lowest_skeleton[0] = minf(lowest_skeleton[0], e.global_position.y)
			if absf(e.global_position.x - middle_x) > 2.0:
				crossed[0] = maxi(crossed[0], 1)
	get_tree().physics_frame.connect(watch_tri)
	var met: Array = await hold_until(["up"], func(): return players()[0].global_position.z < w(0, -53).z, 18.0)
	check("real input: walking the outer tracks, the pair stays on them", met[1] > -1.3 and state() == "playing", "lowest y=%.2f" % met[1])
	await shot("storm_tri_tracks.png")
	await overhead_at("storm_tri_overhead.png", Vector3(229, 150, -140), 90.0)
	# Stand still for the rest of the wave and let the skeletons come.
	var time_up: bool = await wait_until(func(): return tri.get_time_remaining() <= 0.0, 70.0)
	await wait(1.0)
	get_tree().physics_frame.disconnect(watch_tri)
	var left_at_time_up: int = tri_live.call().size()
	check("time up: the wave waits for the remaining skeletons", time_up and (left_at_time_up == 0 or not tri.signal_emitted), "%d left" % left_at_time_up)
	# Then cut down the rest with the saw, wherever they stand: on the middle track the carriers stand on the outer
	# two across from it; on an outer track, on that track and the middle one, staggered so the disc reaches both.
	var outer_cuts := [0]
	var finish_by := Time.get_ticks_msec() + 40000
	while not tri.signal_emitted and Time.get_ticks_msec() < finish_by:
		var alive: Array = tri_live.call()
		if alive.is_empty():
			await wait(0.5)
			continue
		var target: EnemyLocal = alive[0]
		var on_outer: bool = absf(target.global_position.x - middle_x) > 1.5
		await cut_on_tracks(target, left_x, middle_x, right_x)
		if on_outer and not target.is_alive():
			outer_cuts[0] += 1
	check("the remaining skeletons are cut down and the wave clears", tri.signal_emitted, "%d still alive" % tri_live.call().size())
	print("INFO remaining at time up: %d, of which cut on an outer track (staggered stance): %d" % [left_at_time_up, outer_cuts[0]])
	check("six skeletons over the 60 s", tri_spawned[0] == 6 or tri_spawned[0] == 7, str(tri_spawned[0]))
	check("no skeleton fell off the tracks", lowest_skeleton[0] > -2.0, "lowest y=%.2f" % lowest_skeleton[0])
	# How many the parked carriers cut before the time is up depends on where the skeletons spawn (either end of any
	# track, at random), so it's reported, not checked.
	get_tree().physics_frame.disconnect(count_cuts)
	print("INFO tri wave: %d spawned (%d at the far end), %d cut by the saw before the time was up, some skeleton took a crossing: %s" % [tri_spawned[0], spawned_north[0], cut_by_saw[0], "yes" if crossed[0] > 0 else "no"])
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("clearing the tri wave sets Checkpoint9", cp() == "Checkpoint9", cp())
	for i in range(47, 53):
		check("bridge 12 platform %d raised" % i, bridge_y(i) > -2.0, "y=%.2f" % bridge_y(i))

	# Respawn at Checkpoint9, at the tracks' far end, then walk out to the last pad.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	list = players()
	check("respawn at Checkpoint9: one carrier on each outer track", list.all(func(p): return absf(p.global_position.x - left_x) < 0.75 or absf(p.global_position.x - right_x) < 0.75) and list.all(func(p): return p.global_position.y > -1.3), "x=%.1f/%.1f y=%.2f/%.2f" % [list[0].global_position.x, list[1].global_position.x, list[0].global_position.y, list[1].global_position.y])
	check("respawn at Checkpoint9: the wave stays done", not tri.is_running() and tri_live.call().is_empty())
	var out: Array = await hold_until(["up"], func(): return state() == "levelfinished", 8.0)
	check("real input: walking onto the last pad finishes the level", out[0] and out[1] > -1.3, "state=%s lowest y=%.2f" % [state(), out[1]])
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


func sample_line(line: PackedVector3Array, step: float = 0.5) -> Array:
	var out := []
	for i in line.size() - 1:
		var n := maxi(1, int(flat(line[i]).distance_to(flat(line[i + 1])) / step))
		for k in n + 1:
			out.append(flat(line[i]).lerp(flat(line[i + 1]), float(k) / n))
	return out


func distance_to_line(p: Vector2, line: PackedVector3Array) -> float:
	return p.distance_to(closest_on_line(p, line)[1])


## [distance along the line, closest point] for p. The last stretch runs on past the line's end, so progress keeps
## counting once a carrier steps off the end of a track.
func closest_on_line(p: Vector2, line: PackedVector3Array) -> Array:
	var best := INF
	var best_s := 0.0
	var best_point := Vector2.ZERO
	var walked := 0.0
	for i in line.size() - 1:
		var a := flat(line[i])
		var b := flat(line[i + 1])
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, INF if i == line.size() - 2 else 1.0)
		var q := a.lerp(b, t)
		if p.distance_to(q) < best:
			best = p.distance_to(q)
			best_s = walked + a.distance_to(b) * t
			best_point = q
		walked += a.distance_to(b)
	return [best_s, best_point]


## The point that far along the line; past its end, straight on along the last stretch.
func point_along(line: PackedVector3Array, distance: float) -> Vector2:
	for i in line.size() - 1:
		var a := flat(line[i])
		var b := flat(line[i + 1])
		if distance <= a.distance_to(b) or i == line.size() - 2:
			return a + (b - a).normalized() * distance
		distance -= a.distance_to(b)
	return flat(line[line.size() - 1])


func line_length(line: PackedVector3Array) -> float:
	var total := 0.0
	for i in line.size() - 1:
		total += flat(line[i]).distance_to(flat(line[i + 1]))
	return total


## Steers each carrier along its own track with real input, the way a player would: aim at a point a little ahead
## on the track and press the nearest of the eight directions. A carrier more than a metre ahead of the other, measured
## along the centre line, waits for it. Runs until `done` holds and both are past the tracks' end, or `timeout`.
func drive_tracks(west_line: PackedVector3Array, east_line: PackedVector3Array, centre_line: PackedVector3Array, done: Callable, timeout: float) -> Dictionary:
	var list := players()
	var west: PlayerLocal = list[0] if list[0].global_position.x < list[1].global_position.x else list[1]
	var east: PlayerLocal = list[1] if west == list[0] else list[0]
	var lines := {west: west_line, east: east_line}
	var finish := line_length(centre_line) + 1.5
	var stats := {"lowest": INF, "off_track": 0.0, "min_gap": INF, "max_gap": 0.0, "done": false, "seconds": 0.0}
	var started := Time.get_ticks_msec()
	var deadline := started + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if state() != "playing":
			break
		var progress := {}
		for p in [west, east]:
			progress[p] = closest_on_line(flat(p.global_position), centre_line)[0]
		var both_past: bool = progress[west] >= finish and progress[east] >= finish
		if both_past and done.call():
			stats["done"] = true
			break
		stats["min_gap"] = minf(stats["min_gap"], flat(west.global_position).distance_to(flat(east.global_position)))
		stats["max_gap"] = maxf(stats["max_gap"], flat(west.global_position).distance_to(flat(east.global_position)))
		for p in [west, east]:
			var other: PlayerLocal = east if p == west else west
			stats["lowest"] = minf(stats["lowest"], p.global_position.y)
			var on_line: Array = closest_on_line(flat(p.global_position), lines[p])
			var on_track: bool = progress[p] > 0.5 and progress[p] < finish - 1.5
			if on_track:
				stats["off_track"] = maxf(stats["off_track"], flat(p.global_position).distance_to(on_line[1]))
			var waiting: bool = progress[p] - progress[other] > 1.0
			var aim := point_along(lines[p], on_line[0] + 1.8) - flat(p.global_position)
			_steer(p, Vector2.ZERO if waiting else aim.normalized())
	for p in [west, east]:
		_steer(p, Vector2.ZERO)
	stats["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	stats["progress"] = "west %.1f, east %.1f of %.1f m" % [closest_on_line(flat(west.global_position), centre_line)[0], closest_on_line(flat(east.global_position), centre_line)[0], finish]
	return stats


## Presses the directions nearest to `dir` (x east, y south): one or two of the four, or none.
func _steer(p: PlayerLocal, dir: Vector2) -> void:
	for pair in [[p.action_right, dir.x > 0.38], [p.action_left, dir.x < -0.38], [p.action_down, dir.y > 0.38], [p.action_up, dir.y < -0.38]]:
		if pair[1]:
			Input.action_press(pair[0])
			continue
		Input.action_release(pair[0])


## An overhead shot centred on `centre`, `size` metres tall.
func overhead_at(file_name: String, centre: Vector3, size: float) -> void:
	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = size
	top.far = 400.0
	top.position = centre
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot(file_name)
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()


## Places the carriers, saw in hand, so the disc covers this skeleton: across from it on the two outer tracks if it's
## on the middle one; otherwise on its track and the middle one, 2.7 m either side of it along them (5.85 m apart, the
## disc halfway, 1.5 m from both tracks' middles). Then waits for it to die, a few seconds at most.
func cut_on_tracks(target: EnemyLocal, left_x: float, middle_x: float, right_x: float) -> void:
	var z := clampf(target.global_position.z, w(0, -57).z, w(0, -36).z)
	var tx := target.global_position.x
	if absf(tx - middle_x) <= 1.5:
		place(Vector3(left_x, -1.0, z), Vector3(right_x, -1.0, z))
	else:
		var outer_x := left_x if tx < middle_x else right_x
		place(Vector3(outer_x, -1.0, z + 2.7), Vector3(middle_x, -1.0, z - 2.7))
	await wait_until(func(): return not target.is_alive(), 4.0)
	await wait(0.3)


func grid_horde_live() -> Array:
	return world.get_node("Enemies/SurvivalEnemyGroup2/Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


## Holds a direction ("up", "down", "left" or "right") for both carriers until cond holds or timeout.
## Returns [cond held, lowest carrier y meanwhile].
func hold_until(directions: Array, cond: Callable, timeout: float) -> Array:
	var list := players()
	var actions := []
	for d in directions:
		for p in list:
			actions.append(p.get("action_" + d))
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	for a in actions:
		Input.action_press(a)
	var ok: bool = await wait_until(cond, timeout)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame
	get_tree().physics_frame.disconnect(watch)
	return [ok, lowest[0]]


## Walks the pair in a direction, with real input, until a landing trigger fires (cond).
func arrive(direction: String, label: String, cond: Callable, timeout: float = 8.0) -> void:
	var result: Array = await hold_until([direction], cond, timeout)
	check(label, result[0] and result[1] > -1.3 and state() == "playing", "lowest y=%.2f" % result[1])
	await wait(0.5)


func mage_in(group: String, cx: int, cz: int) -> EnemyLocal:
	for e in group_enemies(group):
		var d: Vector3 = e.global_position - w(cx, cz)
		if Vector2(d.x, d.z).length() < 1.0:
			return e
	return null


func mage_at(cx: int, cz: int) -> EnemyLocal:
	for e in group_enemies("Enemies/MageGroup"):
		var d: Vector3 = e.global_position - w(cx, cz)
		if Vector2(d.x, d.z).length() < 1.0:
			return e
	return null


## Keeps walking the pair east, with real input, until the mages appear (both carriers inside the landing trigger).
func arrive_at_mages() -> void:
	var list := players()
	Input.action_press(list[0].action_right)
	Input.action_press(list[1].action_right)
	var arrived: bool = await wait_until(func(): return not group_enemies("Enemies/MageGroup").is_empty(), 4.0)
	Input.action_release(list[0].action_right)
	Input.action_release(list[1].action_right)
	check("real input: stepping onto the third island brings the mages", arrived, "x=%.1f/%.1f" % [list[0].global_position.x, list[1].global_position.x])
	await wait(0.5)
