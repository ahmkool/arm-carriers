extends Node
## Test driver for world_local_frost_golem_boss.tscn. Copy it for a new level: keep the helpers, rewrite _run().
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


# ---- Frost Golem helpers. ----

## Like strike_test, but for a target that survives a hit: dashes until its health drops once.
func strike_until_hit(enemy: EnemyLocal) -> void:
	var start_hp: int = enemy.get_node("Health").current_hp
	var sword := world.get_active_weapon()
	var blade_mid: Vector3 = (sword.get_node("WeaponSpecifics/HitArea/CollisionShape3D") as Node3D).global_position
	var spot: Vector3 = blade_mid + Vector3.RIGHT * 2.0
	spot.y = enemy.global_position.y
	enemy.global_position = spot
	await get_tree().physics_frame
	var list := players()
	for attempt in 3:
		Input.action_press(list[0].action_right)
		Input.action_press(list[1].action_right)
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_press(list[0].action_dash)
		Input.action_press(list[1].action_dash)
		await wait(0.2)
		Input.action_release(list[0].action_dash)
		Input.action_release(list[1].action_dash)
		Input.action_release(list[0].action_right)
		Input.action_release(list[1].action_right)
		await wait(0.6)
		if enemy.get_node("Health").current_hp < start_hp:
			return

var moves_seen: Array = []


func boss() -> EnemyLocal:
	var alive := group_enemies("Enemies/BossGroup")
	return alive[0] if not alive.is_empty() else null


func boss_hp() -> int:
	return boss().get_node("Health").current_hp


func floor_grid() -> GridMap:
	return world.get_node("Level/NavigationRegion3D/GridMapFloor") as GridMap


func ice_cells() -> int:
	var grid := floor_grid()
	var count := 0
	for cell in grid.get_used_cells():
		if cell.y != -1:
			continue
		if grid.mesh_library.get_item_name(grid.get_cell_item(cell)).begins_with("Ice_"):
			count += 1
	return count


func frost() -> FrostGround:
	return boss().get_node("FrostGround") as FrostGround


## Records every move the golem starts, from its behavior's intent when it enters the Attacking state.
func watch_moves() -> void:
	var golem := boss()

	get_tree().physics_frame.connect(func():
		if not is_instance_valid(golem) or not golem.is_alive():
			return
		var attacking: bool = golem.enemy_state_machine.is_in_state("attacking")
		var move: StringName = golem.behavior.intent.requested_attack
		if attacking and (moves_seen.is_empty() or moves_seen[-1] != move or not _was_attacking[0]):
			moves_seen.append(move)
		_was_attacking[0] = attacking
	)

var _was_attacking := [false]


## Puts both carriers `distance` metres in front of the golem, along its facing, and waits for a move.
func stand_at(distance: float) -> void:
	var golem := boss()
	var to_spawn := Vector3(0, 0, 1)
	var spot := golem.global_position + to_spawn * distance
	place(spot + Vector3(0, 0, 2.6), spot)


func wait_for_move(move: StringName, timeout: float) -> bool:
	var before := moves_seen.size()
	return await wait_until(func(): return moves_seen.slice(before).has(move), timeout)


