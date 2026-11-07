extends Node
## Test driver for world_local_space_station.tscn. Copy it for a new level: keep the helpers, rewrite _run().
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


func w(cx: float, cz: float, y: float = 0.0) -> Vector3:
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


func survival_enemies() -> Array:
	return world.get_node("Enemies/SurvivalEnemyGroup/Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


## A scripted kill for testing the level's flow. `kill` goes through the vent-only shields.
func kill_group(path: String) -> void:
	for e in group_enemies(path):
		Health.from_target(e).kill(e.global_position)


func visible_count(enemies: Array) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for e in enemies:
		var pos: Vector3 = e.global_position + Vector3(0, 1, 0)
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen


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


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


func path_ok(from: Vector3, to: Vector3, should: bool, label: String) -> void:
	var map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var reached := path.size() > 0 and path[path.size() - 1].distance_to(NavigationServer3D.map_get_closest_point(map, to)) < 0.6
	check(label, reached == should, "points=%d" % path.size())


func bridge_solid(index: int) -> bool:
	var body := world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D" % index)
	var shape := body.get_node("CollisionShape3D") as CollisionShape3D
	var visual := body.get_node("Visual") as Node3D
	return not shape.disabled and visual.visible


func bridge_pair_solid(number: int) -> bool:
	return bridge_solid(number * 2 - 1) and bridge_solid(number * 2)


func bridge_pair_off(number: int) -> bool:
	return not bridge_solid(number * 2 - 1) and not bridge_solid(number * 2)


func clear_and_open(group: String, expected_cp: String, bridge: int) -> void:
	kill_group(group)
	await wait(1.0)
	var opened: bool = await wait_until(func(): return bridge_pair_solid(bridge), 8.0)
	await shot("space_bridge%d_open.png" % bridge)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(0.5)
	check(group.get_file() + " cleared sets " + expected_cp, cp() == expected_cp, cp())
	check("hard-light bridge %d switches on" % bridge, opened)


func respawn() -> void:
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()


## Real input from the checkpoint, single file across a bridge, until both are past `target_z`.
func cross(bridge: int, target_z: float) -> void:
	var list := players()
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	var across: bool = await wait_until(func(): return list[0].global_position.z < target_z and list[1].global_position.z < target_z, 12.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	get_tree().physics_frame.disconnect(watch)
	await wait(0.6)
	var carry: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	var carried := is_instance_valid(carry.main_carrier) and is_instance_valid(carry.secondary_carrier)
	check("real input: both cross hard-light bridge %d carrying the rifle" % bridge, across and lowest[0] > -1.3 and carried and state() == "playing",
		"z=%.1f/%.1f, lowest y=%.2f, carried=%s, state=%s" % [list[0].global_position.z, list[1].global_position.z, lowest[0], carried, state()])


## Robots must be animated by the shared Rig_Medium clips: their bones have to move while they run.
func check_robot_animates(label: String, enemy: EnemyLocal) -> void:
	var skeleton := enemy.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := skeleton.find_bone("upperleg.l")
	var before := skeleton.get_bone_pose_rotation(bone)
	await wait(0.35)
	var after := skeleton.get_bone_pose_rotation(bone)
	check(label, bone >= 0 and before.angle_to(after) > 0.02 and enemy.has_node("Robot"), "leg turned %.3f rad" % before.angle_to(after))


func fireballs_in_flight() -> Array:
	return world.get_children().filter(func(c): return c is Fireball)


func overhead() -> void:
	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 230.0
	top.far = 400.0
	top.position = Vector3(1.5, 150, -90)
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot("space_overhead.png")
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	await shot("space_start.png")
	print("INFO fps at start: ", Engine.get_frames_per_second())
	await overhead()
	var first := group_enemies("Enemies/EnemyGroup")
	check("enemies are robots", first.size() == 9 and first.all(func(e): return e.has_node("Robot") and not e.has_node("Skeleton_Warrior")), str(first.size()))
	check("gunners are robots that fire laser bolts", group_enemies("Enemies/EnemyGroup3").filter(func(e): return e.has_node("MageBehavior")).all(
		func(e): return e.get_node("FireballEmitter").spawn_scene.resource_path.ends_with("laser_bolt_spawn.tscn")))
	check("bridges start switched off", bridge_pair_off(1) and bridge_pair_off(4))
	path_ok(w(0, -10), w(0, -21), true, "nav: yard connects around the cargo")
	path_ok(w(0, 0), w(0, -12), false, "nav: dock separate from the yard")
	path_ok(w(0, -30), w(-6, -32), false, "nav: gunners' perches can't be walked to")
	path_ok(w(-4, -45), w(4, -51), true, "nav: reactor ring connects around the core")
	path_ok(w(0, -12), w(0, -21), true, "nav: cargo leaves a lane down the middle")

	# Stepping off a deck into space is a fall and a game over.
	var list := players()
	move_players(w(3, 0))
	await wait(0.4)
	Input.action_press(list[0].action_right)
	Input.action_press(list[1].action_right)
	var died: bool = await wait_until(func(): return state() == "gameoverlost", 8.0)
	await shot("space_fall.png")
	Input.action_release(list[0].action_right)
	Input.action_release(list[1].action_right)
	check("real input: walking off the deck is a fall into space", died, state())
	await wait_until(func(): return state() == "playing", 15.0)
	await wait(1.0)

	# Firing line: targets on screen, then a real rocket.
	list = players()
	await hold([list[0].action_up, list[1].action_up], 1.0)
	await wait(1.5)
	check("dock: normal zoom, since every enemy here can be walked to", focal_count() == 0, str(focal_count()))
	check("dock: the practice packs are on screen", visible_count(group_enemies("Enemies/EnemyGroup")) == 9, "%d/9" % visible_count(group_enemies("Enemies/EnemyGroup")))
	await shot("space_range.png")
	await check_rifle_burst()
	await clear_and_open("Enemies/EnemyGroup", "Checkpoint2", 1)

	# Bridge 1, then the yard.
	await respawn()
	var g2 := group_enemies("Enemies/EnemyGroup2")
	check("yard robots wait", g2.size() == 10 and g2.all(func(e): return not e.is_offensive), str(g2.size()))
	await cross(1, w(0, -11).z)
	await wait(1.0)
	check("crossing switches bridge 1 off behind them", bridge_pair_off(1))
	check("crossing wakes the yard robots", group_enemies("Enemies/EnemyGroup2").all(func(e): return e.is_offensive))
	await check_robot_animates("robots run with the shared animations", group_enemies("Enemies/EnemyGroup2")[0])
	await shot("space_yard.png")
	for spot in [[-4, -10, "south-west"], [4, -10, "south-east"], [-4, -20, "north-west"], [4, -20, "north-east"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.2)
		check_view("yard %s view" % spot[2], group_enemies("Enemies/EnemyGroup2"))
	await clear_and_open("Enemies/EnemyGroup2", "Checkpoint3", 2)

	# A respawn mid-level keeps the opened bridge and the cleared yard.
	await respawn()
	check("respawn keeps bridge 2 on", bridge_pair_solid(2))
	check("respawn keeps bridge 1 off", bridge_pair_off(1))
	check("respawn leaves the yard clear", group_enemies("Enemies/EnemyGroup2").is_empty())

	# Bridge 2, then the causeway under fire from the perches.
	await cross(2, w(0, -26).z)
	await wait(1.5)
	check("causeway: framing for the gunners on their perches", focal_count() == 4, str(focal_count()))
	var shots_seen := [0]
	var plasma := [false]
	for spot in [[0, -27, "entrance"], [-1, -31, "west"], [1, -35, "far side"]]:
		move_players(w(spot[0], spot[1]))
		await wait(2.0)
		check_view("causeway %s view" % spot[2], group_enemies("Enemies/EnemyGroup3"), 18.0)
		var gunners := group_enemies("Enemies/EnemyGroup3").filter(_can_cast_at_a_player)
		check("causeway %s: gunners in range on screen" % spot[2], gunners.size() > 0 and visible_count(gunners) == gunners.size(), "%d/%d" % [visible_count(gunners), gunners.size()])
		for bolt in fireballs_in_flight():
			shots_seen[0] += 1
			plasma[0] = plasma[0] or bolt.name.begins_with("LaserBolt")
	await shot("space_causeway.png")
	await check_bolt_downs_plasma()
	print("INFO bolts seen on the causeway: ", shots_seen[0], "  fps: ", Engine.get_frames_per_second())
	check("gunners fire laser bolts", shots_seen[0] > 0 and plasma[0], "%d seen, plasma=%s" % [shots_seen[0], plasma[0]])
	await clear_and_open("Enemies/EnemyGroup3", "Checkpoint4", 3)
	check("clearing the gunners drops the framing", focal_count() == 0, str(focal_count()))

	# Bridge 3, then the reactor ring: hold out against the survival wave.
	var survival := world.get_node("Enemies/SurvivalEnemyGroup") as SurvivalEnemyGroup
	check("survival lasts 40 s in the scene", is_equal_approx(survival.fight_duration, 40.0), str(survival.fight_duration))
	check("survival spawns robots", survival.enemy_scene.resource_path.ends_with("enemy_robot.tscn"), survival.enemy_scene.resource_path)
	survival.fight_duration = 12.0
	await respawn()
	await cross(3, w(0, -42).z)
	await wait(5.0)
	check("ring: normal zoom, since every enemy here can be walked to", focal_count() == 0, str(focal_count()))
	var spawned := survival_enemies()
	check("the wave spawns robots", spawned.size() > 0 and spawned.all(func(e): return e.has_node("Robot")), str(spawned.size()))
	await shot("space_ring.png")
	for spot in [[-4, -44, "south-west"], [4, -44, "south-east"], [-4, -52, "north-west"], [4, -52, "north-east"]]:
		move_players(w(spot[0], spot[1]))
		await wait(1.3)
		check_view("ring %s view" % spot[2], survival_enemies())
	var cleared_at := Time.get_ticks_msec() + 25000
	while Time.get_ticks_msec() < cleared_at and not survival.signal_emitted:
		for e in survival_enemies():
			Health.apply_damage(e, 9999, e.global_position)
		await wait(0.5)
	await wait_until(func(): return bridge_pair_solid(4), 8.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(0.5)
	check("surviving the wave sets Checkpoint5", cp() == "Checkpoint5", cp())
	check("hard-light bridge 4 switches on", bridge_pair_solid(4))

	# Bridge 4 to the escape pad.
	await respawn()
	await cross(4, w(0, -58).z)
	await shot("space_escape_pad.png")
	await wait_until(func(): return state() == "levelfinished", 6.0)
	if state() != "levelfinished":
		move_players(w(0, -61))
		await wait(1.5)
	check("end area finishes the level", state() == "levelfinished", state())
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


## Holds the shooter's real shoot button: the rifle should keep firing at its own rate,
## and each bolt that lands should take exactly one hit point.
func check_rifle_burst() -> void:
	var specifics := world.get_active_weapon().get_node("WeaponSpecifics") as PulseRifleSpecifics
	var shooter: PlayerLocal = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info().main_carrier
	var enemies := group_enemies("Enemies/EnemyGroup")
	var hp_before := _total_hp(enemies)
	var shots := [0]
	var hits := [0]
	var on_fired := func(bolt: PulseBolt):
		shots[0] += 1
		bolt.spent.connect(func(hit_enemy: bool): hits[0] += int(hit_enemy))
	specifics.fired.connect(on_fired)
	Input.action_press(shooter.action_shoot)
	await wait(1.0)
	await shot("space_rifle.png")
	await wait(1.0)
	Input.action_release(shooter.action_shoot)
	await wait(1.0)
	specifics.fired.disconnect(on_fired)
	var damage := hp_before - _total_hp(enemies)
	var killed := enemies.filter(func(e): return not is_instance_valid(e) or not e.is_alive()).size()
	print("INFO 2 s held: %d shots, %d hits, %d damage, %d of %d robots killed" % [shots[0], hits[0], damage, killed, enemies.size()])
	check("real input: holding shoot fires about 10 bolts a second", shots[0] >= 17 and shots[0] <= 21, str(shots[0]))
	check("bolts hit robots for 1 damage each", hits[0] > 0 and damage == hits[0], "%d hits, %d damage" % [hits[0], damage])
	check("a held burst kills robots", killed > 0, str(killed))
	var after: int = shots[0]
	await wait(0.5)
	check("releasing shoot stops the rifle", shots[0] == after)


func _total_hp(enemies: Array) -> int:
	var total := 0
	for e in enemies:
		if is_instance_valid(e):
			total += Health.from_target(e).current_hp
	return total


## Sends a bolt straight at a plasma bolt in flight: it should pop it.
func check_bolt_downs_plasma() -> void:
	var found: bool = await wait_until(func(): return not fireballs_in_flight().is_empty(), 8.0)
	if not found:
		check("a pulse bolt shoots down plasma", false, "no plasma in flight")
		return
	var plasma: Node3D = fireballs_in_flight()[0]
	var bolt := (load("res://src/weapon/pulse_rifle/pulse_bolt.tscn") as PackedScene).instantiate() as PulseBolt
	world.add_child(bolt)
	bolt.launch(plasma.global_position + Vector3(0.0, 0.0, 3.0), Vector3.FORWARD, 42.0, 10.0, 1)
	var downed: bool = await wait_until(func(): return not is_instance_valid(plasma) or plasma.is_queued_for_deletion(), 1.0)
	check("a pulse bolt shoots down plasma", downed)
