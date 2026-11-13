extends Node
## Test driver for world_local_castle_siege.tscn. Run through godot.sh, see docs/level-creation-for-agents.md.
## Real input for walking, aiming and the catapult shot at a wall crossbowman; the rest of each fight is killed by script.
## Save tracking is disabled, so save.json stays untouched.

const WALL_TOP := 3.0
const FLOOR_TOP := -1.0
## The hill on the ledge's west edge spans cells x -5 and -4; the pocket behind it, cells x -10 to -6.
const HILL_EAST_FACE := -8.997
const HILL_WEST_FACE := -14.995
const POCKET_EAST := -14.995
const POCKET_WEST := -29.99
## The ledge's east edge, at the chasm (cell x = 3 starts at 3 * 2.999).
const LEDGE_EAST := 8.997
const ISLAND_GROUPS := ["IslandChasers", "IslandCatapults", "TowerGuards"]
## Section 4's S, as corner cells (build_castle_siege.py's S_BRIDGE), and its first outcrop: the junction cell and
## where it points.
const S_BRIDGE := [Vector2i(-1, -45), Vector2i(-1, -48), Vector2i(5, -48), Vector2i(5, -54), Vector2i(-7, -54), Vector2i(-7, -60), Vector2i(-1, -60), Vector2i(-1, -62)]
const OUTCROP_JUNCTION := Vector2i(-1, -46)
const OUTCROP_TIP_X := -8.997
## The castle front: the field's north edge at the chasm, and the balconies' tops (build_castle_siege.py).
const FRONT_EDGE_X := 17.994  # the field's east edge at the chasm: cell column 5 ends at 6 * 2.999
const GATE_Z := -208.43  # the gate's middle row, -70
const BALCONY_TOP := 1.0  # the first outcrop's far edge (cell x -3 starts at -3 * 2.999)
## The environment's fog between gusts (build_castle_siege.py).
const CALM_FOG := 0.0025

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var specifics: CatapultSpecifics
var shooter: PlayerLocal
var setter: PlayerLocal
var explosions: Array = []
var fireball_closest := [INF]
var fireball_dives := [0]
var fireballs_seen := {}


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(600.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	_run.call_deferred()


func check(label: String, ok: bool, detail: String = "") -> void:
	print(("PASS " if ok else "FAIL ") + label + ("" if detail.is_empty() else "  [" + detail + "]"))
	if not ok:
		fails += 1


func w(cx: int, cz: int, y: float = 0.0) -> Vector3:
	return Vector3((cx + 0.5) * 2.999, y, (cz + 0.5) * 2.999)


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


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


## Holds `actions` until `cond` is true, or the time runs out.
func hold_until(actions: Array, cond: Callable, timeout: float) -> bool:
	for a in actions:
		Input.action_press(a)
	var ok: bool = await wait_until(cond, timeout)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame
	return ok


func gap() -> float:
	var d: Vector3 = setter.global_position - shooter.global_position
	return Vector2(d.x, d.z).length()


func on_screen(point: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return not cam.is_position_behind(point) and rect.has_point(cam.unproject_position(point))


func count_on_screen(nodes: Array) -> int:
	return nodes.filter(func(n): return on_screen(n.global_position + Vector3.UP)).size()


func alive(group: String) -> Array:
	return world.get_node("Enemies/" + group).get_node("InstancedEnemies").get_children().filter(
		func(c): return c is EnemyLocal and c.is_alive())


func kill(enemies: Array) -> void:
	for e in enemies:
		Health.apply_damage(e, 9999, e.global_position)


func bridge_y(index: int) -> float:
	return (world.get_node("Level/Bridges/BridgePlatform%d/AnimatableBody3D" % index) as Node3D).global_position.y


func cp() -> String:
	return String(world.checkpoint_manager.current_checkpoint.name)


func focal_count() -> int:
	return (world.get_node("CameraFollowRig") as CameraFollowRig)._extra_focal_nodes.size()


## A close-up of `enemy` from in front and to one side, since the level camera looks down from far away.
func close_up(enemy: EnemyLocal, file_name: String) -> void:
	var cam := Camera3D.new()
	world.add_child(cam)
	var facing := -enemy.global_basis.z
	facing = Vector3(facing.x, 0.0, facing.z).normalized()
	cam.global_position = enemy.global_position + facing * 3.2 + facing.cross(Vector3.UP) * 2.2 + Vector3.UP * 1.6
	cam.look_at(enemy.global_position + Vector3.UP * 1.0)
	cam.make_current()
	await wait(0.05)
	await shot(file_name)
	cam.queue_free()
	world.get_node("CameraFollowRig/ShakePivot/Camera3D").make_current()


func bind_carriers() -> void:
	var catapult := world.get_node("Weapon/Catapult") as Node3D
	specifics = catapult.get_node("WeaponSpecifics") as CatapultSpecifics
	var carry: CarryInfo = (catapult.get_node("PickAndDropHandler") as PickAndDropHandler).get_carry_info()
	shooter = carry.main_carrier
	setter = carry.secondary_carrier
	if not specifics.fired.is_connected(on_fired):
		specifics.fired.connect(on_fired)


func on_fired(bomb: CatapultBomb, _launch_deg: float) -> void:
	bomb.exploded.connect(func(at: Vector3): explosions.append(at))


func current_flight() -> Dictionary:
	return specifics.predict_flight(specifics.get_launch_angle_deg(gap()), shooter)


func press_shoot() -> void:
	Input.action_press(shooter.action_shoot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(shooter.action_shoot)
	await get_tree().physics_frame


## Tracks every enemy shot: how close it passes to a carrier's chest, and whether it flies downwards.
func watch_fireballs() -> void:
	for node in get_tree().get_nodes_in_group(Checkpoint.ENEMY_PROJECTILE_GROUP):
		_watch_fireball(node as Node3D)


func _watch_fireball(ball: Node3D) -> void:
	if ball == null or ball is CatapultBomb:
		return
	var velocity = ball.get("velocity")
	if velocity is Vector3 and not fireballs_seen.has(ball.get_instance_id()) and (velocity as Vector3).length() > 0.1:
		fireballs_seen[ball.get_instance_id()] = true
		if (velocity as Vector3).y < -0.3:
			fireball_dives[0] += 1
	for p in players():
		fireball_closest[0] = minf(fireball_closest[0], ball.global_position.distance_to(p.global_position + Vector3.UP))


func flat_forward() -> Vector3:
	var forward: Vector3 = specifics.global_basis.z
	forward.y = 0.0
	return forward.normalized()


## Steps the back carrier in or out until the ring's centre is level with `target` along the throw, for a pair facing
## east or west. The front carrier stays put (at the chasm's edge, or short of the hill): stepping back stretches the
## gap, which throws further by more than the step.
func aim_range_at(target: Vector3) -> float:
	var f := flat_forward()
	var back := (shooter.action_left if f.x > 0.0 else shooter.action_right) if absf(f.x) > absf(f.z) else (shooter.action_down if f.z < 0.0 else shooter.action_up)
	var toward := (shooter.action_right if f.x > 0.0 else shooter.action_left) if absf(f.x) > absf(f.z) else (shooter.action_up if f.z < 0.0 else shooter.action_down)
	for step in 50:
		var error: float = (target - current_flight().landing).dot(flat_forward())
		if absf(error) < 0.5:
			return error
		await hold([back if error > 0.0 else toward], 0.05)
		await wait(0.05)
	return (target - current_flight().landing).dot(flat_forward())


## Turns the pair in place: the front carrier walks `front_dir`, the back carrier the opposite way, until `facing`.
func turn_to(front_action: String, back_action: String, facing: Vector3) -> bool:
	return await hold_until([setter.get(front_action), shooter.get(back_action)], func(): return flat_forward().dot(facing) > 0.995, 4.0)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(2.0)
	bind_carriers()
	check("both players carry the catapult", is_instance_valid(shooter) and is_instance_valid(setter))
	get_tree().physics_frame.connect(watch_fireballs)
	get_tree().physics_frame.connect(watch_game_over)
	# SIEGE_START=5 starts at Checkpoint5 and tests only the castle front, to iterate on it without the rest.
	if OS.get_environment("SIEGE_START") == "5":
		await start_at("Checkpoint5")
		await castle_front_section()
		await finish()
		return
	check("the catapult skeleton waits in his pocket from the start", alive("CatapultCrew").size() == 1 and not alive("CatapultCrew")[0].is_offensive)
	check("the islands' enemies aren't there yet", ISLAND_GROUPS.all(func(g): return alive(g).is_empty()))
	await shot("01_spawn.png")
	await overview("01b_overview_ledges.png", Vector3(2, 34, 14), Vector3(4, -4, -16))
	await overview("01c_overview_islands.png", Vector3(-6, 40, -40), Vector3(-8, -4, -86))
	await wall_section()
	await cross_to_second_ledge()
	await catapult_section()
	await islands_section()
	await s_bridge_section()
	await castle_front_section()
	await finish()


func finish() -> void:
	await face_east_on_row(GATE_Z)
	var ok: bool = await hold_until([shooter.action_right, setter.action_right], func(): return state() != "playing", 12.0)
	check("real input: crossing the stone bridge through the gate finishes the level", ok and state().contains("finished"), state())
	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func start_at(checkpoint_name: String) -> void:
	world.checkpoint_manager.current_checkpoint = world.get_node("CheckpointManager/" + checkpoint_name) as Checkpoint
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 10.0)
	await wait(1.5)
	protect_players()
	bind_carriers()
	check("starts at " + checkpoint_name, cp() == checkpoint_name, cp())


## (5) The castle front: an endless horde until the wall's crossbowmen and the balcony catapults are dead; a real bomb
## over the wall kills a balcony catapult.
func castle_front_section() -> void:
	await face_north_on_column(w(-1, 0).x)
	var horde := world.get_node("Enemies/FrontHorde") as SurvivalEnemyGroup
	var ok: bool = await hold_until([shooter.action_up, setter.action_up], func(): return horde.is_running(), 10.0)
	check("real input: stepping into the field starts the castle front", ok and state() == "playing", "shooter z=%.1f state=%s" % [shooter.global_position.z, state()])
	await wait(2.5)
	check("bridge 4 lowers behind the carriers", bridge_y(13) < -5.0, "y=%.2f" % bridge_y(13))
	var guards := alive("FrontGuards")
	var crews := alive("FrontCatapults")
	check("six crossbowmen on the front wall, three catapult skeletons on the balconies", guards.size() == 6 and crews.size() == 3, "%d/%d" % [guards.size(), crews.size()])
	check("the crossbowmen stand on the wall walk", guards.all(func(e): return absf(e.global_position.y - WALL_TOP) < 0.6))
	check("the catapult skeletons stand on the balconies", crews.all(func(e): return absf(e.global_position.y - BALCONY_TOP) < 0.4), str(crews.map(func(e): return snappedf(e.global_position.y, 0.01))))
	check("nobody can walk to the wall or the balconies", (guards + crews).all(func(e): return not path_reaches(shooter.global_position, e.global_position)))
	check("the field is framed", focal_count() == 4, str(focal_count()))
	var crew_throws := [0]
	for crew in crews:
		(crew.get_node("SiegeCatapult") as SiegeCatapult).fired.connect(func(_b): crew_throws[0] += 1)
	await overview("14_castle_front_overview.png", Vector3(0, 36, -190), Vector3(-2, -4, -232))

	# The pair turns to face the wall, lines up on the nearest balcony's row and walks to the chasm's edge.
	var target: EnemyLocal = crews.reduce(func(best, e): return e if absf(e.global_position.z - shooter.global_position.z) < absf(best.global_position.z - shooter.global_position.z) else best)
	await face_east_on_row(target.global_position.z)
	await hold_until([shooter.action_right, setter.action_right], func(): return setter.global_position.x > FRONT_EDGE_X - 0.8, 8.0)
	await wait(0.5)
	var spawned := horde.get_node("Enemies").get_child_count()
	check("the horde keeps coming", spawned >= 3, "%d spawned so far" % spawned)
	check("the balcony catapults throw over the wall", crew_throws[0] > 0, str(crew_throws[0]))
	for deg in [82.0, 70.0, 60.0, 52.0, 45.0]:
		print("INFO   from the chasm's edge at %.0f deg: lands %s" % [deg, specifics.predict_flight(deg, shooter).landing])
	for attempt in 3:
		if not target.is_alive():
			break
		await line_up_z(target.global_position.z)
		var error := await aim_by_sweep(target.global_position)
		var landing: Vector3 = current_flight().landing
		var reach := Vector2(landing.x - target.global_position.x, landing.z - target.global_position.z).length()
		print("INFO aimed over the front wall: error %.2f m, gap %.2f, landing %s, skeleton %s, %.2f m from him" % [error, gap(), landing, target.global_position, reach])
		if attempt == 0:
			check("over the wall, the ring lands on his balcony within the blast of him", absf(landing.y - BALCONY_TOP) < 0.3 and reach < 3.5, "%.2f m, landing %s" % [reach, landing])
			await shot("15_aimed_over_front_wall.png")
		await wait_until(func(): return specifics.is_loaded(), 3.0)
		await press_shoot()
		await wait_until(func(): return not target.is_alive(), 3.5)
	check("real input: a bomb over the wall kills a balcony catapult skeleton", not target.is_alive())
	await shot("16_castle_front_fight.png")

	# The crossbowmen by script: the horde keeps coming while a catapult lives.
	kill(alive("FrontGuards"))
	await wait(4.0)
	check("with catapults left, the horde still spawns", horde.is_spawning() and cp() == "Checkpoint5", "spawning %s cp %s" % [horde.is_spawning(), cp()])
	check("at most 8 of the horde alive at once", horde.get_node("Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive()).size() <= 8)
	kill(alive("FrontCatapults"))
	ok = await wait_until(func(): return bridge_y(14) > -1.5, 8.0)
	check("clearing the wall stops the horde", not horde.is_spawning())
	check("clearing the wall sets Checkpoint6", cp() == "Checkpoint6", cp())
	check("clearing the wall raises the stone bridge to the gate", ok, "y=%.2f" % bridge_y(14))
	var left := horde.get_node("Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive()).size()
	await wait(3.0)
	var after := horde.get_node("Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive()).size()
	check("no more skeletons appear", after <= left, "%d -> %d" % [left, after])
	ok = await wait_until(func():
		kill(horde.get_node("Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive()))
		return horde.signal_emitted, 6.0)
	check("once the ones left are dead, the horde is done", ok)
	await wait(1.0)
	protect_players()


## Turns the pair to face east (from facing north, the front carrier walking right and the back one left), then
## side-steps it until its middle is level with `z`.
func face_east_on_row(z: float) -> void:
	if flat_forward().dot(Vector3.RIGHT) < 0.9:
		await turn_to("action_right", "action_left", Vector3.RIGHT)
	var mid := func(): return (shooter.global_position.z + setter.global_position.z) * 0.5
	var south: bool = mid.call() < z
	var actions := [shooter.action_down, setter.action_down] if south else [shooter.action_up, setter.action_up]
	await hold_until(actions, func(): return (mid.call() >= z - 0.3) if south else (mid.call() <= z + 0.3), 4.0)
	await wait(0.3)


## For a target behind cover, where the landing jumps (a step back can move the ring from the target onto the cover):
## the back carrier steps back through the whole gap range, from the front carrier's spot, noting where each throw
## lands, then comes forward to the gap whose ring fell nearest the target. Returns that distance.
func aim_by_sweep(target: Vector3) -> float:
	var f := flat_forward()
	var back := (shooter.action_left if f.x > 0.0 else shooter.action_right) if absf(f.x) > absf(f.z) else (shooter.action_down if f.z < 0.0 else shooter.action_up)
	var toward := (shooter.action_right if f.x > 0.0 else shooter.action_left) if absf(f.x) > absf(f.z) else (shooter.action_up if f.z < 0.0 else shooter.action_down)
	await hold_until([toward], func(): return gap() < 4.2, 2.0)
	print("INFO sweep from: shooter %s setter %s gap %.2f forward %s" % [shooter.global_position, setter.global_position, gap(), flat_forward()])
	var best_gap := gap()
	var best := INF
	for step in 60:
		var landing: Vector3 = current_flight().landing
		var miss := Vector2(landing.x - target.x, landing.z - target.z).length()
		if miss < best:
			best = miss
			best_gap = gap()
		if step % 10 == 0:
			print("INFO   sweep gap %.2f ring %s" % [gap(), landing])
		if gap() > 7.4:
			break
		await hold([back], 0.04)
		await wait(0.03)
	print("INFO sweep: best ring %.2f m from the target at gap %.2f" % [best, best_gap])
	await hold_until([toward], func(): return gap() <= best_gap + 0.05, 3.0)
	await wait(0.2)
	var final: Vector3 = current_flight().landing
	return Vector2(final.x - target.x, final.z - target.z).length()


## Side-steps the pair (facing north) until the ring is level with `x`.
func line_up_x_ring(x: float) -> void:
	var east: bool = current_flight().landing.x < x
	var actions := [shooter.action_right, setter.action_right] if east else [shooter.action_left, setter.action_left]
	await hold_until(actions, func(): return (current_flight().landing.x >= x - 0.3) if east else (current_flight().landing.x <= x + 0.3), 4.0)


var _game_over_logged := false


## Logs where the carriers were when a game over starts: a fall, most likely, since they're kept invulnerable.
func watch_game_over() -> void:
	var over := state() == "gameoverlost"
	if over == _game_over_logged:
		return
	_game_over_logged = over
	if not over:
		return
	print("INFO GAME OVER: carriers at %s" % [players().map(func(p): return p.global_position)])


## (1) Four crossbowmen on the wall: one killed by a real bomb, the rest by script.
func wall_section() -> void:
	var guards := alive("WallGuards")
	check("four crossbowmen on the wall", guards.size() == 4, str(guards.size()))
	check("the crossbowmen stand on the wall walk", guards.all(func(e): return absf(e.global_position.y - WALL_TOP) < 0.6), "ys=%s" % str(guards.map(func(e): return snappedf(e.global_position.y, 0.01))))
	check("the wall is east of the ledge", guards.all(func(e): return e.global_position.x > LEDGE_EAST + 3.0))
	check("the guards wait at the start", guards.all(func(e): return not e.is_offensive))
	check("nobody can reach the guards on foot", not path_reaches(shooter.global_position, guards[2].global_position))
	var ok: bool = await hold_until([shooter.action_up, setter.action_up], func(): return guards[0].is_offensive, 6.0)
	check("real input: walking north wakes the crossbowmen", ok and state() == "playing", "shooter z=%.1f" % shooter.global_position.z)
	check("the catapult skeleton doesn't wake with them", not alive("CatapultCrew")[0].is_offensive)
	await wait(1.0)
	check("the ledge and the wall are framed", focal_count() == 4, str(focal_count()))
	var target: EnemyLocal = guards.filter(func(e): return absf(e.global_position.z - w(0, 0).z) < 1.0)[0]
	# Turns south of the sinkhole: turning beside it, the back carrier stepped west into it.
	await hold_until([shooter.action_up, setter.action_up], func(): return shooter.global_position.z < w(0, 3).z, 6.0)
	ok = await turn_to("action_right", "action_left", Vector3.RIGHT)
	check("real input: the pair turns to face the wall", ok and state() == "playing", "forward %s" % flat_forward())
	check("still in the same run (nobody fell)", cp() == "Checkpoint", cp())
	await hold_until([shooter.action_right, setter.action_right], func(): return setter.global_position.x > LEDGE_EAST - 1.2, 4.0)
	await line_up_z(target.global_position.z)
	await wait(0.8)
	check("both carriers on screen at the edge", count_on_screen(players()) == 2, "%d/2" % count_on_screen(players()))
	var in_range := guards.filter(func(e): return Vector2(e.global_position.x - shooter.global_position.x, e.global_position.z - shooter.global_position.z).length() <= 18.0)
	check("most crossbowmen can reach the carriers here", in_range.size() >= 3, "%d in range" % in_range.size())
	check("every crossbowman is on screen", count_on_screen(guards) == guards.size(), "%d/%d" % [count_on_screen(guards), guards.size()])
	await shot("02_wall_framed.png")
	var storm := world.get_node("Level/Sandstorm") as Sandstorm
	var environment := (world.get_node("WorldEnvironment") as WorldEnvironment).environment
	var calm_fog := CALM_FOG  # a gust may already be blowing
	storm.start_gust()
	await wait(2.2)
	check("a gust builds up", storm.gust_strength() > 0.9 and environment.fog_density > calm_fog * 2.0, "strength %.2f fog %.4f -> %.4f" % [storm.gust_strength(), calm_fog, environment.fog_density])
	await shot("02b_gust.png")
	ok = await wait_until(func(): return fireball_dives[0] > 0, 8.0)
	check("crossbowmen fire down at the carriers", ok, "dives=%d" % fireball_dives[0])
	await wait(3.0)
	check("a bolt reaches a carrier's body", fireball_closest[0] < 0.9, "closest %.2f m" % fireball_closest[0])
	var error := await aim_range_at(target.global_position)
	var landing: Vector3 = current_flight().landing
	check("the ring can be put on the wall walk by a crossbowman", absf(error) < 1.0 and landing.y > WALL_TOP - 0.3 and landing.distance_to(target.global_position) < 2.0, "%.2f m off, landing y %.2f" % [landing.distance_to(target.global_position), landing.y])
	await wait_until(func(): return specifics.is_loaded(), 3.0)
	await press_shoot()
	ok = await wait_until(func(): return not target.is_alive(), 4.0)
	check("real input: a catapult bomb kills a crossbowman", ok)
	await shot("03_wall_hit.png")
	kill(alive("WallGuards"))
	ok = await wait_until(func(): return bridge_y(2) > -1.5, 8.0)
	check("clearing the wall sets Checkpoint2", cp() == "Checkpoint2", cp())
	check("clearing the wall raises bridge 1", ok, "y=%.2f" % bridge_y(2))
	check("clearing the wall drops its framing", focal_count() == 0, str(focal_count()))
	await wait(2.0)
	protect_players()


## Over bridge 1 onto the second ledge, which wakes the catapult skeleton and lowers the bridge behind.
func cross_to_second_ledge() -> void:
	await face_north_on_column(w(0, 0).x)
	var crew: EnemyLocal = alive("CatapultCrew")[0]
	var ok: bool = await hold_until([shooter.action_up, setter.action_up], func(): return crew.is_offensive or shooter.global_position.z < w(0, -12).z, 10.0)
	ok = ok and crew.is_offensive
	check("real input: stepping onto the second ledge wakes the catapult skeleton", ok and state() == "playing", "shooter z=%.1f state=%s" % [shooter.global_position.z, state()])
	await wait(2.5)
	check("bridge 1 lowers behind the carriers", bridge_y(2) < -5.0, "y=%.2f" % bridge_y(2))
	check("the pocket and the ledge are framed", focal_count() == 4, str(focal_count()))


## (2) The hidden catapult skeleton, on his own: he throws over the hill, and a real bomb thrown back over it kills him.
func catapult_section() -> void:
	var crew: EnemyLocal = alive("CatapultCrew")[0]
	var siege := crew.get_node("SiegeCatapult") as SiegeCatapult
	check("he stands in the pocket behind the hill", crew.global_position.x < POCKET_EAST and crew.global_position.x > POCKET_WEST, "x=%.1f" % crew.global_position.x)
	check("nobody can walk to him", not path_reaches(shooter.global_position, crew.global_position))
	var throws := []
	siege.fired.connect(func(bomb: CatapultBomb):
		var ring := siege.get_node("WarningRing") as Node3D
		throws.append({"hostile": bomb.is_hostile(), "ring": ring.global_position, "ring_visible": ring.visible})
		bomb.exploded.connect(func(at: Vector3):
			throws[-1]["at"] = at
			throws[-1]["nearest"] = players().map(func(p): return Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length()).min()))
	# Up to his row, then turn west to face the hill.
	await hold_until([shooter.action_up, setter.action_up], func(): return (shooter.global_position.z + setter.global_position.z) * 0.5 < crew.global_position.z, 5.0)
	var ok: bool = await wait_until(func(): return throws.size() > 0 and throws[0].has("at"), 12.0)
	check("he throws a bomb at the carriers", ok)
	if ok:
		var at: Vector3 = throws[0].at
		print("INFO his bomb landed at %s, %.2f m from the nearer carrier" % [at, throws[0].nearest])
		check("his bomb is hostile and its ring showed where it lands", throws[0].hostile and throws[0].ring_visible and Vector2(throws[0].ring.x - at.x, throws[0].ring.z - at.z).length() < 0.5)
		check("it clears the hill and lands on the ledge", at.x > HILL_EAST_FACE and absf(at.y - FLOOR_TOP) < 0.3, str(at))
		check("it lands within its blast (3 m) of a carrier", throws[0].nearest < siege.blast_radius, "%.2f m" % throws[0].nearest)
	await shot("04_catapult_framed.png")
	ok = await turn_to("action_left", "action_right", Vector3.LEFT)
	check("real input: the pair turns west, toward the hill", ok and state() == "playing", "forward %s" % flat_forward())
	# Up to the hill: the front carrier can't stand on it, so the throw reaches furthest from its foot.
	await hold_until([shooter.action_left, setter.action_left], func(): return setter.global_position.x < HILL_EAST_FACE + 0.8, 5.0)
	for attempt in 3:
		if not crew.is_alive():
			break
		await line_up_z(crew.global_position.z)
		var error := await aim_range_at(crew.global_position)
		var landing: Vector3 = current_flight().landing
		print("INFO aimed over the hill: error %.2f m, gap %.2f, landing %s, skeleton %s" % [error, gap(), landing, crew.global_position])
		if attempt == 0:
			check("the ring can be put over the hill, in the pocket", landing.x < HILL_WEST_FACE and absf(landing.y - FLOOR_TOP) < 0.3, str(landing))
			await shot("05_aimed_over_hill.png")
		await wait_until(func(): return specifics.is_loaded(), 3.0)
		await press_shoot()
		await wait_until(func(): return not crew.is_alive(), 3.5)
	check("real input: a catapult bomb over the hill kills the catapult skeleton", not crew.is_alive())
	kill(alive("CatapultCrew"))
	ok = await wait_until(func(): return bridge_y(5) > -1.5, 8.0)
	check("killing him sets Checkpoint3", cp() == "Checkpoint3", cp())
	check("killing him raises bridge 2", ok, "y=%.2f" % bridge_y(5))
	check("killing him drops the framing", focal_count() == 0, str(focal_count()))
	await wait(2.0)
	protect_players()


## (3) The islands: chasers over the bridges, catapult skeletons, and crossbowmen on two towers.
func islands_section() -> void:
	await face_north_on_column(w(-1, 0).x)
	var ok: bool = await hold_until([shooter.action_up, setter.action_up], func(): return not alive("IslandChasers").is_empty(), 12.0)
	check("real input: stepping onto the first island starts the fight", ok and state() == "playing", "shooter z=%.1f state=%s" % [shooter.global_position.z, state()])
	await wait(2.5)
	check("bridge 2 lowers behind the carriers", bridge_y(5) < -5.0, "y=%.2f" % bridge_y(5))
	await check_island_enemies()
	await shot("06_islands_start.png")

	# A death mid-fight goes back to Checkpoint3: the islands empty again, bridge 2 up, the first island re-armed.
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 10.0)
	await wait(1.5)
	protect_players()
	bind_carriers()
	check("respawn mid-islands: back at Checkpoint3 on the second ledge", cp() == "Checkpoint3" and absf(shooter.global_position.z - w(0, -15).z) < 4.0, "%s z=%.1f" % [cp(), shooter.global_position.z])
	check("respawn mid-islands: the islands are empty, bridge 2 up", ISLAND_GROUPS.all(func(g): return alive(g).is_empty()) and bridge_y(5) > -1.5, "y=%.2f" % bridge_y(5))
	check("respawn mid-islands: the wall and the catapult stay cleared", alive("WallGuards").is_empty() and alive("CatapultCrew").is_empty())
	await face_north_on_column(w(-1, 0).x)
	ok = await hold_until([shooter.action_up, setter.action_up], func(): return not alive("IslandChasers").is_empty(), 12.0)
	check("the islands start again after the respawn", ok)
	await wait(2.0)

	# Chasers come over the bridges; catapults throw.
	var island_throws := [0]
	for crew in alive("IslandCatapults"):
		(crew.get_node("SiegeCatapult") as SiegeCatapult).fired.connect(func(_b): island_throws[0] += 1)
	var first_island := Rect2(w(-3, -23).x - 1.5, w(-3, -23).z - 1.5, 15.0, 15.0)
	ok = await wait_until(func(): return alive("IslandChasers").any(func(e): return first_island.has_point(Vector2(e.global_position.x, e.global_position.z))), 20.0)
	check("a chaser crosses the bridges to the carriers' island", ok)
	check("nobody fell off a bridge", alive("IslandChasers").size() == 6 and alive("IslandChasers").all(func(e): return e.global_position.y > FLOOR_TOP - 0.5), str(alive("IslandChasers").map(func(e): return snappedf(e.global_position.y, 0.1))))
	await wait_until(func(): return island_throws[0] > 0, 10.0)
	check("the island catapults throw at the carriers", island_throws[0] > 0, str(island_throws[0]))
	await shot("07_islands_fight.png")
	await overview("07b_islands_overview.png", Vector3(-6, 40, -40), Vector3(-8, -4, -86))

	# The rest by script: the way to the end pad opens.
	ok = await wait_until(func():
		for g in ISLAND_GROUPS:
			kill(alive(g))
		return cp() == "Checkpoint4", 10.0)
	check("clearing the islands sets Checkpoint4", ok, cp())
	ok = await wait_until(func(): return bridge_y(8) > -1.5, 8.0)
	check("clearing the islands raises bridge 3", ok, "y=%.2f" % bridge_y(8))
	await wait(2.0)
	protect_players()


func check_island_enemies() -> void:
	var chasers := alive("IslandChasers")
	var crews := alive("IslandCatapults")
	var guards := alive("TowerGuards")
	check("six chasers, five catapult skeletons and two tower crossbowmen appear", chasers.size() == 6 and crews.size() == 5 and guards.size() == 2, "%d/%d/%d" % [chasers.size(), crews.size(), guards.size()])
	check("they all come in offensive", (chasers + crews + guards).all(func(e): return e.is_offensive))
	check("the tower crossbowmen stand on their towers", guards.all(func(e): return absf(e.global_position.y - WALL_TOP) < 0.6), str(guards.map(func(e): return snappedf(e.global_position.y, 0.01))))
	check("nobody can walk to the towers", guards.all(func(e): return not path_reaches(shooter.global_position, e.global_position)))
	check("the chasers can walk to the carriers over the bridges", chasers.all(func(e): return path_reaches(e.global_position, shooter.global_position)))
	check("the catapult skeletons stand on islands", crews.all(func(e): return absf(e.global_position.y - FLOOR_TOP) < 0.3))


## Turns the pair to face north, then side-steps it onto the column at `x`, ready to walk over a bridge.
func face_north_on_column(x: float) -> void:
	if flat_forward().dot(Vector3.FORWARD) < 0.9:
		var front := "action_up"
		var back := "action_down"
		await turn_to(front, back, Vector3.FORWARD)
	var mid := func(): return (shooter.global_position.x + setter.global_position.x) * 0.5
	var east: bool = mid.call() < x
	var actions := [shooter.action_right, setter.action_right] if east else [shooter.action_left, setter.action_left]
	await hold_until(actions, func(): return (mid.call() >= x - 0.3) if east else (mid.call() <= x + 0.3), 4.0)
	await wait(0.3)


## (4) The S-bridge: catapults on islands, a real shot from an outcrop, the S walked with real input.
func s_bridge_section() -> void:
	await face_north_on_column(w(-1, 0).x)
	var ok: bool = await hold_until([shooter.action_up, setter.action_up], func(): return alive("BridgeCatapults").any(func(e): return e.is_offensive), 22.0)
	check("real input: stepping onto the pad past bridge 3 wakes the bridge catapults", ok and state() == "playing", "shooter z=%.1f state=%s" % [shooter.global_position.z, state()])
	await wait(2.5)
	check("bridge 3 lowers behind the carriers", bridge_y(8) < -5.0, "y=%.2f" % bridge_y(8))
	var crews := alive("BridgeCatapults")
	check("four catapult skeletons, one on each island", crews.size() == 4 and crews.all(func(e): return absf(e.global_position.y - FLOOR_TOP) < 0.3), str(crews.size()))
	check("nobody can walk to them", crews.all(func(e): return not path_reaches(shooter.global_position, e.global_position)))
	var throws := []
	for crew in crews:
		(crew.get_node("SiegeCatapult") as SiegeCatapult).fired.connect(func(bomb: CatapultBomb):
			throws.append({})
			var record: Dictionary = throws[-1]
			bomb.exploded.connect(func(at: Vector3): record["nearest"] = players().map(func(p): return Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length()).min()))
	await overview("10_s_bridge_overview.png", Vector3(0, 44, -110), Vector3(-2, -4, -160))

	# Onto the S, the back carrier stopping on the pad's edge so the front carrier stands on the first outcrop's junction.
	var junction := w(OUTCROP_JUNCTION.x, OUTCROP_JUNCTION.y)
	await hold_until([shooter.action_up, setter.action_up], func(): return setter.global_position.z < junction.z + 0.3, 6.0)
	ok = await wait_until(func(): return throws.any(func(r): return r.has("nearest")), 10.0)
	check("the bridge catapults throw at the carriers", ok, "%d thrown" % throws.size())
	if ok:
		var nearest: float = throws.filter(func(r): return r.has("nearest")).map(func(r): return r.nearest).min()
		check("a bridge catapult's bomb lands within its blast of a carrier", nearest < 3.0, "%.2f m" % nearest)
	await shot("11_s_bridge_start.png")

	# The front carrier steps out along the outcrop while the back carrier comes up to the junction: the pair turns west.
	await hold_until([setter.action_left, shooter.action_up], func(): return shooter.global_position.z < junction.z + 0.3, 4.0)
	await hold_until([setter.action_left], func(): return gap() > 6.0 or setter.global_position.x < OUTCROP_TIP_X + 0.6, 3.0)
	# Square up: the back carrier, on the bridge, steps level with the front carrier, so the throw runs down the outcrop.
	var south: bool = shooter.global_position.z < setter.global_position.z
	await hold_until([shooter.action_down if south else shooter.action_up], func(): return (shooter.global_position.z >= setter.global_position.z - 0.15) if south else (shooter.global_position.z <= setter.global_position.z + 0.15), 2.0)
	await wait(0.4)
	print("INFO on the outcrop: shooter %s setter %s gap %.2f forward %s" % [shooter.global_position, setter.global_position, gap(), flat_forward()])
	check("the pair stands in line along the outcrop", state() == "playing" and flat_forward().dot(Vector3.LEFT) > 0.95 and shooter.global_position.y > FLOOR_TOP - 0.3 and setter.global_position.y > FLOOR_TOP - 0.3, "forward %s" % flat_forward())
	var target: EnemyLocal = crews.reduce(func(best, e): return e if e.global_position.distance_to(setter.global_position) < best.global_position.distance_to(setter.global_position) else best)
	for attempt in 3:
		if not target.is_alive():
			break
		var error := await aim_front_range_at(target.global_position)
		var landing: Vector3 = current_flight().landing
		print("INFO aimed from the outcrop: error %.2f m, gap %.2f, landing %s, skeleton %s" % [error, gap(), landing, target.global_position])
		if attempt == 0:
			# He stands on his island's far side, 3 to 4 m behind his stake: the ring falls short of him, the blast doesn't.
			var reach := Vector2(landing.x - target.global_position.x, landing.z - target.global_position.z).length()
			check("from the outcrop the ring lands on his island, within the blast of him", absf(landing.y - FLOOR_TOP) < 0.3 and reach < 3.5, "%.2f m from him, landing %s, gap %.2f" % [reach, landing, gap()])
			check("aiming keeps the front carrier on the outcrop", setter.global_position.x > OUTCROP_TIP_X and state() == "playing", "x=%.2f" % setter.global_position.x)
			await shot("12_aimed_from_outcrop.png")
		await wait_until(func(): return specifics.is_loaded(), 3.0)
		await press_shoot()
		await wait_until(func(): return not target.is_alive(), 3.5)
	check("real input: a bomb from the outcrop kills that island's catapult skeleton", not target.is_alive())

	# Off the outcrop: the back carrier steps back down the bridge while the front carrier walks in to the junction. The
	# catapult keeps its carriers at least 4 m apart: with the back carrier waiting at the junction, the front one was
	# pushed sideways off the outcrop.
	await hold_until([setter.action_right, shooter.action_down], func(): return setter.global_position.x > junction.x - 0.4, 5.0)
	print("INFO off the outcrop: shooter %s setter %s state %s" % [shooter.global_position, setter.global_position, state()])
	# Back onto the S and along all of it, real input, under fire.
	var line := s_line()
	var end_s := line_length(line) - 1.0
	var walked := await walk_line(line, end_s, 60.0)
	check("real input: the pair walks the whole S without falling", walked and state() == "playing" and cp() == "Checkpoint4", "reached %.1f of %.1f m, state %s" % [line_progress(line, setter.global_position), end_s, state()])
	await shot("13_s_bridge_end.png")

	# The rest by script: bridge 4 rises.
	kill(alive("BridgeCatapults"))
	ok = await wait_until(func(): return bridge_y(13) > -1.5, 8.0)
	check("killing them sets Checkpoint5", cp() == "Checkpoint5", cp())
	check("killing them raises bridge 4", ok, "y=%.2f" % bridge_y(13))
	await wait(2.0)
	gsm.transition_to("resettingcheckpoint")
	await wait_until(func(): return state() == "playing", 10.0)
	await wait(1.5)
	protect_players()
	bind_carriers()
	check("respawn at Checkpoint5: on the S's last run, catapults dead, bridge 4 up", cp() == "Checkpoint5" and alive("BridgeCatapults").is_empty() and bridge_y(13) > -1.5 and absf(shooter.global_position.z - w(0, -61).z) < 4.0 and shooter.global_position.y > FLOOR_TOP - 0.3, "z=%.1f y=%.2f" % [shooter.global_position.z, shooter.global_position.y])


## Steps the front carrier along the throw until the ring's centre is level with `target`: the back carrier stands on
## a one-cell bridge, where stepping back would drop them.
func aim_front_range_at(target: Vector3) -> float:
	var out := setter.action_left if flat_forward().x < 0.0 else setter.action_right
	var back := setter.action_right if flat_forward().x < 0.0 else setter.action_left
	for step in 50:
		var error: float = (target - current_flight().landing).dot(flat_forward())
		if absf(error) < 0.5:
			return error
		# The outcrop's tip: one more step out and the front carrier drops.
		if error > 0.0 and setter.global_position.x < OUTCROP_TIP_X + 0.5:
			return error
		await hold([out if error > 0.0 else back], 0.05)
		await wait(0.05)
	return (target - current_flight().landing).dot(flat_forward())


func s_line() -> PackedVector3Array:
	var line := PackedVector3Array()
	for cell in S_BRIDGE:
		line.append(w(cell.x, cell.y))
	return line


func line_length(line: PackedVector3Array) -> float:
	var total := 0.0
	for i in line.size() - 1:
		total += Vector2(line[i + 1].x - line[i].x, line[i + 1].z - line[i].z).length()
	return total


## [distance along the line, flat distance off it] of the point on `line` nearest `p`.
func line_nearest(line: PackedVector3Array, p: Vector3) -> Array:
	var best := [0.0, INF]
	var along := 0.0
	for i in line.size() - 1:
		var a := Vector2(line[i].x, line[i].z)
		var b := Vector2(line[i + 1].x, line[i + 1].z)
		var seg := b - a
		var t := clampf((Vector2(p.x, p.z) - a).dot(seg) / seg.length_squared(), 0.0, 1.0)
		var off := (a + seg * t).distance_to(Vector2(p.x, p.z))
		if off < best[1]:
			best = [along + seg.length() * t, off]
		along += seg.length()
	return best


func line_progress(line: PackedVector3Array, p: Vector3) -> float:
	return line_nearest(line, p)[0]


func point_along(line: PackedVector3Array, distance: float) -> Vector2:
	var left := distance
	for i in line.size() - 1:
		var a := Vector2(line[i].x, line[i].z)
		var b := Vector2(line[i + 1].x, line[i + 1].z)
		if left <= a.distance_to(b):
			return a + (b - a).normalized() * left
		left -= a.distance_to(b)
	return Vector2(line[-1].x, line[-1].z)


## Steers each carrier along `line` with real input until the front carrier is `end_s` along it: each aims 1.6 m
## ahead on the line (or straight back to it when more than 0.8 m off), pressing the nearest of the eight directions,
## and the back carrier waits while it's within 4.6 m of the front one along the line.
func walk_line(line: PackedVector3Array, end_s: float, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if state() != "playing":
			break
		var front := line_nearest(line, setter.global_position)
		if front[0] >= end_s:
			break
		var back := line_nearest(line, shooter.global_position)
		_steer(setter, _line_target(line, front, setter.global_position))
		var back_waits: bool = front[0] - back[0] < 4.6 and back[1] < 0.8
		_steer(shooter, Vector2.ZERO if back_waits else _line_target(line, back, shooter.global_position))
		await get_tree().physics_frame
	for p in players():
		_steer(p, Vector2.ZERO)
	await get_tree().physics_frame
	return state() == "playing" and line_progress(line, setter.global_position) >= end_s


func _line_target(line: PackedVector3Array, nearest: Array, p: Vector3) -> Vector2:
	var here := Vector2(p.x, p.z)
	if nearest[1] > 0.8:
		return point_along(line, nearest[0]) - here
	return point_along(line, nearest[0] + 1.6) - here


func _steer(p: PlayerLocal, dir: Vector2) -> void:
	for a in [p.action_up, p.action_down, p.action_left, p.action_right]:
		Input.action_release(a)
	if dir.length() < 0.05:
		return
	var d := dir.normalized()
	if d.x > 0.38:
		Input.action_press(p.action_right)
	if d.x < -0.38:
		Input.action_press(p.action_left)
	if d.y > 0.38:
		Input.action_press(p.action_down)
	if d.y < -0.38:
		Input.action_press(p.action_up)


## Side-steps the pair (facing east or west) until the ring is level with `z`.
func line_up_z(z: float) -> void:
	var north: bool = current_flight().landing.z > z
	var actions := [shooter.action_up, setter.action_up] if north else [shooter.action_down, setter.action_down]
	await hold_until(actions, func(): return (current_flight().landing.z <= z + 0.3) if north else (current_flight().landing.z >= z - 0.3), 3.0)


func path_reaches(from: Vector3, to: Vector3) -> bool:
	var map := world.get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return path.size() > 0 and Vector2(path[-1].x - to.x, path[-1].z - to.z).length() < 1.0


## A high, wide view, to judge the layout.
func overview(file_name: String, from: Vector3, look: Vector3) -> void:
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.global_position = from
	cam.look_at(look)
	cam.make_current()
	await wait(0.05)
	await shot(file_name)
	cam.queue_free()
	world.get_node("CameraFollowRig/ShakePivot/Camera3D").make_current()
