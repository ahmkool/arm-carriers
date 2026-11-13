extends Node
## Test driver for the catapult's blades, in world_local_lava.tscn (idle practice tieflings near the spawn):
##   tools/level_gen/godot.sh test tools/level_gen/verify_catapult_blades.gd res://src/world/levels/world_local_lava.tscn <out_dir>
## The front carrier lines up with an enemy at blade's length and dashes with the real dash button; walking past and
## the back carrier's dash must not cut. Save tracking is disabled, so save.json stays untouched.

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var blades: CatapultBlades
var shooter: PlayerLocal
var setter: PlayerLocal


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(120.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func hold_until(actions: Array, cond: Callable, timeout: float) -> bool:
	for a in actions:
		Input.action_press(a)
	var ok: bool = await wait_until(cond, timeout)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame
	return ok


func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func targets() -> Array:
	return world.get_node("Enemies/EnemyGroup/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func blade_x(side: float) -> float:
	var hit := blades.get_node("HitArea" + ("Right" if side > 0.0 else "Left") + "/CollisionShape3D") as Node3D
	return hit.global_position.x


## Side-steps the pair until the given blade is level with `x`.
func line_up_blade(side: float, x: float) -> void:
	var east: bool = blade_x(side) < x
	var actions := [shooter.action_right, setter.action_right] if east else [shooter.action_left, setter.action_left]
	await hold_until(actions, func(): return (blade_x(side) >= x - 0.2) if east else (blade_x(side) <= x + 0.2), 5.0)
	await wait(0.3)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	for p in world.players.get_children():
		if p is PlayerLocal:
			p.get_node("Health").grant_invulnerability(9999.0)
	var catapult := world.get_node("Weapon/Catapult")
	blades = catapult.get_node("WeaponSpecifics/Blades") as CatapultBlades
	var carry: CarryInfo = (catapult.get_node("PickAndDropHandler") as PickAndDropHandler).get_carry_info()
	shooter = carry.main_carrier
	setter = carry.secondary_carrier
	check("the catapult has blades", blades != null)
	var grip := catapult.get_node("WeaponSpecifics/Model/FrontGrip") as Node3D
	check("the blades sit on the front grip, either side of the front carrier", blades.global_position.distance_to(grip.global_position) < 0.05 and absf(blade_x(1.0) - setter.global_position.x) > 0.8 and absf(blade_x(-1.0) - setter.global_position.x) > 0.8,
		"blades %s grip %s setter %s" % [blades.global_position, grip.global_position, setter.global_position])

	# The enemy straight east of the front carrier's column: the right blade lines up on it.
	var list := targets()
	list.sort_custom(func(a, b): return a.global_position.x < b.global_position.x)
	var target: EnemyLocal = list.filter(func(e): return e.global_position.x > setter.global_position.x + 2.0)[0]
	var before := targets().size()
	await line_up_blade(1.0, target.global_position.x)
	# Walk (no dash) up to just short of it: nothing is cut.
	await hold_until([shooter.action_up, setter.action_up], func(): return setter.global_position.z < target.global_position.z + 2.0, 5.0)
	await wait(0.3)
	check("walking doesn't cut", targets().size() == before, "%d -> %d" % [before, targets().size()])
	print("INFO lined up: right blade x %.2f, target %s, front carrier %s, gap %.2f" % [blade_x(1.0), target.global_position, setter.global_position, Vector2(setter.global_position.x - shooter.global_position.x, setter.global_position.z - shooter.global_position.z).length()])
	await shot("blades_lined_up.png")

	# The back carrier dashes: the blades don't cut for him.
	Input.action_press(shooter.action_up)
	await tap(shooter.action_dash)
	Input.action_release(shooter.action_up)
	await wait(0.4)
	check("the back carrier's dash doesn't cut", target.is_alive())

	# The front carrier dashes forward, past the enemy.
	var strikes := [0]
	var watch := func(): strikes[0] += int(blades.is_strike_active)
	get_tree().physics_frame.connect(watch)
	Input.action_press(setter.action_up)
	await tap(setter.action_dash)
	await wait(0.15)
	Input.action_release(setter.action_up)
	get_tree().physics_frame.disconnect(watch)
	await wait(0.3)
	check("the front carrier's dash makes the blades strike", strikes[0] > 0, "%d frames" % strikes[0])
	check("real input: a front-carrier dash cuts an enemy with a blade", not target.is_alive(), "front carrier now %s" % setter.global_position)
	await shot("blades_cut.png")

	# The front blade: an enemy straight ahead of the front carrier, cut by a dash forward.
	var blade_root := blades.global_position
	list = targets()
	list.sort_custom(func(a, b): return absf(a.global_position.x - blade_root.x) < absf(b.global_position.x - blade_root.x))
	var ahead: EnemyLocal = list[0]
	var ahead_east: bool = blades.global_position.x < ahead.global_position.x
	var side := [shooter.action_right, setter.action_right] if ahead_east else [shooter.action_left, setter.action_left]
	await hold_until(side, func(): return (blades.global_position.x >= ahead.global_position.x - 0.15) if ahead_east else (blades.global_position.x <= ahead.global_position.x + 0.15), 5.0)
	var ahead_north: bool = blades.global_position.z > ahead.global_position.z + 3.0
	var walk := [shooter.action_up, setter.action_up] if ahead_north else [shooter.action_down, setter.action_down]
	await hold_until(walk, func(): return (blades.global_position.z <= ahead.global_position.z + 3.0) if ahead_north else (blades.global_position.z >= ahead.global_position.z + 3.0), 5.0)
	await wait(0.3)
	print("INFO front blade lined up: grip %s, target %s" % [blades.global_position, ahead.global_position])
	await shot("blades_front_lined_up.png")
	Input.action_press(setter.action_up)
	await tap(setter.action_dash)
	await wait(0.15)
	Input.action_release(setter.action_up)
	await wait(0.3)
	check("real input: a dash forward cuts the enemy ahead with the front blade", not ahead.is_alive(), "grip now %s, target %s" % [blades.global_position, ahead.global_position])

	# And back: a dash backward cuts too, with the left blade.
	list = targets()
	var behind: Array = list.filter(func(e): return e.global_position.x < setter.global_position.x - 2.0)
	if not behind.is_empty():
		behind.sort_custom(func(a, b): return absf(a.global_position.x - setter.global_position.x) < absf(b.global_position.x - setter.global_position.x))
		var second: EnemyLocal = behind[0]
		await line_up_blade(-1.0, second.global_position.x)
		# Stretched out first: the catapult keeps its carriers 4 to 7.5 m apart, so at 4.5 m a dash back has no room.
		await hold_until([setter.action_up], func(): return Vector2(setter.global_position.x - shooter.global_position.x, setter.global_position.z - shooter.global_position.z).length() > 7.0, 3.0)
		var north: bool = setter.global_position.z > second.global_position.z - 1.0
		var both := [shooter.action_up, setter.action_up] if north else [shooter.action_down, setter.action_down]
		await hold_until(both, func(): return (setter.global_position.z < second.global_position.z - 1.0) if north else (setter.global_position.z > second.global_position.z - 1.0), 5.0)
		await wait(0.3)
		Input.action_press(setter.action_down)
		await tap(setter.action_dash)
		await wait(0.15)
		Input.action_release(setter.action_down)
		await wait(0.3)
		check("real input: a dash back toward the back carrier cuts too", not second.is_alive(), "front carrier %s, target %s" % [setter.global_position, second.global_position])
	check("still playing", state() == "playing", state())
	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
