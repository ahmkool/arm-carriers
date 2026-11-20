extends Node
## Test driver for world_local_night_rooftops.tscn: Building 1, Metallic Bridge, Building 2, the second bridge and
## Building 3; footstep surfaces (stone -> metal -> stone), navmesh over the bridges & around rooftop props, the
## stages (Building 1's three ninjas never wake and raise bridge 1 when killed; Building 2's four wake as the carriers
## walk in, again after a respawn, and raise bridge 2 when killed), checkpoints, and screenshots.

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
	get_tree().create_timer(200.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	var prefix := "PASS " if ok else "FAIL "
	var suffix := "" if detail.is_empty() else "  [" + detail + "]"
	print(prefix + label + suffix)
	if not ok:
		fails += 1


func w(cx: float, cz: float, y: float = 0.0) -> Vector3:
	return Vector3((cx + 0.5) * CELL, y, (cz + 0.5) * CELL)


func state() -> String:
	if gsm.current == null:
		return ""
	return String(gsm.current.name).to_lower()


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


func lowest_player_y() -> float:
	var lowest := INF
	for p in players():
		lowest = minf(lowest, p.global_position.y)
	return lowest


func mean_player_z() -> float:
	var list := players()
	return (list[0].global_position.z + list[1].global_position.z) * 0.5


func visible_players() -> int:
	var cam := get_viewport().get_camera_3d()
	var view_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for p in players():
		var pos: Vector3 = p.global_position + Vector3(0, 1.0, 0)
		if _is_point_on_screen(cam, view_rect, pos):
			seen += 1
	return seen


func _is_point_on_screen(cam: Camera3D, view_rect: Rect2, pos: Vector3) -> bool:
	if cam.is_position_behind(pos):
		return false
	return view_rect.has_point(cam.unproject_position(pos))


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func walk_north_until(target_z: float, max_seconds: float, label: String) -> StringName:
	var list := players()
	var actions := [list[0].action_up, list[1].action_up]
	var lowest := [INF]
	var last_surface: Array[StringName] = [&""]
	var watch := func():
		_sample_walk_frame(lowest, last_surface)
	get_tree().physics_frame.connect(watch)
	for a in actions:
		Input.action_press(a)
	var reached := await wait_until(func(): return mean_player_z() <= target_z, max_seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame
	get_tree().physics_frame.disconnect(watch)
	check(
		"real input: " + label,
		reached and lowest[0] > -1.35 and state() == "playing",
		"mean_z=%.1f (target %.1f), lowest_y=%.2f, surface=%s" % [mean_player_z(), target_z, lowest[0], String(last_surface[0])]
	)
	return last_surface[0]


func _sample_walk_frame(lowest: Array, last_surface: Array[StringName]) -> void:
	for p in players():
		lowest[0] = minf(lowest[0], p.global_position.y)
		var surf := FootstepSurface.under(p as CharacterBody3D)
		if surf != FootstepSurface.UNKNOWN:
			last_surface[0] = surf


func group_enemies(group: String) -> Array:
	return world.get_node("Enemies/%s/InstancedEnemies" % group).get_children().filter(func(c): return c is EnemyLocal)


func kill_group(group: String) -> void:
	for enemy in group_enemies(group):
		Health.apply_damage(enemy, 9999, enemy.global_position)


## The first bay of bridge 1 (BridgePlatform1) or bridge 2 (BridgePlatform9) stands when its collision is on.
func bridge_up(bay: String) -> bool:
	var shape := world.get_node("Level/Bridges/%s/AnimatableBody3D/CollisionShape3D" % bay) as CollisionShape3D
	return not shape.disabled


## Every bay of bridge `number` (1: BridgePlatform1-8, 2: BridgePlatform9-16) is down. Bays close one after another,
## 0.5 s apart, so this is about 4 s after the close starts.
func bridge_down(number: int) -> bool:
	var first := 1 + (number - 1) * 8
	for i in range(first, first + 8):
		if bridge_up("BridgePlatform%d" % i):
			return false
	return true


func ninja_projectiles() -> int:
	return get_tree().get_nodes_in_group(Checkpoint.ENEMY_PROJECTILE_GROUP).filter(func(n): return n.name.begins_with("NinjaShuriken")).size()


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func path_ok(from: Vector3, to: Vector3, should: bool, label: String) -> void:
	var map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	var target_nav := NavigationServer3D.map_get_closest_point(map, to)
	var reached := path.size() > 0 and path[path.size() - 1].distance_to(target_nav) < 0.6
	check(label, reached == should, "points=%d" % path.size())


func distance_to_navmesh(centre: Vector3) -> float:
	var map := world.get_world_3d().navigation_map
	var nearest := NavigationServer3D.map_get_closest_point(map, centre)
	return nearest.distance_to(centre)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.2)

	check("save disabled on prototype", world.skip_save)
	check("both carriers stand on Building 1", lowest_player_y() > -1.3, "y=%.2f" % lowest_player_y())
	check("carrying the shuriken launcher", world.get_active_weapon_id() == "shuriken_launcher", world.get_active_weapon_id())
	check("starts on Checkpoint", cp() == "Checkpoint", cp())
	check("spawn view shows both players", visible_players() == 2, "%d/2" % visible_players())

	path_ok(w(-0.5, -1.0), w(-0.5, -13.0), true, "navmesh connects Building 1 across metallic bridge to Building 2")
	var penthouse_gap := distance_to_navmesh(Vector3(-10.5, -0.5, -8.8))
	check("navmesh carves around PenthouseB1 floor", penthouse_gap > 1.0, "gap=%.2f m" % penthouse_gap)

	await shot("01_building1_spawn.png")

	# ---- Round 1: Building 1's three ninjas never wake; killing them saves Checkpoint2 here and raises bridge 1. ----
	check("bridges 1 and 2 start lowered", not bridge_up("BridgePlatform1") and not bridge_up("BridgePlatform9"))
	check("Building 1 has three ninjas", group_enemies("Building1").size() == 3, "%d" % group_enemies("Building1").size())
	check("Building 2's ninjas don't exist before their round", group_enemies("Building2").is_empty())
	await wait(3.0)
	check("Building 1's ninjas stay asleep and throw nothing", group_enemies("Building1").all(func(n): return not n.is_offensive) and ninja_projectiles() == 0)
	kill_group("Building1")
	var rose: bool = await wait_until(func(): return bridge_up("BridgePlatform1") and bridge_up("BridgePlatform8"), 8.0)
	check("killing Building 1's three ninjas raises bridge 1", rose and not bridge_up("BridgePlatform9"))
	check("clearing Building 1 saves Checkpoint2 on it", cp() == "Checkpoint2", cp())
	await wait(0.5)

	var b1_surface := await walk_north_until(-8.5, 4.0, "walk north across Building 1 toward bridge")
	check("Building 1 footstep surface is stone", b1_surface == FootstepSurface.STONE, String(b1_surface))
	check("bridge approach view shows both players", visible_players() == 2, "%d/2" % visible_players())
	await shot("02_bridge_approach.png")

	var bridge_surface := await walk_north_until(-18.0, 4.0, "walk onto metallic bridge mid-span")
	check("Metallic bridge footstep surface is metal", bridge_surface == FootstepSurface.METAL, String(bridge_surface))
	check("mid-bridge view shows both players", visible_players() == 2, "%d/2" % visible_players())
	await shot("03_on_metallic_bridge.png")

	# ---- Round 2: landing on Building 2 closes bridge 1 behind the carriers and spawns its four ninjas. ----
	var b2_surface := await walk_north_until(-29.5, 4.5, "cross metallic bridge onto Building 2")
	check("Building 2 footstep surface is stone", b2_surface == FootstepSurface.STONE, String(b2_surface))
	var closed: bool = await wait_until(func(): return bridge_down(1), 7.0)
	check("landing on Building 2 closes bridge 1 behind the carriers", closed)
	var spawned: bool = await wait_until(func(): return group_enemies("Building2").size() == 4 and group_enemies("Building2").all(func(n): return n.is_offensive), 3.0)
	check("and spawns Building 2's four ninjas, awake", spawned, "%d" % group_enemies("Building2").size())
	check("the checkpoint stays on Building 1 during the round", cp() == "Checkpoint2", cp())
	await shot("04_building2_round.png")

	await walk_north_until(-37.5, 3.5, "walk onto Building 2 helipad")
	check("helipad view shows both players", visible_players() == 2, "%d/2" % visible_players())
	await shot("05_building2_helipad.png")

	# ---- A death in round 2 respawns on Building 1 with bridge 1 up and the round undone. ----
	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.2)
	protect_players()
	check("respawn is on Building 1's Checkpoint2", cp() == "Checkpoint2" and lowest_player_y() > -1.3 and mean_player_z() > -12.0, "cp=%s y=%.2f z=%.1f" % [cp(), lowest_player_y(), mean_player_z()])
	check("bridge 1 is up again after the respawn", bridge_up("BridgePlatform1"))
	check("Building 2's ninjas are gone until the round starts again", group_enemies("Building2").filter(func(n): return n.is_alive()).is_empty())
	await walk_north_until(-29.5, 6.0, "cross bridge 1 again onto Building 2")
	# The round starts as the last bay begins to close, so wait for both.
	var respawned: bool = await wait_until(func(): return group_enemies("Building2").filter(func(n): return n.is_alive() and n.is_offensive).size() == 4 and bridge_down(1), 9.0)
	check("landing again restarts the round", respawned and bridge_down(1), "ninjas alive and awake %d of %d, bridge 1 down %s" % [group_enemies("Building2").filter(func(n): return n.is_alive() and n.is_offensive).size(), group_enemies("Building2").size(), bridge_down(1)])
	path_ok(w(-0.5, -14.0), w(-0.5, -24.0), true, "navmesh connects Building 2 across bridge 2 to Building 3")

	# ---- Clearing Building 2 saves Checkpoint3 on it and raises bridge 2. ----
	kill_group("Building2")
	await shot("05b_building2_cleared.png")
	var rose_2: bool = await wait_until(func(): return bridge_up("BridgePlatform9") and bridge_up("BridgePlatform16"), 8.0)
	check("killing Building 2's four ninjas raises bridge 2", rose_2)
	check("clearing Building 2 saves Checkpoint3 on it", cp() == "Checkpoint3", cp())
	await wait(0.5)

	# ---- Across bridge 2 onto Building 3. ----
	await walk_north_until(-48.5, 4.0, "walk north across Building 2 toward bridge 2")
	var bridge2_surface := await walk_north_until(-57.0, 3.0, "walk onto bridge 2 mid-span")
	check("bridge 2 footstep surface is metal", bridge2_surface == FootstepSurface.METAL, String(bridge2_surface))
	await shot("06_on_bridge2.png")
	await walk_north_until(-68.0, 3.0, "cross bridge 2 onto Building 3")
	await shot("07_building3.png")

	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.2)
	check("respawn is on Building 2's Checkpoint3 with bridge 2 up", cp() == "Checkpoint3" and lowest_player_y() > -1.3 and bridge_up("BridgePlatform9") and mean_player_z() < -38.0, "cp=%s y=%.2f z=%.1f" % [cp(), lowest_player_y(), mean_player_z()])

	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
