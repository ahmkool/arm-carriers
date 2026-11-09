extends Node
## Test driver for world_spike_trap_prototype.tscn: plates, wall speeds, enemies keeping clear of the walls,
## walls killing, respawn reset, and the walls pulling back when the wave is cleared.
## Run through godot.sh, see docs/level-creation-for-agents.md. Save tracking is disabled.

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var trap: SpikeTrap
var horde: SurvivalEnemyGroup
var fails := 0
## Closest any living enemy came to a wall's spike tips while being watched, in metres (negative = inside).
var closest_clearance := [INF]
## Skeletons that died while rockets were flying and the walls stood still.
var rocket_kills := [0]
var counting_kills := [false]

func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	trap = world.get_node("Level/SpikeTrap") as SpikeTrap
	horde = world.get_node("Enemies/SurvivalEnemyGroup") as SurvivalEnemyGroup
	get_tree().create_timer(280.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
	horde.get_node("Enemies").child_entered_tree.connect(_on_enemy_spawned)
	_run.call_deferred()

func _on_enemy_spawned(node: Node) -> void:
	if node is not EnemyLocal:
		return
	Health.from_target(node).died.connect(func(_source): if counting_kills[0]: rocket_kills[0] += 1)

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

func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)

func expose_players() -> void:
	for p in players():
		p.get_node("Health")._invulnerable_time_remaining = 0.0

func horde_enemies() -> Array:
	return horde.get_node("Enemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())

func on_screen(points: Array) -> int:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	var seen := 0
	for pos in points:
		if not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos)):
			seen += 1
	return seen

func player_points() -> Array:
	return players().map(func(p): return p.global_position + Vector3(0, 1, 0))

## The spike tips straight north and south of the pair.
func wall_tip_points() -> Array:
	var x: float = (players()[0].global_position.x + players()[1].global_position.x) * 0.5
	var c := trap.global_position
	return [Vector3(x, c.y + 0.5, c.z - trap.half_gap), Vector3(x, c.y + 0.5, c.z + trap.half_gap)]

func check_view(label: String) -> void:
	var p := on_screen(player_points())
	var walls := on_screen(wall_tip_points())
	check(label, p == 2 and walls == 2, "players %d/2, wall tips %d/2, half gap %.1f, camera y=%.1f" % [p, walls, trap.half_gap, get_viewport().get_camera_3d().global_position.y])

## Distance from a point to the nearest wall's spike tips, along z.
func clearance(pos: Vector3) -> float:
	return trap.half_gap - absf(pos.z - trap.global_position.z)

func watch_enemies() -> void:
	for e in horde_enemies():
		closest_clearance[0] = minf(closest_clearance[0], clearance(e.global_position))

func pressed() -> int:
	return trap.pressed_plate_count()

## Holds both players' right until both plates are held (real input), so they stop on them.
func walk_onto_plates() -> bool:
	var list := players()
	for p in list:
		Input.action_press(p.action_right)
	var ok: bool = await wait_until(func(): return pressed() == 2, 4.0)
	for p in list:
		Input.action_release(p.action_right)
	await wait(0.4)
	return ok and pressed() == 2

func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame

## How far each wall moves in `seconds`.
func measure_close(seconds: float) -> float:
	var before := trap.half_gap
	await wait(seconds)
	return before - trap.half_gap

func respawn() -> void:
	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(1.0)
	protect_players()

