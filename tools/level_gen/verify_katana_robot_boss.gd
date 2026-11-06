extends Node
## Test driver for world_local_katana_robot_boss.tscn: the 4GTN boss fight.
## Run through godot.sh, see docs/level-creation-for-agents.md.
## Real input for crossing and firing the rifle. Save tracking is disabled, so save.json stays untouched.

const CELL := 2.999
var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var boss: EnemyLocal
## Every move the boss starts, in order.
var moves: Array[StringName] = []
var move_times: Array[int] = []
## Telegraphs to screenshot the first time each shows: node path under the boss -> file name.
var captures := {"VFX/DashLane": "katana_lane.png", "VFX/WaveFan": "katana_wave_lanes.png"}
## Damage each hit from the boss dealt to a carrier.
var hits_taken: Array[int] = []
var _last_attack_state: EnemyState
## Lunges start from 7 m or more, so kiting keeps the carriers further than that.
const KITE_DISTANCE := 7.5
var seen_slash_telegraph := [false]
var seen_lane := [false]


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(300.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func visible_count(enemies: Array) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for e in enemies:
		var pos: Vector3 = e.global_position + Vector3(0, 1, 0)
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen


func bridge_solid(index: int) -> bool:
	var body := world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D" % index)
	var shape := body.get_node("CollisionShape3D") as CollisionShape3D
	var visual := body.get_node("Visual") as Node3D
	return not shape.disabled and visual.visible


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
	await wait(0.6)
	var carry: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	var carried := is_instance_valid(carry.main_carrier) and is_instance_valid(carry.secondary_carrier)
	check("real input: both cross hard-light bridge %d carrying the rifle" % bridge, across and lowest[0] > -1.3 and carried and state() == "playing",
		"z=%.1f/%.1f, lowest y=%.2f, carried=%s, state=%s" % [list[0].global_position.z, list[1].global_position.z, lowest[0], carried, state()])


func check_robot_animates(label: String, enemy: EnemyLocal) -> void:
	var skeleton := enemy.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var bone := skeleton.find_bone("upperarm.r")
	var before := skeleton.get_bone_pose_rotation(bone)
	await wait(0.35)
	var after := skeleton.get_bone_pose_rotation(bone)
	check(label, bone >= 0 and before.angle_to(after) > 0.005 and enemy.has_node("Robot"), "leg turned %.3f rad" % before.angle_to(after))


func fireballs_in_flight() -> Array:
	return world.get_children().filter(func(c): return c is Fireball)


func overhead() -> void:
	var follow_cam := get_viewport().get_camera_3d()
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 120.0
	top.far = 400.0
	top.position = Vector3(1.5, 150, -20)
	top.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(top)
	top.make_current()
	var ui := world.get_node("UI") as CanvasLayer
	ui.visible = false
	await shot("katana_overhead.png")
	ui.visible = true
	follow_cam.make_current()
	top.queue_free()


## The group re-instances its enemies on a checkpoint load, so the boss's node name can change.
func find_boss() -> EnemyLocal:
	for child in world.get_node("Enemies/BossGroup/InstancedEnemies").get_children():
		if child is EnemyLocal:
			return child
	return null


func boss_state() -> String:
	if not is_instance_valid(boss) or boss.enemy_state_machine.current_state == null:
		return ""
	return String(boss.enemy_state_machine.current_state.name).to_lower()


## Logs each move as it starts, by watching the attacking state.
func _track_moves() -> void:
	if not is_instance_valid(boss):
		return
	var current := boss.enemy_state_machine.current_state
	if current == _last_attack_state:
		return
	_last_attack_state = current
	if boss_state() != "attacking":
		return
	moves.append(current.get("_move"))
	move_times.append(Time.get_ticks_msec())


func _watch_telegraphs() -> void:
	if not is_instance_valid(boss):
		return
	seen_slash_telegraph[0] = seen_slash_telegraph[0] or boss.get_node("VFX/SlashTelegraph").visible
	seen_lane[0] = seen_lane[0] or boss.get_node("VFX/DashLane").visible


func _track_hits(_amount: int, _remaining: int, _source: Vector3, player: PlayerLocal) -> void:
	hits_taken.append(_amount)
	player.get_node("Health").call_deferred("reset_to_full")


func count(move: StringName) -> int:
	return moves.count(move)


## Two lunges back to back, the second starting as soon as the first ends. A single lunge
## takes under 2 s, and the next normal one waits out a 3.5-5 s cooldown.
func has_dash_pair() -> bool:
	for i in range(1, moves.size()):
		if moves[i] != &"dash" or moves[i - 1] != &"dash":
			continue
		if move_times[i] - move_times[i - 1] < 2600:
			return true
	return false


## Keeps the carriers away from the boss until it has used `move`, so it has to come for them.
func fight_until(done: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline and not done.call():
		await wait(0.25)
		await _capture_telegraphs()
		_reposition_if_cornered()
	return done.call()


func _capture_telegraphs() -> void:
	for path in captures.keys():
		if not boss.get_node(path).visible:
			continue
		var file: String = captures[path]
		captures.erase(path)
		await shot(file)
		return


## Kites like players would: whenever the boss closes in, put the carriers at the far end again,
## so it has to lunge rather than slash.
func _reposition_if_cornered() -> void:
	if boss_state() == "attacking":
		return
	var to_boss: Vector3 = boss.global_position - players()[0].global_position
	if Vector2(to_boss.x, to_boss.z).length() > KITE_DISTANCE:
		return
	var far_end := w(0, -7) if boss.global_position.z < w(0, -11).z else w(0, -16)
	move_players(far_end)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	boss = find_boss()
	check("4GTN is in the arena, asleep", boss != null and boss.behavior is KatanaRobotBehavior and not boss.is_offensive)
	# Dev settings may scale boss hp in debug builds, so read the scene's own value from a fresh copy.
	var fresh := (load(boss.scene_file_path) as PackedScene).instantiate()
	check("4GTN has 180 hp in its scene", Health.from_target(fresh).max_hp == 180, str(Health.from_target(fresh).max_hp))
	print("INFO effective boss hp in this run: ", Health.from_target(boss).max_hp)
	fresh.free()
	check("the bridge to the arena starts on", bridge_solid(1) and bridge_solid(2))
	await check_robot_animates("4GTN idles with the shared Rig_Large clips", boss)
	await shot("katana_start.png")
	await overhead()
	get_tree().physics_frame.connect(_track_moves)
	get_tree().physics_frame.connect(_watch_telegraphs)
	for p in players():
		p.get_node("Health").damaged.connect(_track_hits.bind(p))

	# Real input: across the bridge into the arena, which switches the bridge off and wakes the boss.
	await cross(1, w(0, -7).z)
	var woke: bool = await wait_until(func(): return boss.is_offensive, 5.0)
	check("crossing wakes 4GTN", woke)
	var closed: bool = await wait_until(func(): return not bridge_solid(1) and not bridge_solid(2), 4.0)
	check("crossing switches the bridge off behind the carriers", closed)
	var bar := world.get_node("UI/BossHealthBar") as Control
	check("the boss health bar shows", bar.visible)
	var taunted: bool = await wait_until(func(): return count(&"taunt") > 0, 4.0)
	check("4GTN taunts when it wakes", taunted, str(moves))
	await wait(1.2)
	await shot("katana_awake.png")

	# Real rifle fire at the boss as it walks in.
	var shooter: PlayerLocal = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info().main_carrier
	var hp_before := Health.from_target(boss).current_hp
	Input.action_press(shooter.action_shoot)
	await wait(2.5)
	Input.action_release(shooter.action_shoot)
	var dealt := hp_before - Health.from_target(boss).current_hp
	print("INFO 2.5 s of rifle fire took %d hp off 4GTN" % dealt)
	check("real rifle bolts damage 4GTN", dealt > 0, str(dealt))

	# Phase 1: it should slash up close and lunge from range.
	# Stand still and let it walk up: no repositioning, or the carriers would never be in reach.
	var slashed: bool = await wait_until(func(): return count(&"slash") > 0, 20.0)
	await shot("katana_slash.png")
	check("phase 1: 4GTN slashes up close", slashed, str(moves))
	move_players(w(0, -7) if boss.global_position.z < w(0, -11).z else w(0, -16))
	var lunged: bool = await fight_until(func(): return count(&"dash") > 0 and boss_state() != "attacking", 25.0)
	check("phase 1: 4GTN lunges from range", lunged, str(moves))
	check("the slash shows its telegraph", seen_slash_telegraph[0])
	check("the lunge shows its lane", seen_lane[0])
	check("phase 1 has no plasma waves", count(&"waves") == 0, str(moves))
	check("phase 1 lunges come one at a time", not has_dash_pair(), str(moves))

	# Phase 2 at half health: blade glows, it speeds up, lunges in pairs and slams out plasma waves.
	var health := Health.from_target(boss)
	health.take_damage(health.current_hp - health.max_hp / 2, boss.global_position)
	await wait(0.2)
	var phase := BossPhaseController.from_enemy(boss)
	check("half health enters phase 2", phase.get_current_phase() == 2, str(phase.get_current_phase()))
	var light := boss.get_node("Robot/Rig_Large/Skeleton3D/KatanaHand/Katana/BladeLight") as OmniLight3D
	var particles := boss.get_node("Robot/Rig_Large/Skeleton3D/KatanaHand/Katana/FireParticles") as GPUParticles3D
	await wait(0.8)
	check("phase 2 charges the blade", light.light_energy > 1.0 and particles.emitting, "light %.1f" % light.light_energy)
	check("phase 2 speeds 4GTN up", is_equal_approx(boss.speed, 3.4), str(boss.speed))
	var wave_damage := [0]
	var waves_seen := [false]
	var wave_watch := func():
		for f in fireballs_in_flight():
			waves_seen[0] = true
			wave_damage[0] = f.damage
	get_tree().physics_frame.connect(wave_watch)
	var waved: bool = await fight_until(func(): return count(&"waves") > 0 and waves_seen[0], 30.0)
	await shot("katana_waves.png")
	check("phase 2: 4GTN slams out plasma waves", waved, str(moves))
	check("plasma waves hit for 1, not a one-shot", wave_damage[0] == 1, str(wave_damage[0]))
	var paired: bool = await fight_until(has_dash_pair, 30.0)
	check("phase 2: lunges come in pairs", paired, str(moves))
	get_tree().physics_frame.disconnect(wave_watch)
	print("INFO moves: ", moves)
	print("INFO hits on the carriers: ", hits_taken)
	check("every hit from 4GTN takes 1 hp", hits_taken.all(func(h): return h == 1), str(hits_taken))

	# The kill ends the level.
	health.take_damage(9999, boss.global_position)
	var finished: bool = await wait_until(func(): return state() == "levelfinished", 12.0)
	await shot("katana_finished.png")
	check("defeating 4GTN finishes the level", finished, state())
	print("RESULT fails=%d" % fails)
	get_tree().quit(0 if fails == 0 else 1)
