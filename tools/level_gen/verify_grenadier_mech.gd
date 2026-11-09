extends Node
## Test driver for the grenadier mech in world_playground.tscn: walks in to range, fires grenades level along its barrel
## that land where the carriers stood, a ring shows the blast during the fuse, the blast hurts carriers inside it,
## it backs off from carriers who come close, dies, and comes back on respawn.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_grenadier_mech.gd res://src/world/levels/world_playground.tscn <out_dir> 200
## Other prototypes in the group are killed on waking, so the grenadier is watched on its own. The carriers are left
## vulnerable while it fights (dev settings give them 99 HP), so a blast can be seen to hurt one.

const GROUP := "Enemies/Prototype"
var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0

var states_seen := {}
## One entry per grenade: {grenade, target (where the target stood at launch), barrel_error, landed_at, landed_time, exploded_time}
var grenades: Array[Dictionary] = []
var carrier_hits := 0
var lowest_lift := INF
var _shot_states := {}
var _closeup_busy := false
var _ring_shot_taken := false


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


func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func shot(file_name: String) -> void:
	await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func players() -> Array:
	return world.players.get_children().filter(func(c): return c is PlayerLocal)


func protect_players(seconds: float = 9999.0) -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(seconds)


func floor_y() -> float:
	var lowest := INF
	for p in players():
		lowest = minf(lowest, p.global_position.y)
	return lowest


func enemies() -> Array:
	return world.get_node(GROUP).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func mech() -> EnemyLocal:
	for e in enemies():
		if e.behavior is GroundMechBehavior and (e.behavior as GroundMechBehavior).attack_state == &"lobbing":
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
	return m.get_node("Visual/Mech/Rig_Medium/Skeleton3D/GunHand/Launcher/Muzzle") as Node3D


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)


func _on_node_added(node: Node) -> void:
	if node is MechGrenade:
		_track_grenade.call_deferred(node)


## Notes where the grenade was aimed and how far its launch is from the barrel, then follows it to the blast.
func _track_grenade(grenade: MechGrenade) -> void:
	var m := mech()
	if m == null or not is_instance_valid(grenade):
		return
	var entry := {"grenade": grenade, "target": m.target_player.global_position,
		"barrel_error": rad_to_deg(grenade.velocity.normalized().angle_to(muzzle(m).global_basis.z.normalized())),
		"barrel_pitch": rad_to_deg(asin(clampf(muzzle(m).global_basis.z.normalized().y, -1.0, 1.0))),
		"landed_at": Vector3.INF, "landed_time": -1.0, "exploded_time": -1.0}
	grenades.append(entry)
	await wait_until(func(): return not is_instance_valid(grenade) or grenade.is_armed(), 4.0)
	if not is_instance_valid(grenade):
		return
	entry["landed_at"] = grenade.global_position
	entry["landed_time"] = now()
	if not _ring_shot_taken:
		_ring_shot_taken = true
		await wait(0.6)
		await shot("04_grenade_ring.png")
	await wait_until(func(): return not is_instance_valid(grenade), 5.0)
	entry["exploded_time"] = now()


func _on_carrier_hurt(_amount: int, _remaining: int, _source: Vector3) -> void:
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


