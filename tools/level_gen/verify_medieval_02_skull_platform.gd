extends Node
## Test driver for the skull platform at the start of world_local_02_medieval.tscn
## (built by add_medieval_02_skull_platform.py). Run through godot.sh, see docs/level-creation-for-agents.md.
## Checks the spawn on the round platform, that the skull wave starts by itself, how high skulls fly near the
## carriers and that a real sword swing kills one, that a skull's touch kills a carrier and the wave restarts,
## what the end of the wave does (checkpoint, bridge), the walk to the labyrinth, and a respawn there.
## Save tracking is disabled. The wave is shortened in this driver only, after checking the scene's 60 s.

const CELL := 2.999
const WAVE := "Enemies/SkullSurvival"
const START_ISLAND := [-6, -3, 38, 41]

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var centre: Vector3


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(280.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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
	await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


## The scene reloads after a game over: follow it.
func rebind() -> void:
	await wait_until(func(): return get_tree().current_scene is WorldLocal and get_tree().current_scene.is_node_ready(), 15.0)
	if get_tree().current_scene == world:
		return
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func wave() -> SurvivalEnemyGroup:
	return world.get_node(WAVE) as SurvivalEnemyGroup


func skulls() -> Array:
	return world.get_node(WAVE + "/Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func platform_y(path: String) -> float:
	return (world.get_node(path + "/AnimatableBody3D") as Node3D).global_position.y


func on_platform(p: Node3D) -> bool:
	return Vector2(p.global_position.x - centre.x, p.global_position.z - centre.z).length() < 4.5 and absf(p.global_position.y + 1.0) < 0.3


func on_start_island(p: Node3D) -> bool:
	var cx := floori(p.global_position.x / CELL)
	var cz := floori(p.global_position.z / CELL)
	return cx >= START_ISLAND[0] and cx <= START_ISLAND[1] and cz >= START_ISLAND[2] and cz <= START_ISLAND[3]


func visible_count(nodes: Array, lift: float = 0.5) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for n in nodes:
		var pos: Vector3 = n.global_position + Vector3(0, lift, 0)
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen


func release_all() -> void:
	for p in players():
		for a in [p.action_up, p.action_down, p.action_left, p.action_right, p.action_dash]:
			Input.action_release(a)


## A real swing: the skull is held still beside the blade, at the height skulls fly at near the carriers, and both
## carriers dash sideways into it.
func strike_skull(skull: EnemyLocal, height: float) -> bool:
	skull.is_offensive = false
	var blade := world.get_active_weapon().get_node("WeaponSpecifics/HitArea/CollisionShape3D") as Node3D
	var side := blade.global_basis.x.normalized()
	var spot := blade.global_position + side * 2.4
	spot.y = height
	skull.global_position = spot
	skull.velocity = Vector3.ZERO
	await get_tree().physics_frame
	# Dash towards the skull's side: pick whichever of the four directions is closest to `side`.
	var list := players()
	var dirs := {"action_right": Vector3.RIGHT, "action_left": Vector3.LEFT, "action_down": Vector3.BACK, "action_up": Vector3.FORWARD}
	var best := "action_right"
	for d in dirs:
		if (dirs[d] as Vector3).dot(side) > (dirs[best] as Vector3).dot(side):
			best = d
	for p in list:
		Input.action_press(p.get(best))
	await get_tree().physics_frame
	await get_tree().physics_frame
	for p in list:
		Input.action_press(p.action_dash)
	await wait(0.2)
	release_all()
	await wait(0.4)
	return not is_instance_valid(skull) or not skull.is_alive()


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	centre = (world.get_node("Level/SkullPlatform") as Node3D).global_position
	# The level now opens on the warm-up island (verify_medieval_02_warmup_and_horde.gd): respawn on the platform.
	if cp() != "CheckpointSkulls":
		world.checkpoint_manager.set_current_checkpoint(world.get_node("CheckpointManager/CheckpointSkulls"))
		gsm.transition_to("resettingcheckpoint")
		await wait_until(func(): return state() == "playing", 20.0)
		await wait(1.5)
	protect_players()

	# ---- Spawn. ----
	check("CheckpointSkulls is on the horde island, before the bridge", cp() == "CheckpointSkulls" and players().all(func(p): return p.global_position.z > centre.z + 8.0), cp())
	check("the bridge to the round platform is up and no wave runs yet", platform_y("Level/Bridges/HordeBridgePlatform1") > -1.5 and not wave().is_running())
	# Both carriers step onto the round platform (SkullArrival).
	for i in players().size():
		players()[i].global_position = centre + Vector3(-1.0 + 2.0 * i, 0.5, 0.0)
	await wait(1.5)
	check("both carriers stand on the round platform", players().all(on_platform), "%s %s" % [players()[0].global_position, players()[1].global_position])
	check("the wave is 60 s in the scene", is_equal_approx(wave().fight_duration, 60.0), str(wave().fight_duration))
	check("the bridge to the labyrinth is down", platform_y("Level/Bridges/SkullBridgePlatform1") < -4.0)
	await wait(3.0)
	check("the bridge behind them goes down when the wave starts", platform_y("Level/Bridges/HordeBridgePlatform1") < -4.0 and platform_y("Level/Bridges/HordeBridgePlatform2") < -4.0)
	var started := await wait_until(func(): return wave().is_running(), 5.0)
	check("the labyrinth's walkways are up", platform_y("Level/Bridges/Labyrinth/WalkStartSouthWest1") > -1.5)
	check("the skull wave starts once they step on", started)
	var rig := world.get_node("CameraFollowRig") as CameraFollowRig
	var mid: Vector3 = (players()[0].global_position + players()[1].global_position) * 0.5
	var back: float = rig.compute_desired_follow_position().distance_to(mid) - rig.follow_offset.length()
	var saved: Array = rig._extra_focal_nodes.duplicate()
	rig.clear_focal_points()
	var plain: float = rig.compute_desired_follow_position().distance_to(mid) - rig.follow_offset.length()
	for n in saved:
		rig.add_focal_point(n)
	print("INFO zoom-out with focus %.1f m, without %.1f m" % [back, plain])
	check("the camera is zoomed out a bit more for the wave", back > plain + 1.0 and back < plain + 5.0)
	var timer_ui := world.get_node_or_null("UI/SurvivalTimer") as CanvasItem
	check("the countdown shows", timer_ui != null and timer_ui.is_visible_in_tree())
	await wait(1.5)
	await shot("01_spawn.png")

	# ---- How skulls fly in, with the carriers standing still (invulnerable). ----
	var heights: Array[float] = []
	var deadline := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		for s in skulls():
			for p in players():
				if s.global_position.distance_to(p.global_position) < 2.0:
					heights.append(s.global_position.y)
	heights.sort()
	var spawned := skulls().size()
	check("skulls reach the carriers", heights.size() > 0, "%d samples" % heights.size())
	if heights.size() > 0:
		print("INFO skull height near the carriers: %.2f to %.2f (deck top -1)" % [heights[0], heights[-1]])
	check("skulls stay on screen near the carriers", visible_count(skulls().filter(func(s): return s.global_position.distance_to(players()[0].global_position) < 6.0)) == skulls().filter(func(s): return s.global_position.distance_to(players()[0].global_position) < 6.0).size())
	print("INFO %d skulls alive after 15 s of the wave" % spawned)
	await shot("02_skulls.png")

	# ---- A real swing kills a skull at the height they fly at. ----
	var height: float = heights[heights.size() / 2] if heights.size() > 0 else -0.9
	var target: EnemyLocal = skulls()[0] if not skulls().is_empty() else null
	var killed := false
	if target != null:
		killed = await strike_skull(target, height)
	check("a real sword swing kills a skull flying at carrier height (y %.2f)" % height, killed)

	# ---- A skull's touch kills a carrier, and the wave starts over. ----
	var victim: PlayerLocal = players()[0]
	# Dev settings may raise carrier HP (player_max_hp_override): take it back to the game's 3, which a touch takes.
	var victim_health := victim.get_node("Health") as Health
	victim_health.reset_to_full()
	victim_health.current_hp = 3
	var skull: EnemyLocal = skulls()[0] if not skulls().is_empty() else null
	if skull != null:
		skull.is_offensive = true
		skull.global_position = victim.global_position + Vector3(1.5, 0.3, 0)
	var died := await wait_until(func(): return state() != "playing", 6.0)
	if not died:
		victim_health.kill(victim.global_position)
		died = await wait_until(func(): return state() != "playing", 6.0)
	check("a skull's touch ends the run", died, state())
	await wait_until(func(): return state() == "playing" and is_instance_valid(world), 20.0)
	await rebind()
	await wait_until(func(): return state() == "playing", 20.0)
	protect_players()
	await wait(1.5)  # they drop from the checkpoint's height
	check("after the death the carriers are back on the horde island, not the platform", cp() == "CheckpointSkulls" and players().all(func(p): return p.global_position.z > centre.z + 8.0 and not on_platform(p)), cp())
	check("... with the bridge up and no wave", platform_y("Level/Bridges/HordeBridgePlatform1") > -1.5 and not wave().is_running())
	for i in players().size():
		players()[i].global_position = centre + Vector3(-1.0 + 2.0 * i, 0.5, 0.0)
	var restarted := await wait_until(func(): return wave().is_running() and wave().get_time_remaining() > 50.0, 8.0)
	check("... and the wave starts over once they cross", restarted, "remaining %.1f" % wave().get_time_remaining())

	# ---- The end of the wave (shortened here). ----
	wave().fight_duration = 6.0
	await wait_until(func(): return wave().get_time_remaining() <= 0.0, 12.0)
	var cleared := false
	for i in 40:
		for s in skulls():
			Health.apply_damage(s, 9999, s.global_position)
		await wait(0.25)
		if wave().signal_emitted:
			cleared = true
			break
	check("the wave ends once the time is up and the skulls are dead", cleared)
	await wait(3.0)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("... which saves CheckpointLabyrinth", cp() == "CheckpointLabyrinth", cp())
	check("... and raises the bridge to the start island", platform_y("Level/Bridges/SkullBridgePlatform1") > -1.5 and platform_y("Level/Bridges/SkullBridgePlatform2") > -1.5)
	await shot("03_bridge.png")

	# Over the bridge, for real: line up on the platform's north side and walk north.
	var list := players()
	list[1].global_position = Vector3(centre.x, 0.0, centre.z - 2.0)
	list[0].global_position = Vector3(centre.x, 0.0, centre.z + 0.6)
	await wait(1.0)
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	for p in list:
		Input.action_press(p.action_up)
	await wait(3.2)
	release_all()
	get_tree().physics_frame.disconnect(watch)
	await wait(0.5)
	check("real input: both walk over the bridge onto the start island", list.all(on_start_island) and lowest[0] > -1.6 and state() == "playing",
		"z %.1f / %.1f, lowest y %.2f, state %s" % [list[1].global_position.z, list[0].global_position.z, lowest[0], state()])
	await shot("04_start_island.png")

	# ---- A death in the labyrinth respawns on the skull platform, where the checkpoint was earned, with it done. ----
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(3.0)
	protect_players()
	check("a death in the labyrinth respawns on the skull platform", cp() == "CheckpointLabyrinth" and players().all(on_platform), cp())
	check("... with the skull bridge up and no wave", platform_y("Level/Bridges/SkullBridgePlatform2") > -1.5 and not wave().is_running() and skulls().is_empty())
	check("... and no framing", (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.is_empty())

	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
