extends Node
## Test driver for the warm-up and horde islands at the start of world_local_02_medieval.tscn
## (built by add_medieval_02_warmup_and_horde.py). Run through godot.sh, see docs/level-creation-for-agents.md.
## Checks the spawn in the ring of harmless skeletons, that their touch does nothing and a real swing kills one,
## what clearing them does, that walking onto the horde island wakes all twenty and they charge, a death there
## and the walk back in, what clearing the horde does, and that the skull wave now waits for the round platform.
## Save tracking is disabled.

const CELL := 2.999
const WARMUP := [-8, -3, 57, 62]
const HORDE := [-9, -2, 49, 54]

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


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func living(group: String) -> Array:
	return world.get_node(group + "/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func kill(group: String) -> void:
	for e in living(group):
		Health.apply_damage(e, 9999, e.global_position)


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func platform_y(path: String) -> float:
	return (world.get_node(path + "/AnimatableBody3D") as Node3D).global_position.y


func on(rect: Array, p: Node3D) -> bool:
	var cx := floori(p.global_position.x / CELL)
	var cz := floori(p.global_position.z / CELL)
	return cx >= rect[0] and cx <= rect[1] and cz >= rect[2] and cz <= rect[3] and absf(p.global_position.y + 1.0) < 0.4


func release_all() -> void:
	for p in players():
		for a in [p.action_up, p.action_down, p.action_left, p.action_right, p.action_dash]:
			Input.action_release(a)


func mean_distance(enemies: Array) -> float:
	var total := 0.0
	var mid: Vector3 = (players()[0].global_position + players()[1].global_position) * 0.5
	for e in enemies:
		total += Vector2(e.global_position.x - mid.x, e.global_position.z - mid.z).length()
	return total / maxf(enemies.size(), 1.0)


## Both carriers walk north with real input until `done` holds (or time runs out). Returns the lowest y seen.
func walk_north(done: Callable, seconds: float) -> float:
	var lowest := [INF]
	var watch := func():
		for p in players():
			lowest[0] = minf(lowest[0], p.global_position.y)
	get_tree().physics_frame.connect(watch)
	for p in players():
		Input.action_press(p.action_up)
	await wait_until(done, seconds)
	release_all()
	get_tree().physics_frame.disconnect(watch)
	return lowest[0]


## Puts both carriers in line on a column, setter (the end the blade points past) to the north.
func line_up(x: float, z: float) -> void:
	var list := players()
	list[1].global_position = Vector3(x, 0.0, z)
	list[0].global_position = Vector3(x, 0.0, z + 2.6)
	list[0].velocity = Vector3.ZERO
	list[1].velocity = Vector3.ZERO
	await wait(1.0)


## A real swing: the skeleton is set beside the blade, and both carriers dash sideways into it.
func strike(enemy: EnemyLocal) -> bool:
	var blade := world.get_active_weapon().get_node("WeaponSpecifics/HitArea/CollisionShape3D") as Node3D
	var side := blade.global_basis.x.normalized()
	var spot := blade.global_position + side * 2.4
	spot.y = enemy.global_position.y
	enemy.global_position = spot
	await get_tree().physics_frame
	var dirs := {"action_right": Vector3.RIGHT, "action_left": Vector3.LEFT, "action_down": Vector3.BACK, "action_up": Vector3.FORWARD}
	var best := "action_right"
	for d in dirs:
		if (dirs[d] as Vector3).dot(side) > (dirs[best] as Vector3).dot(side):
			best = d
	for p in players():
		Input.action_press(p.get(best))
	await get_tree().physics_frame
	await get_tree().physics_frame
	for p in players():
		Input.action_press(p.action_dash)
	await wait(0.2)
	release_all()
	await wait(0.5)
	return not is_instance_valid(enemy) or not enemy.is_alive()


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(2.5)

	# ---- Warm-up. ----
	check("the level starts at CheckpointWarmup", cp() == "CheckpointWarmup", cp())
	check("both carriers on the warm-up island", players().all(func(p): return on(WARMUP, p)), "%s %s" % [players()[0].global_position, players()[1].global_position])
	var ring := living("Enemies/Warmup")
	var centre := Vector3((WARMUP[0] + WARMUP[1] + 1) * 0.5 * CELL, 0, (WARMUP[2] + WARMUP[3] + 1) * 0.5 * CELL)
	check("ten skeletons in a ring, none offensive", ring.size() == 10 and ring.all(func(e): return not e.is_offensive and absf(Vector2(e.global_position.x - centre.x, e.global_position.z - centre.z).length() - 5.0) < 0.6))
	check("the horde isn't in the level until the carriers reach its island", living("Enemies/Horde").is_empty() and (world.get_node("Enemies/Horde") as NormalEnemyGroup).spawn_on_trigger, "%d present" % living("Enemies/Horde").size())
	check("both bridges north are down", platform_y("Level/Bridges/WarmupBridgePlatform1") < -4.0 and platform_y("Level/Bridges/HordeBridgePlatform1") < -4.0)
	check("the skull wave isn't running", not (world.get_node("Enemies/SkullSurvival") as SurvivalEnemyGroup).is_running())
	await shot("01_warmup.png")

	# A warm-up skeleton's touch does nothing (carrier HP set to the game's 3: dev settings may raise it).
	var victim: PlayerLocal = players()[0]
	var health := victim.get_node("Health") as Health
	health.reset_to_full()
	health.current_hp = 3
	var toucher: EnemyLocal = ring[0]
	var toucher_home := toucher.global_position
	for i in 30:
		toucher.global_position = victim.global_position + Vector3(0.3, 0, 0)
		await get_tree().physics_frame
	toucher.global_position = toucher_home
	check("a warm-up skeleton's touch does no harm", health.current_hp == 3 and state() == "playing", "hp %d, %s" % [health.current_hp, state()])
	protect_players()

	# A real swing kills one.
	check("a real sword swing kills a warm-up skeleton", await strike(ring[1]))
	kill("Enemies/Warmup")
	await wait(3.5)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("clearing the warm-up saves CheckpointHorde", cp() == "CheckpointHorde", cp())
	check("... and raises the bridge north", platform_y("Level/Bridges/WarmupBridgePlatform1") > -1.5 and platform_y("Level/Bridges/WarmupBridgePlatform2") > -1.5)
	check("... and the horde still isn't there", living("Enemies/Horde").is_empty(), "%d present" % living("Enemies/Horde").size())

	# ---- Onto the horde island, for real. ----
	var bridge_x := (-6 + 0.5) * CELL
	await line_up(bridge_x, WARMUP[2] * CELL + 2.0)
	var inside_horde := func(): return players().all(func(p): return on(HORDE, p) and p.global_position.z < (HORDE[3] + 1) * CELL - 1.5)
	var lowest := await walk_north(inside_horde, 6.0)
	await wait(0.3)
	var horde := living("Enemies/Horde")
	check("real input: over the bridge onto the horde island", players().all(func(p): return on(HORDE, p)) and lowest > -1.6, "lowest y %.2f" % lowest)
	check("... which wakes all twenty", horde.size() == 20 and horde.all(func(e): return e.is_offensive))
	# They appear on arrival (spawn_on_trigger), so they first play the spawn-in and stand for its 2 s.
	await wait(2.2)
	var before := mean_distance(horde)
	await wait(3.0)
	var after := mean_distance(horde)
	check("... and they charge the carriers", after < before - 3.0 and horde.all(func(e): return on(HORDE, e)), "mean distance %.1f -> %.1f m" % [before, after])
	await shot("02_horde.png")

	# ---- A death on the horde island. ----
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.5)
	protect_players()
	check("a death in the horde respawns on the warm-up island's north side", cp() == "CheckpointHorde" and players().all(func(p): return on(WARMUP, p)), cp())
	check("... with the warm-up still cleared and its bridge up", living("Enemies/Warmup").is_empty() and platform_y("Level/Bridges/WarmupBridgePlatform2") > -1.5)
	check("... and the horde gone again until they walk back in", living("Enemies/Horde").is_empty(), "%d present" % living("Enemies/Horde").size())
	await line_up(bridge_x, WARMUP[2] * CELL + 2.0)
	await walk_north(inside_horde, 6.0)
	await wait(0.3)
	check("real input: walking back in brings all twenty back, awake", living("Enemies/Horde").size() == 20 and living("Enemies/Horde").all(func(e): return e.is_offensive), str(living("Enemies/Horde").size()))

	# ---- Clearing the horde. ----
	kill("Enemies/Horde")
	await wait(3.5)
	await wait_until(func(): return not GameplayInput.is_locked(), 10.0)
	await wait(1.0)
	check("clearing the horde saves CheckpointSkulls", cp() == "CheckpointSkulls", cp())
	check("... and raises the bridge to the round platform", platform_y("Level/Bridges/HordeBridgePlatform1") > -1.5 and platform_y("Level/Bridges/HordeBridgePlatform2") > -1.5)
	var wave := world.get_node("Enemies/SkullSurvival") as SurvivalEnemyGroup
	check("... and the skull wave still waits", not wave.is_running())

	var platform := world.get_node("Level/SkullPlatform") as Node3D
	await line_up(platform.global_position.x, HORDE[2] * CELL + 2.0)
	var on_deck := func(): return players().all(func(p): return Vector2(p.global_position.x - platform.global_position.x, p.global_position.z - platform.global_position.z).length() < 2.5)
	lowest = await walk_north(on_deck, 6.0)
	check("real input: over the bridge onto the round platform", on_deck.call() and lowest > -1.6, "lowest y %.2f" % lowest)
	check("... which starts the skull wave", await wait_until(func(): return wave.is_running(), 5.0))
	await shot("03_round_platform.png")

	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
