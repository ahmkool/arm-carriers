extends Node
## Test driver for world_local_sky_station.tscn: board the hover barge, the mechs fly in, the barge holds until they
## die, then docks at the end island. Also a death mid-voyage, and real fork-cannon fire at the mechs: bolts that
## lock on, then a homing missile from the front carrier.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_sky_station.gd res://src/world/levels/world_local_sky_station.tscn <out_dir> 240

const CELL := 2.999
const WAVE := "Enemies/MechWave"
## World (x, z) of the barge's stops, matching build_sky_station.py: parked = dock, fight, final dock.
const STOPS := [Vector2(1.5, -14.997), Vector2(1.5, -14.997), Vector2(4.5, -32.988), Vector2(1.5, -50.979)]

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	_bind_world()
	get_tree().create_timer(220.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func _bind_world() -> void:
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func info(text: String) -> void:
	print("INFO " + text)


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


func w(cx: float, cz: float, y: float = 0.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func barge() -> RotorBarge:
	return world.get_node("Level/Barge") as RotorBarge


func barge_at(stop: int) -> bool:
	var at: Vector3 = barge().body.global_position
	return Vector2(at.x, at.z).distance_to(STOPS[stop]) < 0.1


func mechs() -> Array:
	return world.get_node(WAVE).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func stowed(enemies: Array) -> bool:
	return enemies.all(func(e): return not e.visible and e.process_mode == Node.PROCESS_MODE_DISABLED)


func active(enemies: Array) -> bool:
	return enemies.all(func(e): return e.visible and e.process_mode == Node.PROCESS_MODE_INHERIT)


func aboard(node: Node3D) -> bool:
	return barge().deck.contains(node.global_position)


func on_screen(node: Node3D, height: float = 1.0) -> bool:
	var cam := get_viewport().get_camera_3d()
	var pos := node.global_position + Vector3.UP * height
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos))


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


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)


