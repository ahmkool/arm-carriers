extends Node
## Test driver for world_local_dark_dungeon.tscn. Copy it for a new level: keep the helpers, rewrite _run().
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
	place(pos + Vector3(0, 0, 2.6), pos)


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
	check(label, players_seen == 2 and near_seen == near.size(), "players %d/2, enemies within %.0f m %d/%d, camera y=%.1f" % [players_seen, reach, near_seen, near.size(), get_viewport().get_camera_3d().global_position.y])


func check_mages_in_range(label: String) -> void:
	var in_range := group_enemies("Enemies/EnemyGroup3").filter(_can_cast_at_a_player)
	check(label, in_range.size() > 0 and visible_count(in_range) == in_range.size(), "%d/%d in range on screen" % [visible_count(in_range), in_range.size()])


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


func clear_and_wait(group: String, expected_cp: String, gate_index: int) -> void:
	kill_group(group)
	await wait(4.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check(group.get_file() + " cleared sets " + expected_cp, cp() == expected_cp, cp())
	check("gate %d is open" % gate_index, gate_state(gate_index) == "visible=false solid=false", gate_state(gate_index))
	check("camera focus released", focal_count() == 0, str(focal_count()))


func gate_state(index: int) -> String:
	var body := world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D" % index)
	var seen: bool = body.get_node("Visual").is_visible_in_tree()
	var solid: bool = not body.get_node("CollisionShape3D").disabled
	return "visible=%s solid=%s" % [seen, solid]


## Both carriers' heads must have a clear line to the camera: walls may not hide them.
func check_players_not_behind_walls(label: String) -> void:
	var cam := get_viewport().get_camera_3d()
	var space := world.get_world_3d().direct_space_state
	var hidden := 0
	for p in players():
		var query := PhysicsRayQueryParameters3D.create(cam.global_position, p.global_position + Vector3.UP * 1.6, 4)
		if not space.intersect_ray(query).is_empty():
			hidden += 1
	check(label, hidden == 0, "%d of 2 carriers hidden" % hidden)


## Measures real pixels: average brightness around each enemy on screen. Returns the darkest.
func darkest_enemy(enemies: Array) -> float:
	var cam := get_viewport().get_camera_3d()
	var image := get_tree().root.get_texture().get_image()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var scale_x := float(image.get_width()) / rect.size.x
	var scale_y := float(image.get_height()) / rect.size.y
	var darkest := INF
	for e in enemies:
		var spot := cam.unproject_position(e.global_position + Vector3.UP * 1.2)
		if rect.has_point(spot):
			darkest = minf(darkest, _brightness_around(image, int(spot.x * scale_x), int(spot.y * scale_y)))
	return darkest


func _brightness_around(image: Image, cx: int, cy: int) -> float:
	var total := 0.0
	var count := 0
	for dx in range(-14, 15, 4):
		for dy in range(-14, 15, 4):
			var x := clampi(cx + dx, 0, image.get_width() - 1)
			var y := clampi(cy + dy, 0, image.get_height() - 1)
			total += image.get_pixel(x, y).get_luminance()
			count += 1
	return total / float(count)


func check_enemies_readable(label: String, enemies: Array) -> void:
	await get_tree().process_frame
	var near := enemies.filter(func(e): return is_instance_valid(e) and e.is_alive() and _player_distance(e) <= 14.0)
	if near.is_empty():
		print("INFO %s: no enemies within 14 m" % label)
		return
	# Hide the HUD first: its panel is dark and would be measured instead of the enemy behind it.
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await get_tree().process_frame
	await get_tree().process_frame
	var darkest := darkest_enemy(near)
	ui.visible = true
	check(label, darkest >= 0.05, "darkest of %d enemies has brightness %.3f" % [near.size(), darkest])


func walk_up(label: String, seconds: float, expect_min: float, expect_max: float) -> void:
	var list := players()
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	var z0: float = list[0].global_position.z
	await hold([list[0].action_up, list[1].action_up], seconds)
	get_tree().physics_frame.disconnect(watch)
	var moved: float = z0 - list[0].global_position.z
	check("real input: " + label, moved >= expect_min and moved <= expect_max and lowest[0] > -1.3 and state() == "playing", "moved %.1f, lowest y=%.2f, state=%s" % [moved, lowest[0], state()])


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


func fall_into_pit() -> void:
	var list := players()
	var cx: float = w(0, -13).x
	place(Vector3(cx, 0, w(0, -14).z + 2.6), Vector3(cx, 0, w(0, -14).z))
	await wait(0.4)
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	await wait_until(func(): return list[1].global_position.y < -1.4, 3.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	var died: bool = await wait_until(func(): return state() == "gameoverlost", 5.0)
	check("real input: stepping into the pit is a fall and game over", died, "state=%s y=%.1f" % [state(), list[1].global_position.y])
	await shot("dungeon_pit_fall.png")
	await wait_until(func(): return state() == "playing", 12.0)
	await wait(1.0)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(2.0)
	await shot("dungeon_start.png")
	print("INFO fps at start: ", Engine.get_frames_per_second())
	check_view("spawn view", group_enemies("Enemies/EnemyGroup"), 14.0)
	await check_enemies_readable("spawn: nearby enemies readable in the dark", group_enemies("Enemies/EnemyGroup"))
	check_players_not_behind_walls("spawn: carriers not hidden by walls")
	check("no sun in the level", not world.has_node("DirectionalLight3D"))
	check("gate 1 starts shut and solid", gate_state(1) == "visible=true solid=true", gate_state(1))

	path_ok(w(-3, -12), w(3, -20), true, "nav: hall connects around the pit")
	path_ok(w(0, -27), w(0, -37), true, "nav: crypt connects around the pillars")

	# Walls and gates stop real walking.
	move_players(w(0, -6))
	await wait(0.5)
	await walk_up("walk to the corridor's shut gate", 3.0, 1.0, 11.0)
	await shot("dungeon_gate_shut.png")
	var list := players()
	check("real input: the shut gate holds", list[1].global_position.z > w(0, -9).z - 0.5, "front carrier z=%.1f, gate z=%.1f" % [list[1].global_position.z, w(0, -9).z])
	move_players(w(3, -6))
	await wait(0.5)
	await walk_up("a tall wall stops the carriers", 2.0, 0.5, 8.0)
	check("real input: the wall holds", list[1].global_position.z > w(3, -8).z, "front carrier z=%.1f" % list[1].global_position.z)
	check_players_not_behind_walls("beside the tall north wall: carriers not hidden")
	await shot("dungeon_wall.png")
	move_players(w(-3, 3))
	await wait(0.8)
	check_players_not_behind_walls("beside the low south wall: carriers not hidden")
	await shot("dungeon_south_wall.png")

	# A real sword strike.
	move_players(w(0, 0))
	await wait(0.6)
	var dummies := group_enemies("Enemies/EnemyGroup")
	await strike_test(dummies[0], "action_right", Vector3.RIGHT, "real dash: the blade kills a skeleton")
	await shot("dungeon_strike.png")

	kill_group("Enemies/EnemyGroup")
	await wait(1.7)
	await shot("dungeon_gate_opening.png")
	await clear_and_wait("Enemies/EnemyGroup", "Checkpoint2", 1)
	move_players(w(0, -7))
	await wait(0.5)
	await walk_up("through the open gate, down the corridor", 1.6, 6.0, 9.0)

	# The pit, with no enemies active yet.
	await fall_into_pit()
	protect_players()

	# Hall.
	var g2 := group_enemies("Enemies/EnemyGroup2")
	check("hall has 12 idle chasers", g2.size() == 12 and not g2[0].is_offensive, str(g2.size()))
	move_players(w(0, -13))
	await wait(3.0)
	check("hall trigger starts the fight", g2[0].is_offensive)
	var shut1: bool = await wait_until(func(): return gate_state(1) == "visible=true solid=true", 6.0)
	check("gate 1 shuts behind the carriers", shut1, gate_state(1))
	check("hall: focal points active", focal_count() == 4, str(focal_count()))
	check_view("hall view", group_enemies("Enemies/EnemyGroup2"))
	await check_enemies_readable("hall: nearby enemies readable in the dark", group_enemies("Enemies/EnemyGroup2"))
	await shot("dungeon_hall.png")
	for spot in [[-5, -12, "south-west"], [5, -12, "south-east"], [-5, -21, "north-west"], [5, -21, "north-east"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.3)
		check_view("hall %s view" % spot[2], group_enemies("Enemies/EnemyGroup2"))
		check_players_not_behind_walls("hall %s: carriers not hidden" % spot[2])
		await check_enemies_readable("hall %s: enemies readable" % spot[2], group_enemies("Enemies/EnemyGroup2"))
	await clear_and_wait("Enemies/EnemyGroup2", "Checkpoint3", 4)

	# Respawn.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()
	check("respawn keeps gate 2 open and gate 1 shut", gate_state(4) == "visible=false solid=false" and gate_state(1) == "visible=true solid=true", "gate 2: %s, gate 1: %s" % [gate_state(4), gate_state(1)])
	check("respawn leaves the hall clear", group_enemies("Enemies/EnemyGroup2").is_empty())

	# Crypt.
	move_players(w(0, -28))
	await wait(3.0)
	check("crypt trigger starts group 3", group_enemies("Enemies/EnemyGroup3").all(func(e): return e.is_offensive))
	check("crypt: focal points active", focal_count() == 4, str(focal_count()))
	var crypt_spots := [[0, -28, "entrance"], [-2, -32, "behind a pillar"], [2, -36, "far side"], [-5, -33, "west"]]
	for spot in crypt_spots:
		move_players(w(spot[0], spot[1]))
		await wait(1.6)
		check_view("crypt %s view" % spot[2], group_enemies("Enemies/EnemyGroup3"))
		check_players_not_behind_walls("crypt %s: carriers not hidden" % spot[2])
		await check_enemies_readable("crypt %s: enemies readable" % spot[2], group_enemies("Enemies/EnemyGroup3"))
		check_mages_in_range("crypt %s: mages in range on screen" % spot[2])
	await shot("dungeon_crypt.png")
	print("INFO fps in the busiest view: ", Engine.get_frames_per_second())
	check("no death in the crypt", state() == "playing", state())
	await clear_and_wait("Enemies/EnemyGroup3", "Checkpoint4", 7)
	move_players(w(0, -38))
	await wait(0.5)
	await walk_up("through the last gate", 1.6, 6.0, 9.0)

	move_players(w(0, -45))
	await wait(1.5)
	check("end area finishes the level", state() == "levelfinished", state())

	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 160.0
	top.far = 500.0
	top.position = Vector3(1.5, 100, -60)
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	await shot("dungeon_overhead.png")
	follow_cam.make_current()
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