## A shot from a temporary camera beside the mech, to check the model, the launcher and the pose.
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
	check("a grenadier mech, waiting", m != null and not m.is_offensive)
	if m == null:
		get_tree().quit(1)
		return
	check("stands on the floor", m.is_on_floor() and absf(m.global_position.y - floor_y()) < 0.3, "y=%.2f, carriers at %.2f" % [m.global_position.y, floor_y()])
	check("holds the grenade launcher, not the minigun", m.has_node("Visual/Mech/Rig_Medium/Skeleton3D/GunHand/Launcher") and not m.has_node("Visual/Mech/Rig_Medium/Skeleton3D/GunHand/Minigun"))
	await closeup("01_closeup_asleep.png")

	var list := players()
	await hold([list[0].action_up, list[1].action_up], 2.2)
	await wait(0.5)
	check("wake trigger makes the grenadier offensive", m.is_offensive)
	for other in enemies():
		if other != m:
			Health.apply_damage(other, 9999, other.global_position)
	# Vulnerable while it fights, so a blast can land a hit; dev settings keep the carriers alive.
	for p in players():
		p.get_node("Health")._invulnerable_time_remaining = 0.0
		p.get_node("Health").damaged.connect(_on_carrier_hurt)
	info("carrier HP during the fight: %d" % players()[0].get_node("Health").current_hp)
	get_tree().physics_frame.connect(_sample)
	await wait(3.0)
	await shot("02_awake.png")
	var bands: Array[float] = []
	for i in 10:
		await wait(1.6)
		bands.append(nearest_player_distance(m))
	get_tree().physics_frame.disconnect(_sample)
	protect_players()
	await wait(2.5)
	info("states seen: %s" % str(states_seen.keys()))
	info("distance to the nearer carrier: %s" % str(bands.map(func(d): return "%.1f" % d)))
	check("walks in toward the carriers", states_seen.has("walking"))
	check("settles within lobbing range", bands.slice(4).all(func(d): return d <= 13.0), str(bands.slice(4).map(func(d): return "%.1f" % d)))
	check("lobs grenades", states_seen.has("lobbing") and grenades.size() >= 2, "%d grenades" % grenades.size())
	_check_grenades()
	check("a blast hurts a carrier standing in its ring", carrier_hits > 0, "%d hits" % carrier_hits)
	check("carriers survive thanks to dev HP, state still playing", state() == "playing", state())
	check("stays on the floor while fighting", lowest_lift > -0.3, "lowest %.2f m relative to the carriers' feet" % lowest_lift)

	var close: Vector3 = m.global_position + (players()[0].global_position - m.global_position).normalized() * 2.5
	close.y = players()[0].global_position.y
	players()[0].global_position = close
	players()[1].global_position = close + (close - m.global_position).normalized() * 2.0
	await wait_until(func(): return mech_state(m) != "lobbing", 4.0)
	var before := nearest_player_distance(m)
	await wait(2.0)
	var after := nearest_player_distance(m)
	check("backs off from carriers who come close", after > before + 1.0, "%.1f -> %.1f m" % [before, after])

	Health.apply_damage(m, 9999, m.global_position + Vector3(0, 0, 2))
	await wait(0.5)
	check("dies", is_instance_valid(m) and mech_state(m) == "dead")
	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.0)
	check("respawn brings it back, waiting", mech() != null and not mech().is_offensive)
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _check_grenades() -> void:
	var landed := grenades.filter(func(g): return g["landed_time"] >= 0.0)
	# Only grenades whose fuse should have run out by now; the last may still be ticking.
	var due := landed.filter(func(g): return now() - g["landed_time"] > 2.2)
	var exploded := due.filter(func(g): return g["exploded_time"] >= 0.0)
	var worst_barrel := 0.0
	var worst_miss := 0.0
	var fuses: Array[String] = []
	for g in grenades:
		worst_barrel = maxf(worst_barrel, g["barrel_error"])
	for g in landed:
		var miss: Vector3 = g["landed_at"] - g["target"]
		worst_miss = maxf(worst_miss, Vector2(miss.x, miss.z).length())
	for g in exploded:
		fuses.append("%.2f" % (g["exploded_time"] - g["landed_time"]))
	var worst_pitch := 0.0
	for g in grenades:
		worst_pitch = maxf(worst_pitch, absf(g["barrel_pitch"]))
	check("the launcher is level when it fires", grenades.size() > 0 and worst_pitch < 6.0, "worst barrel pitch %.1f degrees" % worst_pitch)
	check("grenades leave along the barrel", grenades.size() > 0 and worst_barrel < 12.0, "worst %.1f degrees over %d grenades" % [worst_barrel, grenades.size()])
	check("grenades land where the target stood at launch", landed.size() > 0 and worst_miss < 1.5, "worst %.2f m over %d landings" % [worst_miss, landed.size()])
	check("each landed grenade explodes after its fuse", due.size() > 0 and exploded.size() == due.size() and fuses.all(func(f): return absf(float(f) - 1.8) < 0.3), "fuses %s" % str(fuses))
