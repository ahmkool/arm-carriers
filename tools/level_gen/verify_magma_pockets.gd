extends Node
## Test driver for the magma pockets in world_local_lava.tscn. The helpers are verify_lava_prototype.gd's.
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



# ---- Magma pockets. ----
const EXPLOSION := preload("res://src/vfx/explosion.tscn")

var pocket_burns: Array = []


func pockets() -> Array:
	return world.get_node("Level/Pockets").get_children()


func pocket_at(cx: int, cz: int) -> LavaVent:
	for pocket in pockets():
		if pocket.global_position.distance_to(w(cx, cz, -1.0)) < 0.5:
			return pocket
	return null


## What a bomb or rocket leaves behind where it lands.
func explode_at(at: Vector3) -> void:
	var explosion := EXPLOSION.instantiate() as Node3D
	world.add_child(explosion)
	explosion.global_position = at


func bursting(list: Array) -> Array:
	return list.filter(func(p): return p.is_erupting())


func watch_pocket_burns() -> void:
	for pocket in pockets():
		pocket.burned.connect(func(body):
			if body is PlayerLocal:
				pocket_burns.append(body.name)
		)


## Records every pocket that bursts until the time is up.
func record_bursts(seconds: float) -> Array:
	var seen: Array = []
	var watch := func():
		for p in pockets():
			if p.is_erupting() and not seen.has(p):
				seen.append(p)
	get_tree().physics_frame.connect(watch)
	await wait(seconds)
	get_tree().physics_frame.disconnect(watch)
	return seen


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	watch_pocket_burns()
	protect_players()
	await wait(1.0)
	check("the forge has 17 magma pockets, all armed", pockets().size() == 17 and pockets().all(func(p): return p.is_armed()), str(pockets().size()))

	# Nothing but an explosion sets them off, not even the vents erupting nearby.
	kill_group("Enemies/EnemyGroup")
	await clear_and_wait("Enemies/EnemyGroup", "Checkpoint2", 1)
	place_side_by_side(w(0, -16))
	await wait(1.5)
	await shot("pockets_field.png")
	var quiet: Array = await record_bursts(5.0)
	check("pockets stay quiet while the vents around them cycle", quiet.is_empty(), "%d burst" % quiet.size())
	var guards := group_enemies("Enemies/EnemyGroup2")
	check("guards stand on the pockets without burning", guards.size() == 7, str(guards.size()))

	# One explosion on a pocket at the end of the field: it bursts and sets off its neighbour two cells away.
	var west_guard: EnemyLocal = guards.filter(func(g): return Vector2(g.global_position.x - w(-2, -23).x, g.global_position.z - w(-2, -23).z).length() < 0.5)[0]
	var bomb_spot := w(-4, -23)
	check("the neighbour's guard is out of the blast itself", Vector2(bomb_spot.x - west_guard.global_position.x, bomb_spot.z - west_guard.global_position.z).length() > 4.0)
	explode_at(bomb_spot)
	await wait(0.65)
	await shot("pockets_chain_field.png")
	var field_burst: Array = await record_bursts(2.0)
	check("the bombed pocket and its neighbour burst", field_burst.has(pocket_at(-4, -23)) and field_burst.has(pocket_at(-2, -23)), "%d burst" % field_burst.size())
	check("the chain stops at the gap around the checkpoint", not field_burst.has(pocket_at(2, -23)) and not field_burst.has(pocket_at(4, -23)))
	check("the chained burst burns the guard on the neighbour", not is_instance_valid(west_guard) or not west_guard.is_alive())
	check("a burst pocket is spent", not pocket_at(-4, -23).is_armed())
	await wait(10.0)
	check("then it re-arms", pocket_at(-4, -23).is_armed())

	# A chain runs back into careless carriers.
	pocket_burns.clear()
	var east := pocket_at(2, -23)
	var spot := east.global_position
	spot.y = 0.0
	place(spot + Vector3(0.5, 0, 0), spot + Vector3(-0.5, 0, 0))
	await wait(0.3)
	explode_at(w(4, -23))
	await wait(1.6)
	check("a chain reaching the carriers burns them", pocket_burns.size() >= 1, str(pocket_burns))

	# The caldera's far rim: one explosion takes the whole row of five.
	kill_group("Enemies/EnemyGroup2")
	await clear_and_wait("Enemies/EnemyGroup2", "Checkpoint3", 7)
	place_side_by_side(w(0, -29))
	await wait(3.0)
	var rim := [pocket_at(-4, -39), pocket_at(-2, -39), pocket_at(0, -39), pocket_at(2, -39), pocket_at(4, -39)]
	place_side_by_side(w(0, -35) + Vector3(0, 0, 0))
	explode_at(w(-4, -39))
	var rim_burst: Array = await record_bursts(4.0)
	check("one explosion runs the whole caldera rim", rim.all(func(p): return rim_burst.has(p)), "%d burst" % rim_burst.size())
	check("the flank pockets are too far to join", not rim_burst.has(pocket_at(-6, -37)) and not rim_burst.has(pocket_at(6, -37)))

	# The forge's back row, photographed armed.
	kill_group("Enemies/EnemyGroup3")
	await clear_and_wait("Enemies/EnemyGroup3", "Checkpoint4", 11)
	place_side_by_side(w(0, -53))
	await wait(1.5)
	await shot("pockets_forge.png")
	explode_at(w(-6, -58))
	await wait(1.3)
	await shot("pockets_chain_forge.png")
	print("INFO fps: ", Engine.get_frames_per_second())
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