func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.5)
	check("trap waits, walls open", trap.state == SpikeTrap.State.WAITING and is_equal_approx(trap.half_gap, trap.start_half_gap), "state=%d gap=%.2f" % [trap.state, trap.half_gap])
	check("scene's wave lasts 45 s", is_equal_approx(horde.fight_duration, 45.0), "%.1f" % horde.fight_duration)
	check("no plate held at spawn", pressed() == 0, "%d" % pressed())
	check_view("spawn view: carriers and both walls on screen")
	await shot("01_spawn.png")

	# ---- Real input: walk east onto the plates. The wake trigger starts the trap and the wave. ----
	ok = await walk_onto_plates()
	check("real input: both carriers stop on the plates", ok, "pressed=%d, gap between carriers %.2f m" % [pressed(), _carrier_gap()])
	check("walking in starts the trap", trap.state == SpikeTrap.State.CLOSING, "state=%d" % trap.state)
	check("both plates held: walls stopped", is_zero_approx(trap.current_speed()) and await measure_close(2.0) < 0.01, "gap=%.2f" % trap.half_gap)
	await shot("02_on_plates.png")

	# Real fire from the plates at the skeletons coming from the east.
	get_tree().physics_frame.connect(watch_enemies)
	counting_kills[0] = true
	await _fire_from_plates(12.0)
	counting_kills[0] = false
	check("real fire from the plates kills skeletons", rocket_kills[0] > 0, "%d killed" % rocket_kills[0])
	# Each shot's recoil shoves the pair about 0.1 m west, so a long volley can push the shooter off its plate.
	print("INFO plates held after the volley: %d (recoil drift)" % pressed())
	await shot("03_firing.png")
	ok = await walk_onto_plates()
	check("real input: step back east onto both plates", ok, "%d" % pressed())

	# Shooter (west) steps off its plate: one plate held.
	await hold([players()[0].action_left], 0.3)
	await wait(0.3)
	check("real input: shooter steps off, one plate held", pressed() == 1, "%d" % pressed())
	await shot("03b_one_plate.png")
	var slow := await measure_close(2.0)
	check("one plate: walls slowed (about %.2f m in 2 s)" % (trap.slowed_speed * 2.0), absf(slow - trap.slowed_speed * 2.0) < 0.06, "%.2f m" % slow)
	# Both off.
	await hold([players()[0].action_left, players()[1].action_left], 1.2)
	await wait(0.3)
	check("real input: both step off", pressed() == 0, "%d" % pressed())
	var fast := await measure_close(2.0)
	check("no plate: walls close at full speed (about %.2f m in 2 s)" % (trap.close_speed * 2.0), absf(fast - trap.close_speed * 2.0) < 0.08, "%.2f m" % fast)
	check_view("closing view: carriers and both walls on screen")
	await shot("04_closing.png")

	# ---- Enemies near a wall: carriers stand right against the north wall, skeletons must stop short. ----
	trap.state = SpikeTrap.State.WAITING  # freeze the walls for this part
	trap._set_half_gap(4.5)
	var near_wall := trap.global_position + Vector3(4.0, 0.2, -3.9)
	players()[0].global_position = near_wall + Vector3(-1.5, 0, 0)
	players()[1].global_position = near_wall + Vector3(1.5, 0, 0)
	closest_clearance[0] = INF
	await wait(7.0)
	var near := horde_enemies().filter(func(e): return Vector2(e.global_position.x - near_wall.x, e.global_position.z - near_wall.z).length() < 4.0)
	check("skeletons chasing carriers by the wall stay out of the spikes", closest_clearance[0] > 0.2, "closest %.2f m from the tips" % closest_clearance[0])
	check("...and still get close to the carriers", near.size() > 0, "%d within 4 m" % near.size())
	await shot("05_enemies_by_wall.png")

	# ---- Walls closing on skeletons: they back away. ----
	trap._set_half_gap(6.0)
	trap.state = SpikeTrap.State.CLOSING
	var mid := trap.global_position + Vector3(0.0, 0.2, 0.0)
	players()[0].global_position = mid + Vector3(-1.5, 0, 0)
	players()[1].global_position = mid + Vector3(1.5, 0, 0)
	closest_clearance[0] = INF
	var dead_before := _dead_count()
	await wait(6.0)
	check("skeletons back away from closing walls", closest_clearance[0] > 0.0, "closest %.2f m from the tips, %d died meanwhile" % [closest_clearance[0], _dead_count() - dead_before])
	get_tree().physics_frame.disconnect(watch_enemies)

	# ---- The spikes kill: an enemy pushed into them dies, and so does a carrier. ----
	var victim: EnemyLocal = horde_enemies()[0] if horde_enemies().size() > 0 else null
	if victim != null:
		victim.global_position = trap.north_wall.global_position + trap.north_wall.get_forward() * 0.3 + Vector3.UP * 0.2
		await wait(0.3)
	check("spikes kill a skeleton", victim != null and not victim.is_alive())
	expose_players()
	# Both together: the carry joint pulls a lone carrier back toward the other one.
	var spikes := trap.south_wall.global_position + trap.south_wall.get_forward() * 0.3 + Vector3.UP * 0.2
	players()[0].global_position = spikes + Vector3(-1.5, 0, 0)
	players()[1].global_position = spikes + Vector3(1.5, 0, 0)
	ok = await wait_until(func(): return state() == "gameoverlost", 3.0)
	check("spikes kill a carrier: game over", ok, state())
	ok = await wait_until(func(): return state() == "playing", 15.0)
	await wait(1.0)
	protect_players()
	check("respawn: walls back open and waiting", trap.state == SpikeTrap.State.WAITING and is_equal_approx(trap.half_gap, trap.start_half_gap), "state=%d gap=%.2f" % [trap.state, trap.half_gap])
	check("respawn: wave cleared", horde_enemies().is_empty(), "%d alive" % horde_enemies().size())

	# ---- Clear the wave: the walls pull back. ----
	ok = await walk_onto_plates()
	check("real input: back on the plates after respawn", ok and trap.state == SpikeTrap.State.CLOSING, "pressed=%d state=%d" % [pressed(), trap.state])
	horde.fight_duration = 3.0  # driver only; the scene's 45 s was checked above
	await hold([players()[0].action_left, players()[1].action_left], 0.4)  # let the walls move a bit first
	await wait(2.0)
	var closed_to := trap.half_gap
	ok = await _kill_wave_until_done(15.0)
	check("wave cleared", ok)
	await wait(0.2)
	check("clearing the wave retracts the walls", trap.state == SpikeTrap.State.RETRACTING or trap.state == SpikeTrap.State.OPEN, "state=%d, gap %.2f (was %.2f)" % [trap.state, trap.half_gap, closed_to])
	ok = await wait_until(func(): return trap.state == SpikeTrap.State.OPEN, 6.0)
	check("walls end fully open", ok and is_equal_approx(trap.half_gap, trap.start_half_gap), "gap=%.2f" % trap.half_gap)
	check("walls stay open with nobody on the plates", await measure_close(1.5) < 0.001)
	await shot("06_cleared.png")

	print("DONE fails=%d" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func _carrier_gap() -> float:
	var l := players()
	return Vector2(l[0].global_position.x - l[1].global_position.x, l[0].global_position.z - l[1].global_position.z).length()

func _dead_count() -> int:
	return horde.get_node("Enemies").get_children().filter(func(c): return c is EnemyLocal and not c.is_alive()).size()

## Fires every 0.8 s for `seconds`, with real input.
func _fire_from_plates(seconds: float) -> void:
	var shooter: PlayerLocal = players()[0]
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		Input.action_press(shooter.action_shoot)
		await get_tree().physics_frame
		await get_tree().physics_frame
		Input.action_release(shooter.action_shoot)
		await wait(0.8)

func _kill_wave_until_done(timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline and not horde.signal_emitted:
		for e in horde_enemies():
			Health.apply_damage(e, 9999, e.global_position)
		await wait(0.2)
	return horde.signal_emitted