func spikes_in_flight() -> Array:
	return world.get_children().filter(func(c): return c.scene_file_path.ends_with("frost_spike.tscn"))


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.5)
	await shot("golem_start.png")
	print("INFO fps at start: ", Engine.get_frames_per_second())
	var golem := boss()
	check("the Frost Golem waits, at full health", golem != null and not golem.is_offensive and boss_hp() == 54, "hp=%d" % boss_hp())
	var authored_ice := ice_cells()
	print("INFO authored ice cells: ", authored_ice)

	# A real sword strike, from the spawn, before the fight: the golem is brought to the blade while it waits.
	protect_players()
	var hp_before := boss_hp()
	await strike_until_hit(golem)
	check("real dash: a sword hit takes 3 HP off the golem", boss_hp() == hp_before - 3, "%d -> %d" % [hp_before, boss_hp()])
	golem.global_position = w(0, -15)
	golem.get_node("Health").reset_to_full()
	await wait(0.5)

	# Walk into the arena: the bridge sinks behind and the golem wakes.
	var list := players()
	move_players(w(0, -7))
	await wait(0.5)
	await hold([list[0].action_up, list[1].action_up], 1.2)
	var woke: bool = await wait_until(func(): return boss().is_offensive, 4.0)
	check("entering the arena wakes the golem", woke)
	var sank: bool = await wait_until(func(): return bridge_y(1) < -2.0, 6.0)
	check("the bridge sinks behind the carriers", sank, "y=%.2f" % bridge_y(1))
	var bar := world.get_node_or_null("UI/BossHealthBar")
	print("INFO boss bar node: ", bar)
	watch_moves()
	protect_players()

	# Mid range: a slam, which freezes the floor around it.
	stand_at(5.0)
	var slammed: bool = await wait_for_move(&"slam", 10.0)
	check("at mid range the golem slams", slammed, str(moves_seen))
	await wait(1.6)
	await shot("golem_slam.png")
	var frozen := ice_cells() - authored_ice
	check("the slam freezes the floor around it", frozen >= 8, "%d cells frozen" % frozen)
	list = players()
	var spot: Vector3 = (boss().get_node("SlamPoint") as Node3D).global_position
	move_players(Vector3(spot.x, 0, spot.z + 2.0))
	await wait(0.6)
	check("frozen floor is slippery underfoot", list[1].is_on_ice() or list[0].is_on_ice())
	var thawed: bool = await wait_until(func(): return ice_cells() == authored_ice, 14.0)
	check("frozen floor thaws back to the authored ice", thawed, "%d vs %d" % [ice_cells(), authored_ice])

	# Long range: lines of ice spikes.
	stand_at(13.0)
	var spiked: bool = await wait_for_move(&"spikes", 12.0)
	check("at long range the golem sends ice spikes", spiked, str(moves_seen))
	var rose: bool = await wait_until(func(): return spikes_in_flight().size() >= 3, 4.0)
	check("a line of spikes rises toward the carriers", rose, "%d spikes" % spikes_in_flight().size())
	await wait(0.4)
	await shot("golem_spikes.png")

	# Close range: an axe sweep.
	stand_at(3.0)
	var swept: bool = await wait_for_move(&"sweep", 10.0)
	check("up close the golem sweeps its axe", swept, str(moves_seen))
	await wait(0.6)
	check("the sweep's hit box is live mid-swing", boss().get_node("SweepHitBox").monitoring)
	await shot("golem_sweep.png")

	# A slam is lethal: unprotected carriers inside the ring.
	for p in players():
		p.get_node("Health").reset_to_full()

	await wait_until(func(): return not boss().enemy_state_machine.is_in_state("attacking"), 4.0)
	stand_at(4.8)
	var dead_now: bool = await wait_until(func(): return state() == "gameoverlost", 14.0)
	check("standing in the slam's ring is a game over", dead_now, "moves %s" % str(moves_seen.slice(-3)))
	await wait_until(func(): return state() == "playing", 15.0)
	await wait(1.0)
	golem = boss()
	check("respawn resets the golem: waiting, full health", golem != null and not golem.is_offensive and boss_hp() == 54, "hp=%d" % (boss_hp() if golem else -1))
	check("respawn thaws all frozen ground", ice_cells() == authored_ice, "%d vs %d" % [ice_cells(), authored_ice])
	check("respawn raises the bridge again", bridge_y(1) > -2.0, "y=%.2f" % bridge_y(1))

	# Phase 2: down to half health it roars and fans its spikes three ways.
	protect_players()
	list = players()
	move_players(w(0, -7))
	await wait(0.5)
	await hold([list[0].action_up, list[1].action_up], 1.2)
	await wait_until(func(): return boss().is_offensive, 4.0)
	moves_seen.clear()
	watch_moves()
	Health.apply_damage(boss(), 27, boss().global_position)
	var roared: bool = await wait_for_move(&"roar", 6.0)
	check("at half health the golem roars", roared, str(moves_seen))
	check("enraged, it fans its spikes in three lines", boss().behavior.get_spike_lines() == 3)
	stand_at(13.0)
	await wait_for_move(&"spikes", 12.0)
	var most := [0]
	var count_spikes := func(): most[0] = maxi(most[0], spikes_in_flight().size())
	get_tree().physics_frame.connect(count_spikes)
	await wait(2.6)
	await shot("golem_enraged_spikes.png")
	await wait(0.6)
	get_tree().physics_frame.disconnect(count_spikes)
	check("an enraged volley rises in more than one line", most[0] > 6, "%d spikes at once" % most[0])

	# Death ends the level and thaws the ground.
	Health.apply_damage(boss(), 999, boss().global_position)
	var won: bool = await wait_until(func(): return state() == "levelfinished", 8.0)
	check("defeating the golem finishes the level", won, state())
	check("its death thaws the ground", ice_cells() == authored_ice, "%d vs %d" % [ice_cells(), authored_ice])
	print("INFO moves seen: ", moves_seen)
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
