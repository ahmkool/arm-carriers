extends Node
## Test driver for world_local_clanker_boss.tscn. Run through godot.sh, see docs/level-creation-for-agents.md.
## Uses real input where it matters. Save tracking is disabled, so save.json stays untouched.

const CELL := 2.999
const EXPLOSION := preload("res://src/vfx/explosion.tscn")
const BOSS_HP := 60
var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var moves_seen: Array = []
var _was_attacking := [false]


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(400.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func on_screen(point: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return not cam.is_position_behind(point) and rect.has_point(cam.unproject_position(point))


func bridge_y(index: int) -> float:
	return (world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D" % index) as Node3D).global_position.y


func boss() -> EnemyLocal:
	var alive := world.get_node("Enemies/BossGroup/InstancedEnemies").get_children().filter(
		func(c): return c is EnemyLocal and c.is_alive())
	return alive[0] if not alive.is_empty() else null


func boss_hp() -> int:
	return boss().get_node("Health").current_hp


func pockets() -> Array:
	return world.get_node("Level/Pockets").get_children()


func slag_globs() -> Array:
	return world.get_children().filter(func(c): return c.scene_file_path.ends_with("slag_glob.tscn"))


## Records every move the Clanker starts, from its behavior's intent when it enters the Attacking state.
## The move is read from the Attacking state: the behavior's intent is rebuilt every frame, so it is empty mid-move.
func watch_moves() -> void:
	if _watcher.is_valid() and get_tree().physics_frame.is_connected(_watcher):
		get_tree().physics_frame.disconnect(_watcher)
	var clanker := boss()
	var attacking_state := clanker.get_node("EnemyStateMachine/Attacking")
	_watcher = func():
		if not is_instance_valid(clanker) or not clanker.is_alive():
			return
		var attacking: bool = clanker.enemy_state_machine.is_in_state("attacking")
		if attacking and not _was_attacking[0]:
			moves_seen.append(attacking_state._move)
		_was_attacking[0] = attacking
	get_tree().physics_frame.connect(_watcher)

var _watcher: Callable


func wait_for_move(move: StringName, timeout: float) -> bool:
	var before := moves_seen.size()
	return await wait_until(func(): return moves_seen.slice(before).has(move), timeout)


## Puts both carriers `distance` metres in front of the Clanker (towards the bridge), in line like the catapult.
func stand_at(distance: float) -> void:
	var spot := boss().global_position + Vector3(0, 0, distance)
	place(spot + Vector3(0, 0, 4.5), spot)


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


func enter_arena() -> void:
	protect_players()
	var list := players()
	place(w(0, -6) + Vector3(0, 0, 2.25), w(0, -6) + Vector3(0, 0, -2.25))
	await wait(0.5)
	await hold([list[0].action_up, list[1].action_up], 2.4)


func check_real_catapult_hit() -> void:
	var catapult := world.get_node("Weapon/Catapult") as Node3D
	var specifics := catapult.get_node("WeaponSpecifics") as CatapultSpecifics
	var carry: CarryInfo = (catapult.get_node("PickAndDropHandler") as PickAndDropHandler).get_carry_info()
	var shooter: PlayerLocal = carry.main_carrier
	var setter: PlayerLocal = carry.secondary_carrier
	var d: Vector3 = setter.global_position - shooter.global_position
	var flight: Dictionary = specifics.predict_flight(specifics.get_launch_angle_deg(Vector2(d.x, d.z).length()), shooter)
	var clanker := boss()
	var landing: Vector3 = flight.landing
	clanker.global_position = Vector3(landing.x, clanker.global_position.y, landing.z)
	var hp_before := boss_hp()
	var exploded := [false]
	specifics.fired.connect(func(bomb: CatapultBomb, _deg: float): bomb.exploded.connect(func(_at): exploded[0] = true), CONNECT_ONE_SHOT)
	Input.action_press(shooter.action_shoot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(shooter.action_shoot)
	await wait(0.4)
	await shot("clanker_bomb_in_flight.png")
	await wait_until(func(): return exploded[0], 4.0)
	await wait(0.2)
	check("real catapult throw: a bomb takes 3 HP off the Clanker", boss_hp() == hp_before - 3, "%d -> %d" % [hp_before, boss_hp()])


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.5)
	await shot("clanker_start.png")
	print("INFO fps at start: ", Engine.get_frames_per_second())
	var clanker := boss()
	check("the Clanker waits, at full health", clanker != null and not clanker.is_offensive and boss_hp() == BOSS_HP, "hp=%d" % boss_hp())
	check("the arena has magma pockets", pockets().size() == 11, "%d" % pockets().size())

	protect_players()
	await check_real_catapult_hit()
	clanker.global_position = w(0, -17)
	clanker.get_node("Health").reset_to_full()
	await wait(0.5)

	# Walk into the arena: the bridge sinks behind and the Clanker wakes.
	await enter_arena()
	var woke: bool = await wait_until(func(): return boss().is_offensive, 4.0)
	check("entering the arena wakes the Clanker", woke)
	var sank: bool = await wait_until(func(): return bridge_y(1) < -2.0, 6.0)
	check("the bridge sinks behind the carriers", sank, "y=%.2f" % bridge_y(1))
	await wait(1.0)
	var list := players()
	check("both carriers and the Clanker on screen in the arena", on_screen(list[0].global_position + Vector3.UP) and on_screen(list[1].global_position + Vector3.UP))
	print("INFO Clanker on screen from the entrance: ", on_screen(boss().global_position + Vector3.UP * 2.0))
	await shot("clanker_arena.png")
	watch_moves()

	# Long range: slag from the exhausts.
	boss().global_position = w(4, -19)  # on the flank, so the carriers 13 m away aren't in the forge pool
	stand_at(13.0)
	var lobbed: bool = await wait_for_move(&"mortar", 10.0)
	check("at long range the Clanker lobs slag", lobbed, str(moves_seen))
	var flying: bool = await wait_until(func(): return slag_globs().size() >= 2, 2.0)
	check("one glob per carrier", flying, "%d globs" % slag_globs().size())
	await wait(0.5)
	await shot("clanker_mortar.png")
	await wait(1.0)
	var pools := slag_globs().filter(func(g): return g._landed)
	check("globs land and leave burning pools", pools.size() >= 2, "%d pools" % pools.size())
	await shot("clanker_pools.png")
	await wait_until(func(): return slag_globs().is_empty(), 6.0)
	check("the pools cool and go", slag_globs().is_empty(), "%d left" % slag_globs().size())
	check("still playing after the volley", state() == "playing", state())

	# Mid range: a smash. Its shockwave sets off the pockets it reaches, but not under itself.
	await wait_until(func(): return not boss().enemy_state_machine.is_in_state("attacking"), 4.0)
	boss().global_position = w(0, -11)
	boss().is_offensive = false  # held still while the pockets set off by any earlier smash recharge
	place(w(0, -8) + Vector3(0, 0, 1.0), w(0, -9) - Vector3(0, 0, 0.5))
	await wait(10.5)
	boss().global_position = w(0, -11)
	boss().behavior._smash_remaining = 0.0
	boss().is_offensive = true
	stand_at(5.5)
	var hp_before_smash := boss_hp()
	var smashed: bool = await wait_for_move(&"smash", 10.0)
	check("at mid range the Clanker smashes", smashed, str(moves_seen))
	var bursts: Array = await record_bursts(4.5)
	check("the smash's shockwave sets off nearby pockets", bursts.size() >= 3, "%d pockets burst" % bursts.size())
	check("pockets it sets off itself spare the Clanker", boss_hp() == hp_before_smash, "%d -> %d" % [hp_before_smash, boss_hp()])
	check("still playing after the shockwave", state() == "playing", state())
	await shot("clanker_smash.png")

	# Close range: a punch.
	await wait_until(func(): return not boss().enemy_state_machine.is_in_state("attacking"), 4.0)
	stand_at(2.6)
	var punched: bool = await wait_for_move(&"punch", 10.0)
	check("up close the Clanker punches", punched, str(moves_seen))
	await wait(0.6)
	check("the punch's hit box is live mid-swing", boss().get_node("PunchHitBox").monitoring)
	await shot("clanker_punch.png")

	# The counter: an explosion sets off a pocket under the Clanker, and the burst burns it for a fixed chunk.
	await wait(1.5)
	boss().is_offensive = false
	await wait_until(func(): return not boss().enemy_state_machine.is_in_state("attacking"), 4.0)
	place(w(0, -8) + Vector3(0, 0, 1.0), w(0, -9) - Vector3(0, 0, 0.5))  # in the arena, clear of the sunk bridge
	await wait(10.5)  # the pockets recharge after the smash
	var pocket: LavaVent = pockets()[0]
	boss().global_position = Vector3(pocket.global_position.x, boss().global_position.y, pocket.global_position.z)
	var burned_boss := [false]
	pocket.burned.connect(func(body): burned_boss[0] = burned_boss[0] or body == boss())
	var hp_before_pocket := boss_hp()
	var bomb := EXPLOSION.instantiate() as Node3D
	world.add_child(bomb)
	bomb.global_position = pocket.global_position + Vector3(4.0, 1.0, 0.0)
	await wait(2.0)
	var lost := hp_before_pocket - boss_hp()
	check("still playing after the pocket test", state() == "playing", state())
	check("a pocket set off under the Clanker burns it", burned_boss[0], "hp lost %d" % lost)
	check("the burn is a chunk, not a kill", lost >= 6 and lost <= 9 and boss().is_alive(), "hp lost %d" % lost)
	boss().is_offensive = true

	# A smash is lethal: unprotected carriers inside the ring.
	for p in players():
		p.get_node("Health").reset_to_full()
	await wait_until(func(): return not boss().enemy_state_machine.is_in_state("attacking"), 4.0)
	stand_at(4.8)
	var dead_now: bool = await wait_until(func(): return state() == "gameoverlost", 16.0)
	check("standing near the Clanker is a game over", dead_now, "moves %s" % str(moves_seen.slice(-3)))
	get_tree().physics_frame.disconnect(_watcher)
	await wait_until(func(): return state() == "playing", 15.0)
	await wait(1.0)
	clanker = boss()
	check("respawn resets the Clanker: waiting, full health", clanker != null and not clanker.is_offensive and boss_hp() == BOSS_HP, "hp=%d" % (boss_hp() if clanker else -1))
	check("respawn raises the bridge again", bridge_y(1) > -2.0, "y=%.2f" % bridge_y(1))

	# Phase 2: down to half health it overheats. The roar sets off pockets across the arena.
	await enter_arena()
	await wait_until(func(): return boss().is_offensive, 4.0)
	await wait(1.0)
	moves_seen.clear()
	watch_moves()
	Health.apply_damage(boss(), BOSS_HP / 2, boss().global_position)
	var roared: bool = await wait_for_move(&"roar", 6.0)
	check("at half health the Clanker roars", roared, str(moves_seen))
	var roar_bursts: Array = await record_bursts(5.0)
	check("overheated, its roar sets off pockets across the arena", roar_bursts.size() >= 8, "%d of %d" % [roar_bursts.size(), pockets().size()])
	var head := boss().get_node("Clanker/Rig_Large/Skeleton3D/Clanker_Head") as MeshInstance3D
	check("its eyes turn red", head.get_surface_override_material(1) != null)
	await shot("clanker_overheat.png")
	stand_at(7.5)
	await wait(0.6)
	await shot("clanker_overheated_close.png")
	await wait_until(func(): return not boss().enemy_state_machine.is_in_state("attacking"), 4.0)
	stand_at(13.0)
	await wait_for_move(&"mortar", 12.0)
	var most := [0]
	var count_globs := func(): most[0] = maxi(most[0], slag_globs().size())
	get_tree().physics_frame.connect(count_globs)
	await wait(1.4)
	await shot("clanker_overheated_mortar.png")
	get_tree().physics_frame.disconnect(count_globs)
	check("an overheated volley lobs five globs", most[0] >= 5, "%d at once" % most[0])

	Health.apply_damage(boss(), 999, boss().global_position)
	var won: bool = await wait_until(func(): return state() == "levelfinished", 8.0)
	check("defeating the Clanker finishes the level", won, state())
	print("INFO moves seen: ", moves_seen)
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
