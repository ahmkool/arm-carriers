extends Node
## Test driver for the melee mech in world_playground.tscn: runs at the carriers like a skeleton, hurts them on
## contact, stays on the floor, dies, and comes back on respawn.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_melee_mech.gd res://src/world/levels/world_playground.tscn <out_dir> 200
## Other prototypes in the group are killed on waking, so the melee mech is watched on its own. The carriers are left
## vulnerable while it chases (dev settings give them 99 HP), so a touch can be seen to hurt one.

const GROUP := "Enemies/Prototype"
const SCENE := "res://src/enemy/enemy_melee_mech.tscn"
var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0

var states_seen := {}
var carrier_hits := 0
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
		if e.scene_file_path == SCENE:
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


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)


## Only the melee mech's own touches: contact damage comes from its position. Stray bolts and grenades from the
## prototypes removed at waking don't count.
func _on_carrier_hurt(_amount: int, _remaining: int, source: Vector3) -> void:
	var m := mech()
	if m == null or source.distance_to(m.global_position) > 0.5:
		return
	carrier_hits += 1


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


## A shot from a temporary camera beside the mech, to check the model, the axe and the pose.
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
	await wait(2.5)
	var m := mech()
	check("a melee mech, waiting", m != null and not m.is_offensive)
	if m == null:
		get_tree().quit(1)
		return
	check("stands on the floor", m.is_on_floor() and absf(m.global_position.y - floor_y()) < 0.3, "y=%.2f, carriers at %.2f" % [m.global_position.y, floor_y()])
	check("holds the mech axe, wings hidden", m.has_node("Mech/Rig_Medium/Skeleton3D/AxeHand/Axe") and not m.get_node("Mech/Rig_Medium/Skeleton3D/chest/CombatMech_WingLeft").visible)
	await closeup("01_closeup_asleep.png")

	var list := players()
	await hold([list[0].action_up, list[1].action_up], 2.2)
	await wait(0.5)
	if not m.is_offensive:
		info("the wake trigger didn't wake it (the playground's WakePrototype event has no enemy_group), so the test wakes it directly")
		m.is_offensive = true
	for other in enemies():
		if other != m:
			Health.apply_damage(other, 9999, other.global_position)
	# Vulnerable while it chases, so a touch can land; dev settings keep the carriers alive.
	for p in players():
		p.get_node("Health")._invulnerable_time_remaining = 0.0
		p.get_node("Health").damaged.connect(_on_carrier_hurt)
	info("carrier HP during the chase: %d" % players()[0].get_node("Health").current_hp)
	var start := nearest_player_distance(m)
	get_tree().physics_frame.connect(_sample)
	var reached: bool = await wait_until(func(): return carrier_hits > 0, 15.0)
	var closest := nearest_player_distance(m)
	await shot("02_contact.png")
	await wait(2.0)
	get_tree().physics_frame.disconnect(_sample)
	protect_players()
	info("states seen: %s" % str(states_seen.keys()))
	check("runs at the carriers", states_seen.has("running") and closest < start - 3.0, "%.1f m -> %.1f m" % [start, closest])
	check("touching a carrier hurts them", reached, "%d hits, damage %d each" % [carrier_hits, m.hitbox_damage])
	check("carriers survive thanks to dev HP, state still playing", state() == "playing", state())
	check("stays on the floor while chasing", lowest_lift > -0.3, "lowest %.2f m relative to the carriers' feet" % lowest_lift)

	Health.apply_damage(m, 9999, m.global_position + Vector3(0, 0, 2))
	await wait(0.5)
	check("dies", is_instance_valid(m) and mech_state(m) == "dead")
	await shot("04_dead.png")
	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.5)
	check("respawn brings it back, waiting", mech() != null and not mech().is_offensive)
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
