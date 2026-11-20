extends Node
## Test driver for the ninja in world_local_night_rooftops.tscn: Building 1's ninjas are killed by script to raise
## bridge 1, the carriers are put on bridge 1 and walk onto Building 2 with real input, which spawns its four ninjas;
## they circle the
## carriers at a distance without closing in, throw shurikens, and stay on the roof. A big shuriken flung straight at
## a ninja is dodged once; the second one hits.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_ninja.gd res://src/world/levels/world_local_night_rooftops.tscn <out_dir> 150

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
	get_tree().create_timer(130.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func ninjas() -> Array:
	return world.get_node("Enemies/Building2/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal)


## Puts the carriers on bridge 1, facing north, the way they walk onto Building 2.
func put_on_bridge() -> void:
	var carry_info: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	var back := carry_info.main_carrier
	var front := carry_info.secondary_carrier
	for p in [back, front]:
		p.velocity = Vector3.ZERO
	front.global_position = Vector3(0.95, front.global_position.y, -20.0)
	back.global_position = Vector3(0.95, back.global_position.y, -16.8)
	await wait(1.0)


func live_ninjas() -> Array:
	return ninjas().filter(func(n): return is_instance_valid(n) and n.is_alive())


func hp(enemy: EnemyLocal) -> int:
	return Health.from_target(enemy).current_hp


func nearest_player_distance(enemy: Node3D) -> float:
	var best := INF
	for p in players():
		var d: Vector3 = p.global_position - enemy.global_position
		best = minf(best, Vector2(d.x, d.z).length())
	return best


func players_middle() -> Vector3:
	var l := players()
	return (l[0].global_position + l[1].global_position) / 2.0


func ninja_shurikens() -> Array:
	return get_tree().get_nodes_in_group(Checkpoint.ENEMY_PROJECTILE_GROUP).filter(func(n): return n.name.begins_with("NinjaShuriken"))


## Walks both carriers north with real input until the ninjas wake.
## Walks both carriers north off the bridge with real input until both stand on Building 2, then waits for the
## round to start: the bridge closes behind them and the four ninjas spawn, awake.
func walk_in() -> bool:
	var list := players()
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	await wait_until(func(): return list.all(func(p): return p.global_position.z < -26.5), 4.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	var spawned: bool = await wait_until(func(): return ninjas().size() == 4 and ninjas().all(func(n): return n.is_offensive), 6.0)
	# On to the helipad, the middle of the roof, so the ninjas have room to circle all the way round.
	Input.action_press(list[0].action_up)
	Input.action_press(list[1].action_up)
	await wait_until(func(): return (list[0].global_position.z + list[1].global_position.z) / 2.0 < -37.0, 3.0)
	Input.action_release(list[0].action_up)
	Input.action_release(list[1].action_up)
	return spawned


## Flings a big shuriken at the ninja from `metres` away, coming from the carriers' side.
func fling_at(ninja: EnemyLocal, metres: float) -> Shuriken:
	var from := players_middle()
	var heading := ninja.global_position - from
	heading.y = 0.0
	heading = heading.normalized()
	var star := Shuriken.new()
	world.add_child(star)
	var origin := ninja.global_position - heading * metres
	origin.y = ninja.global_position.y + 0.9
	star.launch(origin, heading, 15.0, metres + 4.0, 2, 0.0)
	return star


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.0)
	for n in world.get_node("Enemies/Building1/InstancedEnemies").get_children():
		Health.apply_damage(n, 9999, n.global_position)
	# Bays rise one after another, 0.5 s apart; the last one (BridgePlatform8) is up once the whole bridge is.
	var last_bay := world.get_node("Level/Bridges/BridgePlatform8/AnimatableBody3D/CollisionShape3D") as CollisionShape3D
	await wait_until(func(): return not last_bay.disabled, 8.0)
	await wait(0.4)
	await put_on_bridge()
	check("Building 2's ninjas don't exist before the carriers land", ninjas().is_empty())
	check("real input: walking onto Building 2 spawns its four ninjas, awake", await walk_in())
	if ninjas().size() < 4:
		print("RESULT fails=%d" % (fails + 1))
		get_tree().quit(1)
		return
	var anim: Animation = (ninjas()[0] as EnemyLocal).animation_player.get_animation(&"skeleton_warrior/Throw")
	info("Throw clip %.2f s" % (anim.length if anim != null else -1.0))
	await shot("01_spawn.png")

	# ---- Circling: watch both for 9 s while the carriers stand still. ----
	var closest := INF
	var swept := [0.0, 0.0, 0.0, 0.0]
	var last_angle := [NAN, NAN, NAN, NAN]
	var lowest_y := INF
	var thrown_seen := 0
	var seen := {}
	var states := {}
	var deadline := Time.get_ticks_msec() + 9000
	var shot_taken := false
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		var middle := players_middle()
		for i in 4:
			var n: EnemyLocal = ninjas()[i]
			closest = minf(closest, nearest_player_distance(n))
			lowest_y = minf(lowest_y, n.global_position.y)
			states[String(n.enemy_state_machine.current_state.name)] = true
			var angle := atan2(n.global_position.x - middle.x, n.global_position.z - middle.z)
			if not is_nan(last_angle[i]):
				swept[i] += absf(angle_difference(last_angle[i], angle))
			last_angle[i] = angle
		for s in ninja_shurikens():
			if not seen.has(s):
				seen[s] = true
				thrown_seen += 1
		if not shot_taken and Time.get_ticks_msec() > deadline - 6000 and not ninja_shurikens().is_empty():
			shot_taken = true
			await shot("02_circling_throw.png")
	info("states seen: %s" % ", ".join(states.keys()))
	check("ninjas keep their distance", closest > 3.5, "closest %.1f m" % closest)
	check("all four ninjas run round the carriers", swept.all(func(a): return a > deg_to_rad(60)), "swept %s degrees" % str(swept.map(func(a): return roundi(rad_to_deg(a)))))
	check("ninjas throw shurikens", thrown_seen >= 2, "%d thrown" % thrown_seen)
	check("ninjas stay on the roof", lowest_y > -2.0, "lowest y %.2f" % lowest_y)
	if not shot_taken:
		await shot("02_circling.png")

	# ---- Dodge: the first star flung at a ninja is dodged, the second hits. ----
	var ninja: EnemyLocal = ninjas()[0]
	var behavior := ninja.behavior as NinjaBehavior
	await wait_until(func(): return ninja.enemy_state_machine.is_in_state("running") or ninja.enemy_state_machine.is_in_state("idle"), 3.0)
	var hp_before := hp(ninja)
	var start := ninja.global_position
	var star := fling_at(ninja, 7.0)
	var dodged: bool = await wait_until(func(): return ninja.enemy_state_machine.is_in_state("dodging"), 1.5)
	check("a ninja dodges the first big shuriken", dodged and behavior.has_dodged)
	await wait(0.15)
	await shot("03_dodge.png")
	await wait_until(func(): return not is_instance_valid(star) or not star.is_flying(), 2.0)
	check("the dodge keeps it unhurt", hp(ninja) == hp_before, "hp %d -> %d" % [hp_before, hp(ninja)])
	var moved := Vector2(ninja.global_position.x - start.x, ninja.global_position.z - start.z).length()
	check("the dodge carries it aside", moved > 1.5, "%.1f m" % moved)
	await wait(0.6)
	await wait_until(func(): return not ninja.enemy_state_machine.is_in_state("throwing"), 2.0)
	var hp_second := hp(ninja)
	var second := fling_at(ninja, 5.0)
	var dodged_again: bool = await wait_until(func(): return ninja.enemy_state_machine.is_in_state("dodging"), 1.0)
	check("it doesn't dodge a second time", not dodged_again)
	var hit: bool = await wait_until(func(): return hp(ninja) < hp_second, 1.5)
	check("the second shuriken hits it", hit, "hp %d -> %d" % [hp_second, hp(ninja)])
	await wait(1.5)
	if is_instance_valid(second):
		second.queue_free()

	# ---- The other ninja still dodges: it has its own one. ----
	var other: EnemyLocal = ninjas()[1]
	var other_behavior := other.behavior as NinjaBehavior
	var other_dodged := false
	# It can't dodge mid-throw, by design, so a star that lands as it starts a throw gets one more go.
	for attempt in 2:
		await wait_until(func(): return not other.enemy_state_machine.is_in_state("throwing"), 2.0)
		fling_at(other, 7.0)
		other_dodged = await wait_until(func(): return other.enemy_state_machine.is_in_state("dodging"), 1.5)
		if other_dodged or other_behavior.has_dodged or not other.is_alive():
			break
		await wait(1.0)
	check("each ninja has its own dodge", other_dodged)
	await wait(1.0)
	_finish()


func _finish() -> void:
	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
