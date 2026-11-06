extends Node
## Test driver for world_local_necromancer_boss.tscn.
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



func boss() -> EnemyLocal:
	return world.get_node("Enemies/NecromancerGroup/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal)[0]


func gate_state(index: int) -> String:
	var body := world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D" % index)
	var seen: bool = body.get_node("Visual").is_visible_in_tree()
	var solid: bool = not body.get_node("CollisionShape3D").disabled
	return "visible=%s solid=%s" % [seen, solid]


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


func bar_visible() -> bool:
	return (world.get_node("UI/BossHealthBar") as Control).visible


func minions() -> Array:
	var parent := world.get_node_or_null("NecromancerMinions")
	if parent == null:
		return []
	return parent.get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func count_bolts() -> int:
	return world.get_children().filter(func(c): return c is Fireball).size()


func graves() -> Array:
	return world.get_children().filter(func(c): return c.name.begins_with("GraveEruption") or c.name.contains("GraveEruption"))


func current_move() -> String:
	var b := boss()
	if not b.enemy_state_machine.is_in_state("attacking"):
		return ""
	return String(b.enemy_state_machine.current_state._move)


## Watches the fight and returns every move started, in order. Screenshots the first of each.
func watch_moves(seconds: float, prefix: String) -> Array:
	var seen: Array = []
	var last := ""
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var move := current_move()
		if move != last and not move.is_empty():
			seen.append(move)
			print("INFO %s move: %s  at %s  minions=%d bolts=%d" % [prefix, move, boss().global_position, minions().size(), count_bolts()])
			if seen.count(move) == 1:
				await wait(0.7)
				await shot("%s_%s.png" % [prefix, move])
		last = move
		await get_tree().process_frame
	return seen


func check_on_screen(label: String) -> void:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	var all := players() + [boss()]
	for e in all:
		var pos: Vector3 = e.global_position + Vector3.UP
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	check(label, seen == 3, "%d/3 camera y=%.1f" % [seen, cam.global_position.y])


## Brings the carriers to open floor, puts the boss beside the blade, then swings it with real dash input.
func real_swing_hits_boss() -> void:
	var list := players()
	var b := boss()
	var before: int = b.health.current_hp
	var sword := world.get_active_weapon()
	for attempt in 6:
		move_players(w(0, -11))
		await wait(0.5)
		var blade_mid: Vector3 = (sword.get_node("WeaponSpecifics/HitArea/CollisionShape3D") as Node3D).global_position
		var side := Vector3.LEFT if attempt % 2 == 0 else Vector3.RIGHT
		var spot: Vector3 = blade_mid + side * 2.6
		spot.y = b.global_position.y
		b.global_position = spot
		await get_tree().physics_frame
		var acts: Array = [list[0].action_left, list[1].action_left] if attempt % 2 == 0 else [list[0].action_right, list[1].action_right]
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
		if b.health.current_hp < before:
			break
	print("INFO boss after swing test at ", b.global_position, " floor=", b.is_on_floor(), " state=", b.enemy_state_machine.current_state.name)
	check("real sword dash hurts the boss", b.health.current_hp < before, "%d -> %d" % [before, b.health.current_hp])


func _run() -> void:
	await wait_until(func(): return state() == "playing", 30.0)
	check("level starts playing", state() == "playing", state())
	await wait(1.0)
	await shot("01_antechamber.png")
	check("boss sleeps until the fight", not boss().is_offensive)
	check("gate starts open", gate_state(1) == "visible=false solid=false", gate_state(1))
	check("no health bar yet", not bar_visible())
	var scene_tree_ok := boss().has_node("Necromancer/Rig_Medium/Skeleton3D/ScytheHand/Scythe")
	check("model and scythe are in the rig", scene_tree_ok)
	var a: Vector3 = w(0, -9)
	var map := world.get_world_3d().navigation_map
	await wait(0.2)
	var path := NavigationServer3D.map_get_path(map, boss().global_position, w(5, -11), true)
	check("arena navmesh connects", path.size() > 0)

	# Real input from the corridor into the arena.
	protect_players()
	place(a + Vector3(0, 0, 2.6), a)
	await wait(0.3)
	var ups: Array = [players()[0].action_up, players()[1].action_up]
	for u in ups:
		Input.action_press(u)
	var woke: bool = await wait_until(func(): return boss().is_offensive, 8.0)
	for u in ups:
		Input.action_release(u)
	check("walking in wakes the boss", woke)
	var taunted: bool = await wait_until(func(): return current_move() == "taunt", 2.0)
	check("the boss taunts first", taunted, current_move())
	check("health bar shows", bar_visible())
	check("camera frames the arena", focal_count() == 4, str(focal_count()))
	await wait(2.5)
	check("gate shut behind the carriers", gate_state(1) == "visible=true solid=true", gate_state(1))
	await shot("02_fight_start.png")
	check_on_screen("carriers and boss on screen at the start")

	# Phase 1: leave the carriers mid-arena and watch.
	move_players(w(0, -12))
	var moves: Array = await watch_moves(26.0, "p1")
	print("INFO phase 1 moves: ", moves)
	check("phase 1 fires volleys", moves.has("volley"), str(moves))
	check("phase 1 summons", moves.has("summon"), str(moves))
	check("phase 1 never erupts graves", not moves.has("graves"), str(moves))
	await wait(3.5)
	check("minions appear", minions().size() > 0, str(minions().size()))
	check("minions stay within the cap", minions().size() <= 3, str(minions().size()))
	check("minions don't finish the group", not world.get_node("Enemies/NecromancerGroup").signal_emitted)

	# Corners: both carriers and the boss stay framed.
	for corner in [w(-4, -11), w(4, -11), w(-4, -19), w(4, -19)]:
		move_players(corner)
		await wait(1.6)
		check_on_screen("all on screen near %s" % corner)
	await shot("03_corner.png")

	# Staying close: a swing, then a blink away.
	var hits := [0]
	boss().get_node("SwingHitBox").body_entered.connect(func(_b): hits[0] += 1)
	var from: Vector3 = boss().global_position
	var deadline := Time.get_ticks_msec() + 16000
	var saw_moves: Array = []
	while Time.get_ticks_msec() < deadline:
		var flat := boss().global_position
		if not saw_moves.has("blink"):
			place(flat + Vector3(0.6, 0.2, 1.6), flat + Vector3(0.6, 0.2, 4.2))
		var move := current_move()
		if not move.is_empty() and not saw_moves.has(move):
			saw_moves.append(move)
			print("INFO close move: ", move)
			if move == "blink":
				from = boss().global_position
			if move == "swing":
				await wait(0.6)
				await shot("04_swing.png")
		if saw_moves.has("swing") and saw_moves.has("blink"):
			break
		await wait(0.1)
	check("the boss swings at close carriers", saw_moves.has("swing"), str(saw_moves))
	check("the swing reaches them", hits[0] > 0, str(hits[0]))
	check("the boss blinks when crowded", saw_moves.has("blink"), str(saw_moves))
	await wait(1.0)
	check("blink carries the boss away", boss().global_position.distance_to(from) > 3.0, "%s -> %s" % [from, boss().global_position])
	var on_floor: bool = boss().is_on_floor()
	check("the boss lands on the floor", on_floor, str(boss().global_position))
	await real_swing_hits_boss()

	# Phase 2.
	var health: Health = boss().health
	Health.apply_damage(boss(), health.current_hp - int(health.max_hp * 0.4), boss().global_position)
	await wait(0.2)
	check("phase 2 starts", (boss().get_node("BossPhaseController") as BossPhaseController).is_phase_at_least(2))
	var flames: GPUParticles3D = boss().get_node("Necromancer/Rig_Medium/Skeleton3D/ScytheHand/Scythe/FireParticles")
	check("scythe burns in phase 2", flames.emitting)
	await wait(0.5)
	move_players(w(0, -12))
	await shot("05_enraged.png")
	var deadline2 := Time.get_ticks_msec() + 20000
	var ring_shot := false
	var moves2: Array = []
	while Time.get_ticks_msec() < deadline2 and (not ring_shot or not moves2.has("summon")):
		var move := current_move()
		if not move.is_empty() and not moves2.has(move):
			moves2.append(move)
			print("INFO p2 move: ", move, " bolts=", count_bolts())
		if not ring_shot and graves().size() > 0:
			ring_shot = true
			await wait(0.9)
			await shot("06_graves_telegraph.png")
			await wait(0.6)
			await shot("07_graves_erupt.png")
		await get_tree().process_frame
	check("phase 2 erupts graves", ring_shot, str(moves2))
	check("phase 2 summons again", moves2.has("summon"), str(moves2))

	# A real eruption kills a carrier and respawn restores the fight.
	await wait_until(func(): return graves().is_empty(), 5.0)
	for p in players():
		p.get_node("Health")._invulnerable_time_remaining = 0.0
	var grave: Node3D = boss().get_node("NecromancerSpells").grave_scene.instantiate()
	world.add_child(grave)
	grave.global_position = Vector3(players()[1].global_position.x, boss().global_position.y, players()[1].global_position.z)
	var dead_players := func(): return state() == "gameoverlost" or players().any(func(p): return p.is_dead)
	var killed: bool = await wait_until(dead_players, 4.0)
	check("standing in an eruption kills a carrier", killed, state())
	await wait_until(func(): return state() == "resettingcheckpoint" or state() == "playing" and not players().any(func(p): return p.is_dead), 10.0)
	await wait_until(func(): return state() == "playing", 12.0)
	protect_players()
	await wait(0.5)
	await get_tree().physics_frame
	check("respawn: boss back at full health", boss().health.current_hp == boss().health.max_hp, str(boss().health.current_hp))
	check("respawn: boss asleep", not boss().is_offensive)
	check("respawn: minions cleared", minions().is_empty(), str(minions().size()))
	check("respawn: gate open", gate_state(1) == "visible=false solid=false", gate_state(1))
	check("respawn: bar hidden", not bar_visible())
	check("respawn: phase reset", not (boss().get_node("BossPhaseController") as BossPhaseController).is_phase_at_least(2))

	# Second attempt, then the finish.
	place(a + Vector3(0, 0, 2.6), a)
	await wait(0.3)
	for u in ups:
		Input.action_press(u)
	var rewoke: bool = await wait_until(func(): return boss().is_offensive, 8.0)
	for u in ups:
		Input.action_release(u)
	check("respawn: fight can restart", rewoke)
	await wait(0.5)
	await wait_until(func(): return current_move() == "", 3.0)
	await wait(3.0)
	var spell: Node = boss().get_node("NecromancerSpells")
	spell.summon_minions(2)
	await wait(3.0)
	var killed_with: Array = minions()
	check("minions present before the kill", killed_with.size() > 0, str(killed_with.size()))
	Health.apply_damage(boss(), 9999, boss().global_position)
	await wait(0.3)
	check("minions die with the boss", minions().is_empty(), str(minions().size()))
	await shot("08_death.png")
	var finished: bool = await wait_until(func(): return state() == "levelfinished", 5.0)
	check("killing the boss finishes the level", finished, state())
	await wait(1.0)
	await shot("09_finished.png")
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
