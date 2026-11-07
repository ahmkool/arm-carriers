extends Node
## Test driver for world_local_rotor_decks.tscn. Copy it for a new level: keep the helpers, rewrite _run().
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
	get_tree().create_timer(600.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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
	var in_range := group_enemies("Enemies/EnemyGroup3").filter(_can_cast_at_a_player)
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


func ferry_z(index: int) -> float:
	return (world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D" % index) as Node3D).global_position.z


func near_dock_z(index: int) -> float:
	return (world.get_node("Level/Bridges/BridgePlatform%d" % index) as Node3D).global_position.z + 4.0 * CELL


func far_dock_z(index: int) -> float:
	return (world.get_node("Level/Bridges/BridgePlatform%d" % index) as Node3D).global_position.z


func clear_and_call(group: String, expected_cp: String, ferry: int) -> void:
	kill_group(group)
	await wait(1.5)
	await shot("decks_ferry%d_called.png" % ferry)
	var docked: bool = await wait_until(func(): return absf(ferry_z(ferry) - near_dock_z(ferry)) < 0.1, 9.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(0.5)
	check(group.get_file() + " cleared sets " + expected_cp, cp() == expected_cp, cp())
	check("ferry %d comes to the near dock" % ferry, docked, "z=%.1f, dock=%.1f" % [ferry_z(ferry), near_dock_z(ferry)])


## Real walking from the deck onto the docked ferry, which starts when both are aboard. Standing still, they ride it.
func board_and_ride(ferry: int, label: String, on_the_way: Callable) -> void:
	var list := players()
	var start := Vector3(1.5, 0, near_dock_z(ferry) + 8.0)
	move_players(start)
	await wait(0.6)
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var left: bool = await wait_until(func(): return ferry_z(ferry) < near_dock_z(ferry) - 0.3, 6.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	check("real input: walking aboard starts ferry %d" % ferry, left, "z=%.1f" % ferry_z(ferry))
	var gap_min := [INF]
	var gap_max := [0.0]
	var low := [INF]
	var offset_start: float = list[0].global_position.z - ferry_z(ferry)
	var worst_slip := [0.0]
	var watch := func():
		gap_min[0] = minf(gap_min[0], gap())
		gap_max[0] = maxf(gap_max[0], gap())
		low[0] = minf(low[0], minf(list[0].global_position.y, list[1].global_position.y))
		worst_slip[0] = maxf(worst_slip[0], absf(list[0].global_position.z - ferry_z(ferry) - offset_start))
	get_tree().physics_frame.connect(watch)
	await wait(1.0)
	await on_the_way.call()
	await wait_until(func(): return absf(ferry_z(ferry) - far_dock_z(ferry)) < 0.05, 7.0)
	get_tree().physics_frame.disconnect(watch)
	await wait(0.3)
	var carry: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	check(label + ": both ride to the far dock", low[0] > -1.3 and state() == "playing", "lowest y=%.2f, state=%s" % [low[0], state()])
	check(label + ": they move with the ferry instead of sliding", worst_slip[0] < 0.6, "worst slip %.2f m" % worst_slip[0])
	check(label + ": the bazooka stays carried", is_instance_valid(carry.main_carrier) and is_instance_valid(carry.secondary_carrier), "gap %.1f to %.1f" % [gap_min[0], gap_max[0]])
	print("INFO ride gap %.2f to %.2f m" % [gap_min[0], gap_max[0]])


## Steps off the side while the ferry is in the air.
func fall_off_ferry(ferry: int) -> void:
	var list := players()
	move_players(Vector3(1.5, 0, near_dock_z(ferry) + 2.0))
	await wait_until(func(): return ferry_z(ferry) < near_dock_z(ferry) - 2.0, 6.0)
	Input.action_press(list[0].action_right)
	Input.action_press(list[1].action_right)
	var lowest := [INF]
	var watch := func():
		lowest[0] = minf(lowest[0], list[0].global_position.y)
	get_tree().physics_frame.connect(watch)
	var died: bool = await wait_until(func(): return state() == "gameoverlost", 8.0)
	await shot("decks_fall.png")
	Input.action_release(list[0].action_right)
	Input.action_release(list[1].action_right)
	get_tree().physics_frame.disconnect(watch)
	check("real input: stepping off a flying ferry is a fall and game over", died and lowest[0] < -4.0, "lowest y=%.1f, state=%s" % [lowest[0], state()])
	await wait_until(func(): return state() == "playing", 15.0)
	await wait(1.0)


## Photographs the deck with a camera riding on it at both docks. Boards fixed to the ferry look identical.
func deck_change_between_docks(ferry: int) -> float:
	var player := world.get_node("Level/Bridges/BridgePlatform%d/AnimationPlayer" % ferry) as AnimationPlayer
	player.play("bottom")
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var at_far := get_tree().root.get_texture().get_image()
	player.play("complete")
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var at_near := get_tree().root.get_texture().get_image()
	player.play("bottom")
	var total := 0.0
	var count := 0
	for x in range(0, at_far.get_width(), 8):
		for y in range(0, at_far.get_height(), 8):
			total += absf(at_far.get_pixel(x, y).get_luminance() - at_near.get_pixel(x, y).get_luminance())
			count += 1
	return total / float(count)


func check_boards_move_with_ferry() -> void:
	var body := world.get_node("Level/Bridges/BridgePlatform1/AnimatableBody3D") as Node3D
	var follow_cam := get_viewport().get_camera_3d()
	var deck_cam := Camera3D.new()
	deck_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	deck_cam.size = 5.0
	deck_cam.position = Vector3(0, 6, 0)
	deck_cam.rotation_degrees = Vector3(-90, 0, 0)
	body.add_child(deck_cam)
	deck_cam.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	var material := (body.get_node("Visual/Deck") as MeshInstance3D).mesh.surface_get_material(0) as ShaderMaterial
	var fixed: float = await deck_change_between_docks(1)
	# The control: the same measurement with the old world-space planks must show a big change.
	material.set_shader_parameter("local_space", false)
	var sliding: float = await deck_change_between_docks(1)
	material.set_shader_parameter("local_space", true)
	check("the ferry's boards move with it", fixed < 0.005, "change %.4f" % fixed)
	check("that measurement does catch sliding boards", sliding > fixed + 0.01, "world-space planks change %.4f" % sliding)
	await shot("decks_boards_far.png")
	ui.visible = true
	follow_cam.make_current()
	deck_cam.queue_free()
	await wait(0.2)


func overhead() -> void:
	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 250.0
	top.far = 400.0
	top.position = Vector3(10, 150, -95)
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot("decks_overhead.png")
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	await shot("decks_start.png")
	print("INFO fps at start: ", Engine.get_frames_per_second())
	await overhead()
	await check_boards_move_with_ferry()
	check("ferry 1 waits at the far dock", absf(ferry_z(1) - far_dock_z(1)) < 0.1, "z=%.1f" % ferry_z(1))
	path_ok(w(-4, -13), w(4, -19), true, "nav: ring connects around the hole")
	path_ok(w(0, 0), w(0, -13), false, "nav: start separate from ring")
	path_ok(w(0, -30), w(-8, -33), false, "nav: mages' decks can't be walked to")

	# Rotors don't hold anyone up: stepping off an edge falls through them.
	var list := players()
	move_players(w(4, 7))
	await wait(0.4)
	Input.action_press(list[0].action_right)
	Input.action_press(list[1].action_right)
	var died: bool = await wait_until(func(): return state() == "gameoverlost", 8.0)
	Input.action_release(list[0].action_right)
	Input.action_release(list[1].action_right)
	check("real input: walking off the deck through a rotor is a fall", died, state())
	await wait_until(func(): return state() == "playing", 15.0)
	await wait(1.0)
	list = players()
	var respawn_dx: float = absf(list[0].global_position.x - list[1].global_position.x)
	var respawn_aim: Vector3 = world.get_active_weapon().get_node("WeaponSpecifics").muzzle.global_transform.basis.z
	print("INFO after a sideways death: carriers %.2f m apart in x, muzzle points %s" % [respawn_dx, respawn_aim])
	check("respawning after a sideways death faces forward again", respawn_aim.z < -0.9 and respawn_dx < 1.0, str(respawn_aim))

	# Firing line: targets on screen, then a real rocket across the gap.
	list = players()
	await hold([list[0].action_up, list[1].action_up], 2.0)
	await wait(2.5)
	check("firing line: normal zoom, since every enemy here can be walked to", focal_count() == 0, str(focal_count()))
	check_view("firing line view", group_enemies("Enemies/EnemyGroup"), 100.0)
	await shot("decks_range.png")
	var bazooka := world.get_active_weapon()
	var specifics := bazooka.get_node("WeaponSpecifics")
	var before := group_enemies("Enemies/EnemyGroup").size()
	specifics._request_fire_bullet()
	var hit: bool = await wait_until(func(): return group_enemies("Enemies/EnemyGroup").size() < before, 9.0)
	print("INFO rocket aimed along the carriers: killed %d of %d" % [before - group_enemies("Enemies/EnemyGroup").size(), before])
	check("a real rocket kills a pack across the deck", hit)
	await shot("decks_rocket.png")

	await clear_and_call("Enemies/EnemyGroup", "Checkpoint2", 1)

	# Dying on the way must bring the ferry back and let them ride again.
	var g2 := group_enemies("Enemies/EnemyGroup2")
	check("ring's chasers wait", g2.size() == 11 and not g2[0].is_offensive, str(g2.size()))
	await fall_off_ferry(1)
	check("after a death the ferry is back at the near dock", absf(ferry_z(1) - near_dock_z(1)) < 0.1, "z=%.1f" % ferry_z(1))
	check("after a death the chasers wait again", group_enemies("Enemies/EnemyGroup2").all(func(e): return not e.is_offensive))
	protect_players()

	await board_and_ride(1, "ferry 1", func():
		await shot("decks_ride.png")
		check_view("ferry 1 mid-flight view", group_enemies("Enemies/EnemyGroup2"))
		world.get_active_weapon().get_node("WeaponSpecifics")._request_fire_bullet()
	)
	await wait(0.8)
	check("the chasers wait out the ride: the ferry isn't in the navmesh", group_enemies("Enemies/EnemyGroup2").all(func(e): return not e.is_offensive))
	print("INFO chasers down after one rocket fired mid-flight: %d of 11" % (11 - group_enemies("Enemies/EnemyGroup2").size()))
	check("ring: normal zoom, since every enemy here can be walked to", focal_count() == 0, str(focal_count()))
	check_view("ring view from the dock", group_enemies("Enemies/EnemyGroup2"))
	await walk("off the ferry onto the ring", 1.6, 4.0)
	var woke: bool = await wait_until(func(): return group_enemies("Enemies/EnemyGroup2").all(func(e): return e.is_offensive), 3.0)
	check("stepping off onto the ring wakes the chasers", woke)
	var returned: bool = await wait_until(func(): return absf(ferry_z(1) - near_dock_z(1)) < 0.1, 7.0)
	check("then ferry 1 flies back to its near dock", returned, "z=%.1f" % ferry_z(1))
	check("sending the ferry back doesn't lock the players' input", not GameplayInput.is_locked())
	await shot("decks_ring.png")
	for spot in [[-4, -12, "south-west"], [4, -12, "south-east"], [-4, -19, "north-west"], [4, -19, "north-east"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.3)
		check_view("ring %s view" % spot[2], group_enemies("Enemies/EnemyGroup2"))
	await clear_and_call("Enemies/EnemyGroup2", "Checkpoint3", 2)

	# Respawn.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("respawn keeps ferry 2 at the near dock", absf(ferry_z(2) - near_dock_z(2)) < 0.1, "z=%.1f" % ferry_z(2))
	check("respawn leaves the ring clear", group_enemies("Enemies/EnemyGroup2").is_empty())

	# Under fire on the way in.
	var fireballs := [0]
	await board_and_ride(2, "ferry 2", func():
		check_view("ferry 2 mid-flight view", group_enemies("Enemies/EnemyGroup3"), 18.0)
		await wait(1.5)
		await shot("decks_ride_under_fire.png")
		fireballs[0] = get_tree().get_nodes_in_group("fireballs").size() + world.get_children().filter(func(c): return c is Fireball).size()
	)
	print("INFO fireballs in flight during the second ride: ", fireballs[0])
	check("the causeway waits out the ride", group_enemies("Enemies/EnemyGroup3").all(func(e): return not e.is_offensive))
	await walk("off the ferry onto the causeway", 1.6, 4.0)
	var woke3: bool = await wait_until(func(): return group_enemies("Enemies/EnemyGroup3").all(func(e): return e.is_offensive), 3.0)
	check("landing on the causeway wakes the mages and chasers", woke3)
	var returned2: bool = await wait_until(func(): return absf(ferry_z(2) - near_dock_z(2)) < 0.1, 7.0)
	check("then ferry 2 flies back to its near dock", returned2, "z=%.1f" % ferry_z(2))
	await wait(1.5)
	for spot in [[0, -29, "entrance"], [-2, -33, "west"], [2, -36, "far side"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.6)
		check_view("causeway %s view" % spot[2], group_enemies("Enemies/EnemyGroup3"), 24.0)
		var mages := group_enemies("Enemies/EnemyGroup3").filter(_can_cast_at_a_player)
		check("causeway %s: mages in range on screen" % spot[2], mages.size() > 0 and visible_count(mages) == mages.size(), "%d/%d" % [visible_count(mages), mages.size()])
	await shot("decks_causeway.png")
	await check_waits_for_unreachable_player()
	print("INFO fps on the causeway: ", Engine.get_frames_per_second())
	await barge_fight()
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_waits_for_unreachable_player() -> void:
	var chaser: EnemyLocal = group_enemies("Enemies/EnemyGroup3").filter(func(e): return not e.has_node("MageBehavior"))[0]
	var mage_deck := w(-8, -32)
	place(mage_deck + Vector3(0, 0, 2.0), mage_deck)
	chaser.global_position = w(-2, -32)
	var lowest := [INF]
	var watch := func():
		if is_instance_valid(chaser):
			lowest[0] = minf(lowest[0], chaser.global_position.y)
	get_tree().physics_frame.connect(watch)
	await wait(5.0)
	get_tree().physics_frame.disconnect(watch)
	var stayed: bool = is_instance_valid(chaser) and chaser.is_alive() and lowest[0] > -1.3
	check("a chaser hunting a player it can't reach waits on its deck instead of walking off", stayed, "lowest y=%.2f, x=%.1f, deck edge x=%.1f" % [lowest[0], chaser.global_position.x if is_instance_valid(chaser) else 0.0, w(-3, -32).x - 1.5])


func check_any_mage_in_range() -> bool:
	return group_enemies("Enemies/EnemyGroup3").any(_can_cast_at_a_player)


# ---- The barge fight. ----
const BARGE_STOPS := [Vector3(1.5, 0, -129), Vector3(1.5, 0, -117), Vector3(1.5, 0, -150), Vector3(28.5, 0, -163), Vector3(28.5, 0, -186)]


func barge() -> RotorBarge:
	return world.get_node("Level/Barge") as RotorBarge


func barge_at(stop: int) -> bool:
	var at: Vector3 = barge().body.global_position
	return Vector2(at.x - BARGE_STOPS[stop].x, at.z - BARGE_STOPS[stop].z).length() < 0.1


func wave(number: int) -> Array:
	return group_enemies("Enemies/BargeWave%d" % number)


func stowed(enemies: Array) -> bool:
	return enemies.all(func(e): return not e.visible and e.process_mode == Node.PROCESS_MODE_DISABLED)


func aboard(node: Node3D) -> bool:
	return barge().deck.contains(node.global_position)


## Boards in line, one carrier behind the other, so the bazooka points forward at the waves.
func board_barge() -> bool:
	var list := players()
	var spot := w(0, -35)
	place(spot + Vector3(0, 0, -2), spot + Vector3(0, 0, 2))
	await wait(0.6)
	if muzzle_direction().z > 0.0:
		place(spot + Vector3(0, 0, 2), spot + Vector3(0, 0, -2))
		await wait(0.6)
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var on: bool = await wait_until(func(): return players().all(func(p): return barge().deck.contains(p.global_position, 1.5)), 8.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	return on and await wait_until(func(): return barge().is_moving(), 3.0)


## Watches a wave from its drop to `seconds` later: lands on the deck, closes in, and nobody walks off.
func watch_wave(number: int, label: String, seconds: float) -> void:
	var enemies := wave(number)
	var landed: bool = await wait_until(func(): return enemies.all(func(e): return e.visible and e.process_mode == Node.PROCESS_MODE_INHERIT), 6.0)
	await wait(0.3)
	check(label + ": every enemy drops onto the moving deck", landed and enemies.all(func(e): return aboard(e) and e.is_on_floor()), "%d enemies" % enemies.size())
	var before := 0.0
	for e in enemies:
		before += _player_distance(e)
	var deck_y: float = barge().body.global_position.y
	var lowest := [INF]
	var watch := func():
		for e in enemies:
			if is_instance_valid(e) and e.is_alive():
				lowest[0] = minf(lowest[0], e.global_position.y - barge().body.global_position.y)
	get_tree().physics_frame.connect(watch)
	await wait(1.5)
	var after := 0.0
	var alive := enemies.filter(func(e): return is_instance_valid(e) and e.is_alive())
	for e in alive:
		after += _player_distance(e)
	check(label + ": they chase the carriers across the deck", alive.size() < enemies.size() or after < before - 2.0, "summed distance %.1f -> %.1f" % [before, after])
	await shot("decks_barge_wave%d.png" % number)
	await wait(maxf(seconds - 1.5, 0.0))
	get_tree().physics_frame.disconnect(watch)
	check(label + ": none walk off the edge while chasing", lowest[0] > -1.0, "lowest %.2f m relative to the deck at y=%.2f" % [lowest[0], deck_y])


func muzzle_direction() -> Vector3:
	return world.get_active_weapon().get_node("WeaponSpecifics").muzzle.global_transform.basis.z


## Fires real rockets along the carriers while the wave is aboard, then reports how many fell.
func fire_rockets(number: int, shots: int) -> void:
	var specifics := world.get_active_weapon().get_node("WeaponSpecifics")
	var before := wave(number).size()
	for i in shots:
		specifics._request_fire_bullet()
		await wait(1.4)
	print("INFO wave %d: %d of %d down after %d real rockets fired along %s, carriers still aboard: %s" % [number, before - wave(number).size(), before, shots, str(muzzle_direction()), str(players().all(aboard))])


func barge_fight() -> void:
	kill_group("Enemies/EnemyGroup3")
	var docked: bool = await wait_until(func(): return barge_at(1) and not barge().is_moving(), 12.0)
	check("clearing the causeway sets Checkpoint4", cp() == "Checkpoint4", cp())
	check("the barge comes to the causeway", docked, str(barge().body.global_position))
	check("its waves wait out of sight", stowed(wave(1)) and stowed(wave(2)) and wave(1).size() == 5 and wave(2).size() == 7)
	await wait(1.5)
	check("the barge waits at the dock for the carriers", barge_at(1) and not barge().is_moving())
	await shot("decks_barge_docked.png")

	protect_players()
	check("real input: walking aboard sets the barge off", await board_barge())
	var mages := group_enemies("Enemies/BargeMages")
	check("setting off wakes the mages on the perches", mages.size() == 2 and mages.all(func(m): return m.is_offensive))
	await wait_until(func(): return wave(1).all(func(e): return e.process_mode == Node.PROCESS_MODE_INHERIT), 6.0)
	await fire_rockets(1, 2)
	await watch_wave(1, "wave 1", 3.0)
	var hovering: bool = await wait_until(func(): return barge_at(2) and not barge().is_moving(), 20.0)
	if wave(1).size() > 0:
		await wait(1.5)
		check("the barge hovers at its first stop while wave 1 lives", hovering and barge_at(2) and not barge().is_moving(), str(barge().body.global_position))
	await shot("decks_barge_hover.png")
	check("the carriers rode it all the way", players().all(aboard) and state() == "playing", state())
	kill_group("Enemies/BargeWave1")
	var left: bool = await wait_until(func(): return barge().is_moving() and barge().target_stop() == 3, 3.0)
	check("clearing wave 1 sends the barge on", left)
	await watch_wave(2, "wave 2", 3.0)
	var fireballs := world.get_children().filter(func(c): return c is Fireball).size()
	print("INFO fireballs in flight during wave 2: ", fireballs)

	# Dying mid-voyage puts everything back at the dock.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	check("after a death the barge is back at its dock", barge_at(1) and not barge().is_moving(), str(barge().body.global_position))
	check("after a death both waves wait out of sight again", stowed(wave(1)) and stowed(wave(2)) and wave(1).size() == 5 and wave(2).size() == 7, "%d, %d" % [wave(1).size(), wave(2).size()])
	check("after a death the mages wait again", group_enemies("Enemies/BargeMages").all(func(m): return not m.is_offensive))
	protect_players()
	check("real input: boarding again sets it off again", await board_barge())
	await wait_until(func(): return not stowed(wave(1)) and wave(1).all(func(e): return e.process_mode == Node.PROCESS_MODE_INHERIT), 6.0)
	kill_group("Enemies/BargeWave1")
	await wait_until(func(): return barge().target_stop() == 3 and wave(2).all(func(e): return e.process_mode == Node.PROCESS_MODE_INHERIT), 12.0)
	kill_group("Enemies/BargeWave2")
	var arrived: bool = await wait_until(func(): return barge_at(4) and not barge().is_moving(), 30.0)
	check("clearing wave 2 brings the barge to the end pad", arrived and players().all(aboard), str(barge().body.global_position))
	await walk("off the barge onto the end pad", 1.4, 3.0)
	move_players(w(9, -69))
	await wait(1.5)
	check("end area finishes the level", state() == "levelfinished", state())
