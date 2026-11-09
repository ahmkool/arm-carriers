extends Node
## Test driver for the ground mech in world_playground.tscn: walks in to firing range, fires bursts along its barrel,
## backs off from carriers who come close, stays on the floor, dies, comes back on respawn.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_ground_mech.gd res://src/world/levels/world_playground.tscn <out_dir> 200
## Other prototypes in the group are killed on waking, so the ground mech is watched on its own.

const GROUP := "Enemies/Prototype"
var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0

var states_seen := {}
## Angle in degrees between the barrel and each bolt's launch direction, as each bolt leaves.
var bolt_errors: Array[float] = []
var lowest_lift := INF
var _shot_states := {}
var _closeup_busy := false


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(170.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	get_tree().node_added.connect(_on_node_added)
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
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func floor_y() -> float:
	var lowest := INF
	for p in players():
		lowest = minf(lowest, p.global_position.y)
	return lowest


func enemies() -> Array:
	return world.get_node(GROUP).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func mech() -> EnemyLocal:
	for e in enemies():
		if e.behavior is GroundMechBehavior and (e.behavior as GroundMechBehavior).attack_state == &"shooting":
			return e
	return null


func mech_state(m: EnemyLocal) -> String:
	return String(m.enemy_state_machine.current_state.name).to_lower()


func nearest_player_distance(m: EnemyLocal) -> float:
	var nearest := INF
	for p in players():
		var d: Vector3 = p.global_position - m.global_position
		nearest = minf(nearest, Vector2(d.x, d.z).length())
	return nearest


func muzzle(m: EnemyLocal) -> Node3D:
	return m.get_node("Visual/Mech/Rig_Medium/Skeleton3D/GunHand/Minigun/Muzzle") as Node3D


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)


## Each bolt the ground mech fires: how far its launch direction is from where the barrel points.
func _on_node_added(node: Node) -> void:
	if not node is FireballSpawn:
		return
	_measure_bolt.call_deferred(node)


func _measure_bolt(spawn: FireballSpawn) -> void:
	var m := mech()
	if m == null or not is_instance_valid(spawn):
		return
	if spawn.global_position.distance_to(muzzle(m).global_position) > 0.3:
		return
	var launch: Vector3 = spawn._launch_velocity.normalized()
	bolt_errors.append(rad_to_deg(launch.angle_to(muzzle(m).global_basis.z.normalized())))


func _sample() -> void:
	var m := mech()
	if m == null:
		return
	var s := mech_state(m)
	states_seen[s] = true
	lowest_lift = minf(lowest_lift, m.global_position.y - floor_y())
	if _shot_states.has(s):
		return
	_shot_states[s] = true
	_state_shots.call_deferred(s)


func _state_shots(s: String) -> void:
	await shot("03_state_%s.png" % s)
	await closeup("03_closeup_%s.png" % s)


## A shot from a temporary camera beside the mech, to check the model, the gun and the pose.
func closeup(file_name: String) -> void:
	var m := mech()
	if m == null or _closeup_busy:
		return
	_closeup_busy = true
	var game_camera := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	world.add_child(cam)
	var side := m.global_basis.x * 3.5 - m.global_basis.z * 3.0 + Vector3.UP * 1.0
	cam.global_position = m.global_position + Vector3.UP * 1.3 + side
	cam.look_at(m.global_position + Vector3.UP * 1.3, Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await shot(file_name)
	game_camera.make_current()
	cam.queue_free()
	_closeup_busy = false


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.5)
	var m := mech()
	check("a ground mech, waiting", m != null and not m.is_offensive)
	if m == null:
		get_tree().quit(1)
		return
	check("stands on the floor", m.is_on_floor() and absf(m.global_position.y - floor_y()) < 0.3, "y=%.2f, carriers at %.2f" % [m.global_position.y, floor_y()])
	check("starts standing", mech_state(m) == "standing", mech_state(m))
	check("its wings are hidden", not m.get_node("Visual/Mech/Rig_Medium/Skeleton3D/chest/CombatMech_WingLeft").visible)
	await closeup("01_closeup_asleep.png")

	var list := players()
	await hold([list[0].action_up, list[1].action_up], 2.2)
	await wait(0.5)
	check("wake trigger makes the ground mech offensive", m.is_offensive)
	for other in enemies():
		if other != m:
			Health.apply_damage(other, 9999, other.global_position)
	protect_players()
	var start_distance := nearest_player_distance(m)
	get_tree().physics_frame.connect(_sample)
	await wait(3.0)
	await shot("02_awake.png")
	var bands: Array[float] = []
	for i in 10:
		await wait(1.5)
		bands.append(nearest_player_distance(m))
	get_tree().physics_frame.disconnect(_sample)
	info("states seen: %s" % str(states_seen.keys()))
	info("distance to the nearer carrier: %.1f m at waking, then %s" % [start_distance, str(bands.map(func(d): return "%.1f" % d))])
	check("walks in toward the carriers", states_seen.has("walking"))
	check("settles within firing range", bands.slice(4).all(func(d): return d <= 12.0), str(bands.slice(4)))
	check("fires gun bursts", states_seen.has("shooting") and bolt_errors.size() >= 3, "%d bolts" % bolt_errors.size())
	var worst := 0.0
	var total := 0.0
	for e in bolt_errors:
		worst = maxf(worst, e)
		total += e
	var average := total / maxf(bolt_errors.size(), 1)
	check("bolts leave along the barrel", bolt_errors.size() > 0 and average < 6.0 and worst < 15.0, "average %.1f, worst %.1f degrees over %d bolts" % [average, worst, bolt_errors.size()])
	check("stays on the floor while fighting", lowest_lift > -0.3, "lowest %.2f m relative to the carriers' feet" % lowest_lift)

	# A carrier walking right up to it: it backs away rather than standing in reach.
	var close: Vector3 = m.global_position + (players()[0].global_position - m.global_position).normalized() * 2.5
	close.y = players()[0].global_position.y
	players()[0].global_position = close
	players()[1].global_position = close + (close - m.global_position).normalized() * 2.0
	await wait_until(func(): return mech_state(m) != "shooting", 3.0)
	var before := nearest_player_distance(m)
	await wait(2.0)
	var after := nearest_player_distance(m)
	check("backs off from carriers who come close", after > before + 1.0, "%.1f -> %.1f m" % [before, after])
	check("still on the floor after backing off", m.is_on_floor() and state() == "playing", "y=%.2f" % m.global_position.y)

	Health.apply_damage(m, 9999, m.global_position + Vector3(0, 0, 2))
	await wait(0.5)
	check("dies", is_instance_valid(m) and mech_state(m) == "dead")
	await shot("04_dead.png")

	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.0)
	check("respawn brings it back, waiting", mech() != null and not mech().is_offensive)
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