## Walks both carriers north with real input until both stand well inside the barge deck.
func board_barge() -> bool:
	var list := players()
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var on: bool = await wait_until(func(): return players().all(func(p): return barge().deck.contains(p.global_position, 2.5)), 10.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	await wait(0.3)
	return on and players().all(aboard)


## Real bolt fire from the fork cannon, the way a player would use it with carriers holding still: short bursts whenever a mech
## circles into the line of fire. Returns [hits, bursts]. The carriers don't turn to aim, so this shows the gun can
## reach a hovering mech, not how easy aiming is.
func fire_at_mechs(seconds: float) -> Array:
	var hits := [0]
	var count := func(_amount: int, _remaining: int, _source: Vector3): hits[0] += 1
	for m in mechs():
		m.get_node("Health").damaged.connect(count)
	var shooter := carriers()[0]
	var bursts := 0
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and hits[0] == 0:
		if not await wait_until(_mech_in_line_of_fire, maxf((deadline - Time.get_ticks_msec()) / 1000.0, 0.0)):
			break
		bursts += 1
		await hold([shooter.action_shoot], 0.8)
		await wait(0.6)
	for m in mechs():
		if m.get_node("Health").damaged.is_connected(count):
			m.get_node("Health").damaged.disconnect(count)
	return [hits[0], bursts]


func _mech_in_line_of_fire() -> bool:
	var muzzle: Marker3D = world.get_active_weapon().get_node("WeaponSpecifics").muzzle
	var forward := Vector2(muzzle.global_basis.z.x, muzzle.global_basis.z.z).normalized()
	for m in mechs():
		var to := Vector2(m.global_position.x - muzzle.global_position.x, m.global_position.z - muzzle.global_position.z)
		if to.length() < 16.0 and absf(forward.angle_to(to)) < deg_to_rad(20.0):
			return true
	return false


func cannon() -> ForkCannonSpecifics:
	return world.get_active_weapon().get_node("WeaponSpecifics") as ForkCannonSpecifics


## [back carrier, front carrier], from the weapon's own carry info.
func carriers() -> Array[PlayerLocal]:
	var carry_info: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	return [carry_info.main_carrier, carry_info.secondary_carrier]


## Real fire with both barrels: bursts from the back carrier until a mech is locked, then the front carrier's shoot
## button. Returns [locked, launched, the locked mech died to the missile].
func lock_and_launch(seconds: float) -> Array:
	var back := carriers()[0]
	var front := carriers()[1]
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline and cannon().get_locked_target() == null:
		if not await wait_until(_mech_in_line_of_fire, maxf((deadline - Time.get_ticks_msec()) / 1000.0, 0.0)):
			break
		await hold([back.action_shoot], 0.8)
	return await _launch_at_lock(front)


## Paints the nearest mech by script, as if four bolts had hit it, wherever it is. Then the front carrier's real
## shoot button, so the missile has to steer to reach it.
func scripted_lock_and_launch() -> Array:
	var target: EnemyLocal = null
	for m in mechs():
		if target == null or m.global_position.distance_to(_players_middle()) < target.global_position.distance_to(_players_middle()):
			target = m
	if target == null:
		return [false, false, false]
	for i in ForkCannonSpecifics.HITS_TO_LOCK:
		cannon()._on_bolt_hit_enemy(target)
	await wait_until(func(): return cannon().is_missile_loaded(), 3.0)
	return await _launch_at_lock(carriers()[1])


func _launch_at_lock(front: PlayerLocal) -> Array:
	var target := cannon().get_locked_target()
	if target == null:
		return [false, false, false]
	var launched := [null]
	var on_launch := func(missile: ForkMissile): launched[0] = missile
	cannon().missile_fired.connect(on_launch)
	await hold([front.action_shoot], 0.1)
	cannon().missile_fired.disconnect(on_launch)
	var missile: ForkMissile = launched[0]
	if missile == null:
		return [true, false, false]
	info("missile launched homing=%s at %s" % [missile.has_target(), target.name])
	await wait(0.5)
	await shot("05b_missile.png")
	var died: bool = await wait_until(func(): return not is_instance_valid(target) or not target.is_alive(), 4.0)
	return [true, true, died]


func kill_mechs() -> void:
	for m in mechs():
		Health.apply_damage(m, 9999, m.global_position)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.5)
	check("both carriers on the station floor", lowest_player_y() > -1.6, "lowest y=%.2f" % lowest_player_y())
	check("carrying the fork cannon", world.get_active_weapon() != null and world.get_active_weapon().scene_file_path.ends_with("fork_cannon.tscn"))
	check("the barge waits at the station's dock", barge_at(1) and not barge().is_moving(), str(barge().body.global_position))
	check("two mechs wait out of sight", mechs().size() == 2 and stowed(mechs()), "%d mechs" % mechs().size())
	check("both carriers on screen at the spawn", players().all(on_screen))
	await shot("01_spawn.png")
	await wait(1.0)
	check("the barge doesn't leave without the carriers", barge_at(1) and not barge().is_moving())

	# ---- First crossing: board, mechs arrive, then a death mid-fight. ----
	check("real input: walking north boards the barge", await board_barge())
	var left: bool = await wait_until(func(): return barge().is_moving() and barge().target_stop() == 2, 3.0)
	check("boarding sets the barge off", left)
	await shot("02_departing.png")
	var flying_in: bool = await wait_until(func(): return mechs().any(func(m): return m.visible), 6.0)
	check("the mechs appear once the barge is under way", flying_in and barge().is_moving())
	await wait(0.6)
	await shot("03_mechs_flying_in.png")
	var arrived: bool = await wait_until(func(): return active(mechs()), 6.0)
	check("both mechs arrive and switch on", arrived and mechs().all(func(m): return m.is_offensive))
	var hover_gap := []
	for m in mechs():
		hover_gap.append("%.1f" % (m.global_position.y - barge().body.global_position.y))
	info("mech heights above the deck on arrival: %s" % str(hover_gap))
	check("gameplay: the carriers rode it out without falling", players().all(aboard) and state() == "playing", state())

	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("after a death the barge is back at its dock", barge_at(1) and not barge().is_moving(), str(barge().body.global_position))
	check("after a death both mechs are back, out of sight", mechs().size() == 2 and stowed(mechs()) and mechs().all(func(m): return not m.is_offensive), "%d mechs" % mechs().size())

	# ---- Second crossing, all the way. ----
	check("real input: boarding again", await board_barge())
	await wait_until(func(): return active(mechs()), 12.0)
	var holding: bool = await wait_until(func(): return barge_at(2) and not barge().is_moving(), 15.0)
	check("the barge holds mid-air at the fight stop", holding, str(barge().body.global_position))
	var states := {}
	var mech_seen := [0, 0]
	var players_seen := [0, 0]
	var lowest := [INF]
	var watch := func():
		for m in mechs():
			states[String(m.enemy_state_machine.current_state.name).to_lower()] = true
	get_tree().physics_frame.connect(watch)
	for i in 8:
		await wait(1.0)
		for m in mechs():
			mech_seen[1] += 1
			mech_seen[0] += 1 if on_screen(m, 1.2) else 0
			var off: Vector3 = m.global_position - _players_middle()
			info("t=%d %s %s offset=(%.1f, %.1f, %.1f) on_screen=%s" % [i, m.name, m.enemy_state_machine.current_state.name, off.x, off.y, off.z, on_screen(m, 1.2)])
		players_seen[1] += 2
		players_seen[0] += players().filter(on_screen).size()
		lowest[0] = minf(lowest[0], lowest_player_y())
		if i == 2:
			await shot("04_fight.png")
		if i == 5:
			await shot("05_fight.png")
	get_tree().physics_frame.disconnect(watch)
	info("mech states seen while holding: %s" % str(states.keys()))
	check("the mechs attack: gun and dash", states.has("shooting") and states.has("dashing"), str(states.keys()))
	check("the barge keeps holding while they live", barge_at(2) and not barge().is_moving() and mechs().size() > 0)
	check("carriers stay on screen during the fight", players_seen[0] == players_seen[1], "%d/%d" % players_seen)
	check("mechs are on screen most of the fight", mech_seen[0] >= mech_seen[1] * 0.7, "%d/%d samples" % mech_seen)
	check("carriers stay aboard during the fight", players().all(aboard) and state() == "playing", state())

	var fired: Array = await fire_at_mechs(20.0)
	info("real bolt fire: %d hits after %d bursts at mechs in the line of fire, %d of 2 still alive" % [fired[0], fired[1], mechs().size()])
	if fired[1] == 0:
		info("no mech crossed the line of fire of the still carriers in 20 s, so real fire was not tried this run")
	if fired[1] > 0:
		check("real fire: the bolts hit a mech in its line of fire", fired[0] > 0, "%d hits, %d bursts" % fired)
	var strike: Array = await lock_and_launch(25.0)
	info("lock and launch: locked=%s launched=%s killed=%s" % strike)
	if not strike[0]:
		info("no mech stayed in the line of fire long enough to lock this run, so the lock is painted by script")
		strike = await scripted_lock_and_launch()
		info("scripted lock, real launch: locked=%s launched=%s killed=%s" % strike)
	if strike[0]:
		check("real fire: the front carrier's button launches a missile at the lock", strike[1])
		check("real fire: the homing missile downs the locked mech", strike[2])
	kill_mechs()
	await wait(0.2)
	var onward: bool = await wait_until(func(): return barge().is_moving() and barge().target_stop() == 3, 3.0)
	check("downing both mechs sends the barge on", onward)
	await wait(1.5)
	await shot("06_onward.png")
	var docked: bool = await wait_until(func(): return barge_at(3) and not barge().is_moving(), 20.0)
	check("the barge docks at the end island", docked and players().all(aboard), str(barge().body.global_position))
	check("carriers on screen at the end dock", players().all(on_screen))
	await shot("07_end_dock.png")
	var list := players()
	await hold([list[0].action_up, list[1].action_up], 2.6)
	await wait(1.0)
	check("real input: walking off into the end area finishes the level", state() == "levelfinished", "%s, lowest y=%.2f" % [state(), lowest_player_y()])
	await shot("08_finished.png")

	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
