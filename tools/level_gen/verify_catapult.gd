extends Node
## Test driver for the catapult in world_local_lava.tscn.
## Run through godot.sh, see docs/level-creation-for-agents.md.
## Uses real input where it matters. Save tracking is disabled, so save.json stays untouched.

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0

var catapult: Node3D
var specifics: CatapultSpecifics
var guide: CatapultAimGuide
var shooter: PlayerLocal
var setter: PlayerLocal
var shots: Array = []
var explosions: Array = []


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(200.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func protect_players() -> void:
	for p in players():
		p.get_node("Health").grant_invulnerability(9999.0)


func action(player: PlayerLocal, suffix: String) -> String:
	return "p%s_%s" % [player.device_id, suffix]


func hold(actions: Array, seconds: float) -> void:
	for a in actions:
		Input.action_press(a)
	await wait(seconds)
	for a in actions:
		Input.action_release(a)
	await get_tree().physics_frame


func gap() -> float:
	var d: Vector3 = setter.global_position - shooter.global_position
	return Vector2(d.x, d.z).length()


func on_screen(point: Vector3) -> bool:
	var cam := get_viewport().get_camera_3d()
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	return not cam.is_position_behind(point) and rect.has_point(cam.unproject_position(point))


func players_on_screen() -> int:
	return players().filter(func(p): return on_screen(p.global_position + Vector3.UP)).size()


func current_flight() -> Dictionary:
	return specifics.predict_flight(specifics.get_launch_angle_deg(gap()), shooter)


## Flat distance from the back carrier to where the bomb would land.
func throw_distance() -> float:
	var landing: Vector3 = current_flight().landing
	return Vector2(landing.x - shooter.global_position.x, landing.z - shooter.global_position.z).length()


func press_shoot() -> void:
	Input.action_press(shooter.action_shoot)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(shooter.action_shoot)
	await get_tree().physics_frame


func on_fired(bomb: CatapultBomb, launch_deg: float) -> void:
	shots.append(launch_deg)
	bomb.exploded.connect(func(at: Vector3): explosions.append(at))


func alive(group: String) -> Array:
	return world.get_node("Enemies/" + group).get_node("InstancedEnemies").get_children().filter(
		func(c): return c is EnemyLocal and c.is_alive())


## Walks the front carrier in or out until the ring's centre is level with `target` along the throw.
func aim_range_at(target: Vector3) -> float:
	var forward: Vector3 = specifics.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	for step in 40:
		var landing: Vector3 = current_flight().landing
		var error: float = (target - landing).dot(forward)
		if absf(error) < 0.6:
			return error
		var suffix := "up" if error > 0.0 else "down"
		await hold([action(setter, suffix)], 0.06)
		await wait(0.05)
	return (target - current_flight().landing).dot(forward)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	catapult = world.get_node("Weapon/Catapult") as Node3D
	specifics = catapult.get_node("WeaponSpecifics") as CatapultSpecifics
	guide = specifics.get_node("AimGuide") as CatapultAimGuide
	specifics.fired.connect(on_fired)
	await wait(1.0)
	var carry: CarryInfo = (catapult.get_node("PickAndDropHandler") as PickAndDropHandler).get_carry_info()
	check("both players carry the catapult", is_instance_valid(carry.main_carrier) and is_instance_valid(carry.secondary_carrier))
	shooter = carry.main_carrier
	setter = carry.secondary_carrier
	var forward: Vector3 = specifics.global_basis.z
	check("the catapult throws towards the level ahead", forward.z < -0.9, str(forward))
	check("the front carrier is ahead", (setter.global_position - shooter.global_position).dot(forward) > 3.0, "gap %.2f" % gap())
	check("loaded at the start", specifics.is_loaded())
	check("the landing ring shows while both carry it", guide.visible)
	var rest_distance := throw_distance()
	print("INFO rest gap=%.2f angle=%.1f distance=%.2f landing=%s" % [gap(), specifics.get_launch_angle_deg(gap()), rest_distance, current_flight().landing])
	check("the ring sits on the landing point", guide.global_position.distance_to(current_flight().landing) < 0.3)
	check("the ring is on screen", on_screen(guide.global_position))
	await shot("catapult_rest.png")

	# Closest together: the steepest, shortest lob.
	await hold([action(setter, "down"), action(shooter, "up")], 1.0)
	await wait(0.3)
	var near_distance := throw_distance()
	print("INFO close gap=%.2f angle=%.1f distance=%.2f" % [gap(), specifics.get_launch_angle_deg(gap()), near_distance])
	check("close together lobs steeply", specifics.get_launch_angle_deg(gap()) > 70.0, "%.1f deg" % specifics.get_launch_angle_deg(gap()))
	check("close together throws shorter", near_distance < rest_distance - 1.0, "%.2f vs %.2f" % [near_distance, rest_distance])
	await shot("catapult_close.png")

	# Stretched out: the flattest, longest throw.
	await hold([action(setter, "up"), action(shooter, "down")], 1.6)
	await wait(0.3)
	var far_distance := throw_distance()
	print("INFO far gap=%.2f angle=%.1f distance=%.2f" % [gap(), specifics.get_launch_angle_deg(gap()), far_distance])
	check("stretched out throws at about 45 degrees", specifics.get_launch_angle_deg(gap()) < 50.0, "%.1f deg gap %.2f" % [specifics.get_launch_angle_deg(gap()), gap()])
	check("stretched out throws furthest", far_distance > rest_distance + 3.0, "%.2f vs %.2f" % [far_distance, rest_distance])
	check("both carriers on screen at full stretch", players_on_screen() == 2, "%d/2" % players_on_screen())
	check("the far ring is on screen", on_screen(guide.global_position))
	await shot("catapult_far.png")

	# A real shot: the landing matches the ring.
	var predicted: Vector3 = current_flight().landing
	await press_shoot()
	await wait_until(func(): return shots.size() > 0, 1.0)
	check("shoot fires one bomb", shots.size() == 1, str(shots))
	check("the arm empties", not specifics.is_loaded())
	await wait(0.35)
	await shot("catapult_flight.png")
	await press_shoot()
	check("no second bomb while the arm winds back", shots.size() == 1, str(shots))
	ok = await wait_until(func(): return explosions.size() == 1, 4.0)
	check("the bomb explodes", ok)
	if ok:
		check("it lands where the ring was", explosions[0].distance_to(predicted) < 0.8, "%s vs %s" % [explosions[0], predicted])
	await shot("catapult_explosion.png")
	ok = await wait_until(func(): return specifics.is_loaded(), 3.0)
	check("the arm reloads", ok)

	# Aim at the practice group with the front carrier's distance, then fire for real.
	await hold([action(setter, "down"), action(shooter, "up")], 1.0)
	var targets := alive("EnemyGroup")
	targets.sort_custom(func(a, b): return absf(a.global_position.x - shooter.global_position.x) < absf(b.global_position.x - shooter.global_position.x))
	var target: EnemyLocal = targets[0]
	var before := targets.size()
	var error := await aim_range_at(target.global_position)
	print("INFO aimed at %s, error %.2f m, gap %.2f, landing %s" % [target.global_position, error, gap(), current_flight().landing])
	check("the front carrier can bring the ring onto an enemy", absf(error) < 1.0, "%.2f m" % error)
	await shot("catapult_aimed.png")
	await press_shoot()
	await wait(2.5)
	var after := alive("EnemyGroup").size()
	print("INFO practice group alive %d -> %d" % [before, after])
	check("an aimed bomb kills enemies", after < before, "%d -> %d" % [before, after])
	await shot("catapult_kill.png")

	# One carrier lets go.
	await wait_until(func(): return specifics.is_loaded(), 3.0)
	shots.clear()
	setter.carrying_weapon_data.can_carry_status = CarryingWeaponData.CanCarryStatus.NO_WEAPON_AVAILABLE
	await wait(0.2)
	await press_shoot()
	check("no throwing with a single carrier", shots.is_empty(), str(shots))
	check("the ring hides with a single carrier", not guide.visible)
	await shot("catapult_solo.png")

	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)
