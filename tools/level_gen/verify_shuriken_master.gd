extends Node
## Test driver for the Shuriken Master on world_local_night_rooftops.tscn's Building 3. The level is jumped to
## Checkpoint3 (Building 2 cleared, bridge 2 up), then the carriers walk onto Building 3 with real input:
## - bridge 2 closes behind them, he spawns awake with 30 HP, carrier-sized, with a health bar over his head;
## - his two giant stars circle him; he throws them, they linger and creep, and he pulls them back;
## - a star that is out cuts a carrier it touches;
## - the launcher's kunai and star glance off his stars;
## - hurt while a star is out, he swaps places with it;
## - beaten, his stars go and Checkpoint4 is saved on Building 3.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_shuriken_master.gd res://src/world/levels/world_local_night_rooftops.tscn <out_dir> 200

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
	get_tree().create_timer(180.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


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
		await get_tree().physics_frame
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


func boss() -> EnemyLocal:
	var list := world.get_node("Enemies/Building3/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal)
	return null if list.is_empty() else list[0]


func master() -> ShurikenMasterBehavior:
	return boss().behavior as ShurikenMasterBehavior


func stars() -> Array:
	return master().stars.filter(func(s): return is_instance_valid(s))


func boss_hp() -> int:
	return Health.from_target(boss()).current_hp


func bridge2_down() -> bool:
	for i in range(9, 17):
		var shape := world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D/CollisionShape3D" % i) as CollisionShape3D
		if not shape.disabled:
			return false
	return true


func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Where an orbiting star will be in `seconds`.
func orbit_point_after(star: BossShuriken, seconds: float) -> Vector3:
	var angle := star.orbit_angle + BossShuriken.ORBIT_SPEED * seconds
	return boss().global_position + Vector3(cos(angle), 0.0, sin(angle)) * BossShuriken.ORBIT_RADIUS + Vector3.UP * BossShuriken.HEIGHT


func walk_north_until(target_z: float, seconds: float) -> bool:
	var list := players()
	for p in list:
		Input.action_press(p.action_up)
	var reached: bool = await wait_until(func(): return list.all(func(p): return p.global_position.z < target_z), seconds)
	for p in list:
		Input.action_release(p.action_up)
	return reached


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	# Jump to Building 2 cleared: Checkpoint3 has bridge 2 up and Buildings 1 and 2 beaten.
	(world.get_node("CheckpointManager/Checkpoint3") as Node).call("_trigger_checkpoint")
	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.5)
	protect_players()
	check("the boss doesn't exist before his round", boss() == null)

	# ---- The round: landing closes bridge 2 and spawns him. ----
	check("real input: walk across bridge 2 onto Building 3", await walk_north_until(-66.5, 8.0))
	var spawned: bool = await wait_until(func(): return boss() != null and boss().is_offensive and bridge2_down(), 9.0)
	check("landing closes bridge 2 and spawns the Shuriken Master, awake", spawned)
	if not spawned:
		_finish()
		return
	check("he has 30 HP", Health.from_target(boss()).max_hp == 30 and boss_hp() == 30, "%d/%d" % [boss_hp(), Health.from_target(boss()).max_hp])
	var bar := boss().get_node("EnemyHealthBar3D") as EnemyHealthBar3D
	var bar_shown: bool = await wait_until(func(): return bar.visible, 3.0)
	check("a health bar shows over his head from the start", bar_shown and bar.position.y > 2.0)
	check("no boss bar: he is a normal enemy", not (world.get_node("UI/BossHealthBar") as Control).visible)
	var model := boss().get_node("Ninja") as Node3D
	check("he is carrier-sized, like the other ninjas", is_equal_approx(model.scale.y, 1.0), "scale %.2f" % model.scale.y)
	await wait(0.6)
	check("two giant stars circle him", stars().size() == 2 and stars().all(func(s): return absf(flat_distance(s.global_position, boss().global_position) - BossShuriken.ORBIT_RADIUS) < 0.3))
	await shot("01_orbit.png")

	# ---- His moves, watched for 14 s: throw, linger, pull back, and the odd swap. ----
	var seen := {}
	var last_pos := boss().global_position
	var drift_near_carrier := INF
	var shot_drift := false
	var deadline := Time.get_ticks_msec() + 14000
	while Time.get_ticks_msec() < deadline and boss() != null:
		await get_tree().physics_frame
		for s in stars():
			seen[BossShuriken.Mode.keys()[s.mode]] = true
			if s.is_drifting():
				for p in players():
					drift_near_carrier = minf(drift_near_carrier, flat_distance(s.global_position, p.global_position))
		if flat_distance(boss().global_position, last_pos) > 2.5:
			seen["SWAP"] = true
		last_pos = boss().global_position
		if not shot_drift and seen.has("DRIFTING"):
			shot_drift = true
			await shot("02_star_out.png")
	info("seen: %s" % ", ".join(seen.keys()))
	check("he throws a star", seen.has("THROWN"))
	check("it lingers out there", seen.has("DRIFTING"))
	check("and he pulls it back", seen.has("RETURNING"))
	check("a lingering star creeps up on the carriers", drift_near_carrier < 4.0, "closest %.1f m" % drift_near_carrier)

	# Hold him still for the close checks; his stars keep circling.
	boss().is_offensive = false
	await wait_until(func(): return stars().all(func(s): return s.mode == BossShuriken.Mode.ORBITING), 6.0)

	# ---- A star cuts a carrier it touches. ----
	var victim: PlayerLocal = players()[0]
	var victim_health := victim.get_node("Health") as Health
	victim_health.reset_to_full()
	var star: BossShuriken = stars()[0]
	star.drift_from(victim.global_position)
	var cut: bool = await wait_until(func(): return victim_health.current_hp < victim_health.max_hp, 1.0)
	check("a star cuts a carrier it touches", cut, "hp %d" % victim_health.current_hp)
	victim_health.reset_to_full()
	protect_players()
	star.pull_back()
	await wait_until(func(): return star.mode == BossShuriken.Mode.ORBITING, 4.0)

	# ---- The carriers' shots glance off his stars. ----
	var kunai_deflected := false
	for attempt in 4:
		kunai_deflected = await _kunai_glances_off(stars()[attempt % 2])
		if kunai_deflected:
			break
	check("a kunai glances off his star", kunai_deflected)
	var star_deflected := false
	for attempt in 4:
		star_deflected = await _launcher_star_glances_off(stars()[attempt % 2])
		if star_deflected:
			break
	check("the launcher's star glances off his star", star_deflected)
	await shot("03_deflect.png")
	check("glancing shots don't hurt him", boss_hp() == 30, "hp %d" % boss_hp())

	# ---- Hurt while a star is out, he swaps places with it. ----
	boss().is_offensive = true
	await wait(0.2)
	star = stars()[0]
	# Sideways, away from the carriers: he won't swap to a star near them.
	var side := 1.0 if boss().global_position.x < 0.0 else -1.0
	var spot := boss().global_position + Vector3(6.0 * side, 0, 0)
	for p in players():
		p.velocity = Vector3.ZERO
	star.throw_at(spot)
	await wait_until(func(): return star.is_drifting(), 3.0)
	boss().is_offensive = false
	star.mode = BossShuriken.Mode.DRIFTING
	master()._swap_cooldown = 0.0
	var before := boss().global_position
	var star_before := star.global_position
	boss().is_offensive = true
	Health.apply_damage(boss(), 2, boss().global_position + Vector3.FORWARD)
	await get_tree().physics_frame
	var jumped := flat_distance(boss().global_position, star_before) < 0.5 and flat_distance(star.global_position, before) < BossShuriken.DRIFT_LOOP_RADIUS + 0.5
	check("hurt while a star is out, he swaps places with it", jumped, "boss moved %.1f m" % flat_distance(boss().global_position, before))
	await wait(0.1)
	await shot("04_swap.png")
	check("the hit still counts", boss_hp() == 28, "hp %d" % boss_hp())

	# ---- He never swaps onto the carriers: a star lingering on one is no way in. ----
	await wait(0.5)
	master()._swap_cooldown = 0.0
	star.drift_from(players()[0].global_position)
	star.mode = BossShuriken.Mode.DRIFTING
	var stood := boss().global_position
	Health.apply_damage(boss(), 2, boss().global_position + Vector3.FORWARD)
	await get_tree().physics_frame
	check("he won't swap to a star on top of a carrier", flat_distance(boss().global_position, stood) < 0.5, "moved %.1f m" % flat_distance(boss().global_position, stood))

	# ---- Beaten. ----
	var star_refs := stars()
	Health.apply_damage(boss(), 999, boss().global_position)
	var gone: bool = await wait_until(func(): return star_refs.all(func(s): return not is_instance_valid(s)), 3.0)
	check("beaten, his stars go with him", gone)
	var saved: bool = await wait_until(func(): return String(world.checkpoint_manager.current_checkpoint.name) == "Checkpoint4", 3.0)
	check("beating him saves Checkpoint4 on Building 3", saved)
	_finish()


## Fires a kunai from 5 m at where the star will be when it gets there. True if its heading changes.
func _kunai_glances_off(star: BossShuriken) -> bool:
	var from := boss().global_position + Vector3(-6.0, BossShuriken.HEIGHT, 3.0)
	var travel := 5.5 / Shuriken.KUNAI_SPEED
	var aim := orbit_point_after(star, travel)
	var kunai := Kunai.new()
	world.add_child(kunai)
	kunai.launch(from, aim - from, Shuriken.KUNAI_SPEED, 9.0, 2)
	var heading := (aim - from).normalized()
	var turned: bool = await wait_until(func(): return is_instance_valid(kunai) and kunai.global_basis.z.dot(heading) < 0.95, 0.6)
	await wait(0.4)
	return turned


func _launcher_star_glances_off(star: BossShuriken) -> bool:
	var from := boss().global_position + Vector3(-7.0, BossShuriken.HEIGHT, 4.0)
	var travel := 6.0 / 15.0
	var aim := orbit_point_after(star, travel)
	var heading := Vector3(aim.x - from.x, 0.0, aim.z - from.z).normalized()
	var flying := Shuriken.new()
	world.add_child(flying)
	flying.launch(from, heading, 15.0, 10.0, 2, 0.0)
	var turned: bool = await wait_until(func(): return is_instance_valid(flying) and flying.get_direction().dot(heading) < 0.95, 1.0)
	if is_instance_valid(flying):
		flying.queue_free()
	return turned


func _finish() -> void:
	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
