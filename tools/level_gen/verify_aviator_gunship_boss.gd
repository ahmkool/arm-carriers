extends Node
## Test driver for world_local_aviator_gunship_boss.tscn. Run through godot.sh, see docs/level-creation-for-agents.md.
## Uses real input to enter the arena and to fire the fork cannon. Carriers get a big health pool while the moves are
## measured, so hits show as lost HP instead of a game over. Save tracking is disabled.

const BOSS_HP := 150
const TOUGH_HP := 999
var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0

var moves_seen: Array = []
var sides_seen: Array = []
var bolts_seen := 0
var rockets_seen := 0
var _was_attacking := false
var _last_side := -1
var _seen_nodes := {}
var _watcher: Callable


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(380.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func health_of(node: Node) -> Health:
	return node.get_node("Health") as Health


func toughen_players(hp: int) -> void:
	for p in players():
		var h := health_of(p)
		h.max_hp = hp
		h.reset_to_full()


## Invulnerable carriers can't be knocked off the deck by a chain of hits; damage checks open short windows.
func protect(on: bool) -> void:
	for p in players():
		var h := health_of(p)
		if on:
			h.grant_invulnerability(9999.0)
			continue
		h.set("_invulnerable_time_remaining", 0.0)


func total_player_hp() -> int:
	var total := 0
	for p in players():
		total += health_of(p).current_hp
	return total


func place_pair(centre: Vector3, along: Vector3) -> void:
	var list := players()
	list[0].velocity = Vector3.ZERO
	list[1].velocity = Vector3.ZERO
	list[0].global_position = centre + along * 1.2
	list[1].global_position = centre - along * 1.2


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


func boss() -> EnemyLocal:
	var alive := world.get_node("Enemies/BossGroup/InstancedEnemies").get_children().filter(
		func(c): return c is EnemyLocal and c.is_alive())
	return alive[0] if not alive.is_empty() else null


func brain() -> AviatorGunshipBehavior:
	return boss().behavior as AviatorGunshipBehavior


func moves_node() -> GunshipMoves:
	return boss().get_node("GunshipMoves") as GunshipMoves


func current_move() -> StringName:
	var machine := boss().enemy_state_machine
	if not machine.is_in_state("attacking"):
		return &""
	return machine.get_node("Attacking").call("current_move")


func boss_hp() -> int:
	return health_of(boss()).current_hp


func flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Records every move the gunship starts, each side it settles on, and the bolts and rockets it puts in the world.
func watch() -> void:
	unwatch()
	for p in players():
		var h := health_of(p)
		var log_hit := func(amount: int, remaining: int, source: Vector3): print("INFO hit ", p.name, " -", amount, " left ", remaining, " from ", source, " move ", current_move() if boss() else &"")
		if not h.damaged.is_connected(log_hit):
			h.damaged.connect(log_hit)
	var gunship := boss()
	_was_attacking = false
	_last_side = -1
	_watcher = func():
		_trace()
		if not is_instance_valid(gunship) or not gunship.is_alive():
			return
		var attacking: bool = gunship.enemy_state_machine.is_in_state("attacking")
		if attacking and not _was_attacking:
			moves_seen.append(gunship.enemy_state_machine.get_node("Attacking").call("current_move"))
		_was_attacking = attacking
		var behavior := gunship.behavior as AviatorGunshipBehavior
		# The side changes when a flight starts; it counts as reached once the gunship hovers on its new station.
		var settled := flat_distance(gunship.global_position, behavior.station_point(behavior.current_lateral())) < 2.0
		if gunship.enemy_state_machine.is_in_state("hovering") and settled and behavior.side != _last_side:
			_last_side = behavior.side
			sides_seen.append(behavior.side)
		for child in world.get_children():
			if _seen_nodes.has(child):
				continue
			_seen_nodes[child] = true
			if child.scene_file_path.ends_with("laser_bolt_spawn.tscn"):
				bolts_seen += 1
			if child is GunshipRocket:
				rockets_seen += 1
	get_tree().physics_frame.connect(_watcher)


var _traced_state := ""
var _traced_boss := 0


## Prints each game state change and each new gunship instance, to explain an unexpected reset.
func _trace() -> void:
	var now := state()
	if now != _traced_state:
		print("INFO state -> ", now, " at ", Time.get_ticks_msec())
		_traced_state = now
	var gunship := boss()
	var id := gunship.get_instance_id() if gunship != null else 0
	if id == _traced_boss:
		return
	_traced_boss = id
	var hps := []
	for p in players():
		hps.append("%d@%s" % [health_of(p).current_hp, p.global_position])
	print("INFO gunship instance -> ", id, " offensive=", gunship.is_offensive if gunship else false, " players ", hps)


func unwatch() -> void:
	if _watcher.is_valid() and get_tree().physics_frame.is_connected(_watcher):
		get_tree().physics_frame.disconnect(_watcher)


func wait_for_move(move: StringName, timeout: float) -> bool:
	return await wait_until(func(): return boss() != null and current_move() == move, timeout)


func enter_arena() -> void:
	var list := players()
	await hold([list[0].action_up, list[1].action_up], 1.6)


# ---- Sections. ----

func check_start() -> void:
	var gunship := boss()
	var b := brain()
	check("the gunship waits, at full health", gunship != null and not gunship.is_offensive and boss_hp() == BOSS_HP, "hp=%d" % boss_hp())
	var north := b.station_point(0.0)
	check("it waits off the north edge", flat_distance(gunship.global_position, north) < 1.5,
		"at %s, station %s" % [gunship.global_position, north])
	check("it hovers about a metre above the deck", absf(gunship.global_position.y - (b.altitude())) < 0.6,
		"y=%.2f wanted %.2f" % [gunship.global_position.y, b.altitude()])


func check_wake_and_real_fire() -> void:
	brain().side_seconds_min = 999.0  # stay north while firing
	brain().side_seconds_max = 999.0
	await enter_arena()
	var woke := await wait_until(func(): return boss().is_offensive, 3.0)
	check("walking north wakes the gunship", woke)
	var bar := world.get_node_or_null("UI/BossHealthBar") as Control
	check("the boss bar shows", bar != null and bar.visible)
	await wait(0.6)
	await shot("gunship_awake.png")
	check("the gunship is on screen once awake", on_screen(boss().global_position))
	var hp_before := boss_hp()
	var list := players()
	await hold([list[0].action_shoot, list[1].action_shoot], 3.0)
	await wait(1.5)
	check("real fork cannon fire hurts the gunship", boss_hp() < hp_before, "%d -> %d" % [hp_before, boss_hp()])


func check_moves() -> void:
	moves_seen.clear()
	watch()
	# Guns and rockets: carriers standing still in the middle.
	var centre := brain().arena_center
	place_pair(centre + Vector3(0, 0, 3), Vector3.BACK)
	var saw_rockets := await wait_for_move(AviatorGunshipBehavior.MOVE_ROCKETS, 14.0)
	var hp_before := total_player_hp()
	protect(false)
	await wait(0.9)
	await shot("gunship_rockets.png")
	await wait(1.8)
	protect(true)
	check("rockets launch and land on the carriers", saw_rockets and rockets_seen >= 4 and total_player_hp() < hp_before,
		"rockets=%d hp %d -> %d" % [rockets_seen, hp_before, total_player_hp()])
	var saw_guns := await wait_for_move(AviatorGunshipBehavior.MOVE_GUNS, 12.0)
	await wait(2.0)
	check("a gun burst fires ten bolts", saw_guns and bolts_seen >= 10, "bolts=%d" % bolts_seen)

	# The laser: a pair standing in its path is hit; then the beam follows them along the edge.
	var saw_laser := await wait_for_move(AviatorGunshipBehavior.MOVE_LASER, 16.0)
	check("the gunship fires its laser", saw_laser, str(moves_seen))
	if not saw_laser:
		return
	var moves := moves_node()
	var path_point := moves.beam_origin() + moves.beam_direction() * 14.0
	place_pair(Vector3(path_point.x, centre.y, path_point.z), moves.beam_direction())
	await wait(0.6)
	await shot("gunship_laser_charge.png")
	hp_before = total_player_hp()
	var fired := await wait_until(func(): return moves.is_laser_firing(), 2.0)
	protect(false)
	await wait(0.25)
	protect(true)
	await shot("gunship_laser_fire.png")
	check("the laser hurts carriers in its path", fired and total_player_hp() <= hp_before - 6,
		"hp %d -> %d" % [hp_before, total_player_hp()])
	# Step out sideways: carriers 4 m off the beam are safe.
	var side_axis := moves.beam_direction().cross(Vector3.UP)
	place_pair(Vector3(path_point.x, centre.y, path_point.z) + side_axis * 4.5, moves.beam_direction())
	await get_tree().physics_frame
	var lateral_before := brain().current_lateral()
	hp_before = total_player_hp()
	protect(false)
	await wait(1.0)
	protect(true)
	var safe := total_player_hp() == hp_before or not moves.is_laser_firing()
	check("carriers 4.5 m off the beam are safe for a moment", safe, "hp %d -> %d" % [hp_before, total_player_hp()])
	var slid := absf(brain().current_lateral() - lateral_before)
	check("the gunship slides towards them while firing, slowly", slid > 0.5 and slid < 3.5, "slid %.2f m in 1 s" % slid)
	await wait_until(func(): return not moves.is_laser_firing(), 4.0)


func check_side_switches() -> void:
	var b := brain()
	b.side_seconds_min = 5.0
	b.side_seconds_max = 6.0
	b.call("finish_relocation")  # restart the side timer with the short values
	sides_seen.clear()
	var arrivals := 0
	var framed := 0
	var facing_ok := 0
	var deadline := Time.get_ticks_msec() + 40000
	var seen_count := 0
	while Time.get_ticks_msec() < deadline and arrivals < 4:
		await get_tree().physics_frame
		if sides_seen.size() == seen_count:
			continue
		seen_count = sides_seen.size()
		arrivals += 1
		var gunship := boss()
		var arrived_side: int = sides_seen[-1]
		var wanted_facing := -AviatorGunshipBehavior.SIDES[arrived_side]
		await wait(0.5)
		var face := -gunship.global_basis.z
		if Vector3(face.x, 0, face.z).normalized().dot(wanted_facing) > 0.95:
			facing_ok += 1
		if on_screen(gunship.global_position):
			framed += 1
		await shot("gunship_side_%s.png" % AviatorGunshipBehavior.SIDE_NAMES[arrived_side])
	var distinct := {}
	for s in sides_seen:
		distinct[s] = true
	check("it changes sides on its timer", arrivals >= 3 and distinct.size() >= 3, "sides %s" % str(sides_seen))
	check("on each side it faces back across the deck", facing_ok == arrivals, "%d of %d" % [facing_ok, arrivals])
	check("the camera keeps it on screen on every side", framed == arrivals, "%d of %d" % [framed, arrivals])


func check_enrage() -> void:
	Health.apply_damage(boss(), boss_hp() - BOSS_HP / 2 + 1, boss().global_position)
	await wait(0.3)
	check("at half health it enrages", brain().is_enraged())


func check_death_and_respawn() -> void:
	unwatch()
	for p in players():
		var h := health_of(p)
		h.max_hp = 3
		h.reset_to_full()
	protect(false)
	var centre := brain().arena_center
	place_pair(centre, Vector3.BACK)
	var lost := await wait_until(func(): return state() == "gameoverlost", 45.0)
	check("standing still under fire is a game over", lost, state())
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	var gunship := boss()
	check("respawn resets the gunship: waiting at full health", gunship != null and not gunship.is_offensive and boss_hp() == BOSS_HP,
		"hp=%d" % (boss_hp() if gunship else -1))
	check("respawn puts it back off the north edge", gunship != null and flat_distance(gunship.global_position, brain().station_point(0.0)) < 1.5)


func check_win() -> void:
	toughen_players(TOUGH_HP)
	protect(true)
	await enter_arena()
	await wait_until(func(): return boss().is_offensive, 3.0)
	Health.apply_damage(boss(), 999, boss().global_position)
	var won := await wait_until(func(): return state() == "levelfinished", 10.0)
	check("downing the gunship finishes the level", won, state())


func _run() -> void:
	var ok := await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.5)
	await shot("gunship_start.png")
	print("INFO fps at start: ", Engine.get_frames_per_second())
	check_start()
	toughen_players(TOUGH_HP)
	protect(true)
	await check_wake_and_real_fire()
	await check_moves()
	await check_side_switches()
	await check_enrage()
	await check_death_and_respawn()
	await check_win()
	print("INFO moves seen: ", moves_seen)
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)
