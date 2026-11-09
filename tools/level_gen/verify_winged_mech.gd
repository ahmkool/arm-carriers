extends Node
## Test driver for the winged mech in world_playground.tscn: hover, orbit, gun burst, dash, death fall, respawn.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_winged_mech.gd res://src/world/levels/world_playground.tscn <out_dir> 200
## Players are invulnerable, so dash hits are counted from the hit box's body_entered instead of from damage.

const GROUP := "Enemies/Prototype"
var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0

var states_seen := {}
var bolts_spawned := 0
var dash_hits := 0
var peak_speed := 0.0
var hover_heights: Array[float] = []
var orbit_angle := 0.0
var _last_angle := INF
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


func centre() -> Vector3:
	var sum := Vector3.ZERO
	for p in players():
		sum += p.global_position
	return sum / players().size()


## The winged mechs only: the playground may hold other prototypes too, such as the ground mech.
func mechs() -> Array:
	return world.get_node(GROUP).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive() and c.behavior is WingedMechBehavior)


## Everything else in the group, removed once awake so the winged mech is watched on its own.
func others() -> Array:
	return world.get_node(GROUP).get_node("InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive() and not c.behavior is WingedMechBehavior)


func mech() -> EnemyLocal:
	var list := mechs()
	return null if list.is_empty() else list[0]


func mech_state(m: EnemyLocal) -> String:
	return String(m.enemy_state_machine.current_state.name).to_lower()


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)


func _mech_on_screen() -> bool:
	var m := mech()
	if m == null:
		return false
	var cam := get_viewport().get_camera_3d()
	var pos := m.global_position + Vector3.UP * 1.2
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return not cam.is_position_behind(pos) and rect.has_point(cam.unproject_position(pos))


func _on_node_added(node: Node) -> void:
	if node is FireballSpawn:
		bolts_spawned += 1


func _on_dash_hit(body: Node) -> void:
	if body is PlayerLocal:
		dash_hits += 1


## Samples the mech every physics frame while the fight runs.
func _sample() -> void:
	var m := mech()
	if m == null:
		return
	var s := mech_state(m)
	states_seen[s] = true
	peak_speed = maxf(peak_speed, m.velocity.length())
	if s == "hovering":
		hover_heights.append(m.global_position.y - centre().y)
	var flat := m.global_position - centre()
	var angle := atan2(flat.z, flat.x)
	if _last_angle != INF:
		orbit_angle += absf(wrapf(angle - _last_angle, -PI, PI))
	_last_angle = angle
	_screenshot_new_state(s)


func _screenshot_new_state(s: String) -> void:
	if _shot_states.has(s):
		return
	_shot_states[s] = true
	_state_shots.call_deferred(s)


func _state_shots(s: String) -> void:
	await shot("03_state_%s.png" % s)
	await closeup("03_closeup_%s.png" % s)


## A shot from a temporary camera beside the mech, to check the model, the gun grip and the lean.
func closeup(file_name: String) -> void:
	var m := mech()
	if m == null or _closeup_busy:
		return
	_closeup_busy = true
	var game_camera := get_viewport().get_camera_3d()
	var cam := Camera3D.new()
	world.add_child(cam)
	var side := m.global_basis.x * 3.5 - m.global_basis.z * 3.0 + Vector3.UP * 1.2
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
	check("one winged mech, waiting", m != null and not m.is_offensive)
	if m == null:
		get_tree().quit(1)
		return
	var lift := m.global_position.y - centre().y
	check("hovers above the floor while asleep", lift > 1.0 and lift < 2.4, "%.2f m above the carriers" % lift)
	check("starts in hovering", mech_state(m) == "hovering", mech_state(m))
	await shot("01_asleep.png")
	await closeup("01_closeup_asleep.png")

	var list := players()
	await hold([list[0].action_up, list[1].action_up], 2.2)
	await wait(0.5)
	check("wake trigger makes the mech offensive", m.is_offensive)
	for other in others():
		Health.apply_damage(other, 9999, other.global_position)
	protect_players()
	m.get_node("DashHitBox").body_entered.connect(_on_dash_hit)
	get_tree().physics_frame.connect(_sample)
	await wait(2.5)
	await shot("02_awake.png")
	var on_screen := 0
	for i in 6:
		await wait(2.0)
		await shot("02_fight_%d.png" % i)
		on_screen += 1 if _mech_on_screen() else 0
	check("mech mostly on screen while circling", on_screen >= 4, "%d/6 samples" % on_screen)
	(m.behavior as WingedMechBehavior).dash_chance = 1.0
	info("forcing dashes from now on")
	await wait(14.0)
	get_tree().physics_frame.disconnect(_sample)

	info("states seen: %s" % str(states_seen.keys()))
	check("used the gun", states_seen.has("shooting"))
	check("used the dash", states_seen.has("dashing"))
	check("gun bursts spawned bolts", bolts_spawned >= 3, "%d bolts" % bolts_spawned)
	check("dash reached high speed", peak_speed > 15.0, "peak %.1f m/s" % peak_speed)
	check("dash hit a carrier", dash_hits > 0, "%d hits" % dash_hits)
	var avg := 0.0
	for h in hover_heights:
		avg += h
	avg /= maxf(hover_heights.size(), 1)
	check("hovers about 1.6 m above the carriers", avg > 1.0 and avg < 2.6, "avg %.2f over %d samples" % [avg, hover_heights.size()])
	check("circles the carriers", orbit_angle > PI * 0.5, "%.0f degrees swept" % rad_to_deg(orbit_angle))
	var flat := m.global_position - centre()
	info("distance from carriers' middle at the end: %.1f m" % Vector2(flat.x, flat.z).length())

	var behavior := m.behavior as WingedMechBehavior
	behavior.dash_chance = 0.0
	await wait_until(func(): return mech_state(m) == "hovering", 5.0)
	var floor_probe := m.global_position
	Health.apply_damage(m, 9999, m.global_position + Vector3(0, 0, 2))
	await wait(1.5)
	check("dead mech drops to the floor", is_instance_valid(m) and m.global_position.y < centre().y + 0.5, "y %.2f -> %.2f" % [floor_probe.y, m.global_position.y if is_instance_valid(m) else -99.0])
	await shot("04_dead.png")

	world.restart_game()
	await wait_until(func(): return state() == "playing", 20.0)
	await wait(2.0)
	check("respawn brings the mech back, waiting", mech() != null and not mech().is_offensive)
	print("DONE fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
