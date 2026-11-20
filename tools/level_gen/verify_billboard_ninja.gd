extends Node
## Test driver for the billboard ninja in world_local_night_rooftops.tscn. The carriers are placed on Building 1's
## east side, facing the east tower, and use the real shoot buttons:
## - the ninja never wakes (Building 1's guards are harmless) and the camera frames the tower;
## - a star fired straight at the billboard hangs against it, and its kunai can't reach the ninja behind it;
## - the star itself can't hurt the ninja;
## - a star sent past the end of the billboard, slowed with the front carrier's held button until a blade points
##   at the ninja and then let go, kills it with a kunai; with Building 1's other two ninjas dead, bridge 1 rises.
## Run: tools/level_gen/godot.sh test tools/level_gen/verify_billboard_ninja.gd res://src/world/levels/world_local_night_rooftops.tscn <out_dir> 200

const PANEL := Vector3(21.8, -1.0, 7.5)
## Flat distance from the front carrier to where the star hangs: 1.82 m to the muzzle plus the star's 9 m.
const FRONT_TO_HANG := 10.82
## Carriers stand this far north of the launcher's line (CarryInfo positions are 0.953 m to the gun's right).
const CARRIER_SIDE := 0.953
const CARRY_LENGTH := 3.2
## A blade this close to the bearing to the ninja is lined up, in radians.
const AIM_TOLERANCE := 0.06
const ATTEMPTS := 4

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(180.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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
		await get_tree().physics_frame
	return cond.call()


func shot(file_name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func protect_players() -> void:
	for p in world.players.get_children():
		if p is PlayerLocal:
			p.get_node("Health").grant_invulnerability(9999.0)


func launcher() -> ShurikenLauncherSpecifics:
	return world.get_active_weapon().get_node("WeaponSpecifics") as ShurikenLauncherSpecifics


## [back carrier, front carrier].
func carriers() -> Array[PlayerLocal]:
	var carry_info: CarryInfo = world.get_active_weapon().get_node("PickAndDropHandler").get_carry_info()
	return [carry_info.main_carrier, carry_info.secondary_carrier]


func ninja() -> EnemyLocal:
	var list := building1().filter(func(c): return c.behavior is NinjaPeekerBehavior)
	return null if list.is_empty() else list[0]


func building1() -> Array:
	return world.get_node("Enemies/Building1/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal)


func ninja_hp() -> int:
	var n := ninja()
	if n == null or not is_instance_valid(n):
		return 0
	return Health.from_target(n).current_hp


func peeker() -> NinjaPeekerBehavior:
	return ninja().behavior as NinjaPeekerBehavior


func bridge_up() -> bool:
	var bay := world.get_node("Level/Bridges").get_child(0)
	return not (bay.get_node("AnimatableBody3D/CollisionShape3D") as CollisionShape3D).disabled


func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


## Puts the carriers facing east so the launcher's line runs along z = `line_z` and the star hangs at `hang_x`.
func aim_from(hang_x: float, line_z: float) -> void:
	var c := carriers()
	var front_x := hang_x - FRONT_TO_HANG
	var z := line_z - CARRIER_SIDE
	for p in c:
		p.velocity = Vector3.ZERO
	c[1].global_position = Vector3(front_x, c[1].global_position.y, z)
	c[0].global_position = Vector3(front_x - CARRY_LENGTH, c[0].global_position.y, z)
	await wait(0.8)
	var muzzle := launcher().muzzle
	info("muzzle at (%.2f, %.2f) heading (%.2f, %.2f)" % [muzzle.global_position.x, muzzle.global_position.z, muzzle.global_basis.z.x, muzzle.global_basis.z.z])


func fire() -> Shuriken:
	await wait_until(func(): return launcher().is_loaded(), 3.0)
	var fired: Array = [null]
	var on_launch := func(s: Shuriken): fired[0] = s
	launcher().shuriken_launched.connect(on_launch)
	await tap(carriers()[0].action_shoot)
	launcher().shuriken_launched.disconnect(on_launch)
	return fired[0]


## The smallest angle between any of the star's blades and the bearing from the star to the ninja.
func blade_error(star: Shuriken) -> float:
	var visual: Node3D = null
	for child in star.get_children():
		if child is ShurikenVisual:
			visual = child
	var to_ninja := ninja().global_position - star.global_position
	var bearing := atan2(to_ninja.x, to_ninja.z)
	var blade := atan2(visual.global_basis.z.x, visual.global_basis.z.z)
	var best := INF
	for i in 4:
		best = minf(best, absf(angle_difference(blade + i * PI / 2.0, bearing)))
	return best


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	protect_players()
	await wait(1.0)
	check("the bridge to Building 2 starts lowered", not bridge_up())
	check("the billboard ninja waits on the east tower", ninja() != null and not ninja().is_offensive)
	# Building 1's other two ninjas: dead first, so the billboard ninja is the last one standing.
	for n in building1():
		if n != ninja():
			Health.apply_damage(n, 9999, n.global_position)

	# ---- Walk-in: the camera frames the tower; the ninja stays asleep behind the billboard. ----
	await aim_from(PANEL.x + 0.8, PANEL.z)
	var cam := get_viewport().get_camera_3d()
	await wait(1.5)
	var rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	check("the camera frames the billboard", rect.has_point(cam.unproject_position(PANEL + Vector3.UP)))
	await wait(3.0)
	var thrown := get_tree().get_nodes_in_group(Checkpoint.ENEMY_PROJECTILE_GROUP).filter(func(n): return n.name.begins_with("NinjaShuriken")).size()
	check("the billboard ninja stays asleep behind the billboard and throws nothing", not ninja().is_offensive and thrown == 0 and absf(ninja().global_position.z - PANEL.z) < 0.2)
	await shot("01_billboard.png")

	# ---- Straight at the billboard: the star hangs on it and the kunai can't get round. ----
	await wait_until(func(): return peeker().is_hidden(), 5.0)
	var blocked := await fire()
	check("a star is flung at the billboard", blocked != null)
	var hung: bool = await wait_until(func(): return not is_instance_valid(blocked) or blocked.is_hovering(), 2.0)
	var stop_x := blocked.global_position.x if is_instance_valid(blocked) else INF
	check("it hangs against the billboard, short of its range", hung and stop_x < PANEL.x - 0.8 and stop_x > PANEL.x - 1.4, "stopped at x %.2f" % stop_x)
	await shot("02_star_on_billboard.png")
	var hp_before := ninja_hp()
	blocked.scatter()
	await wait(0.6)
	check("kunai scattered in front of the billboard don't reach the ninja", ninja_hp() == hp_before, "hp %d -> %d" % [hp_before, ninja_hp()])

	# ---- The star can't hurt it: one flown right through it from behind the billboard. ----
	var through := Shuriken.new()
	world.add_child(through)
	through.launch(ninja().global_position + Vector3(0, 1.0, 5.0), Vector3.BACK * -1.0, 15.0, 8.0, 2, 0.0)
	await wait(0.8)
	check("the star itself doesn't hurt the ninja", ninja_hp() == hp_before, "hp %d" % ninja_hp())
	if is_instance_valid(through):
		through.queue_free()

	# ---- Past the end of the billboard, slow it, line a blade up with the ninja, let go. ----
	var killed := false
	var attempt := 0
	while attempt < ATTEMPTS and not killed:
		attempt += 1
		killed = await _try_combo(attempt)
	check("a star beside the billboard and a lined-up kunai kill the ninja", killed, "%d attempt(s)" % attempt)
	var rose: bool = await wait_until(bridge_up, 5.0)
	check("the bridge to Building 2 rises once the ninja falls", rose)
	await wait(1.0)
	await shot("04_bridge_up.png")
	print("RESULT fails=%d" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _try_combo(attempt: int) -> bool:
	await aim_from(PANEL.x + 0.9, PANEL.z + 2.6)
	await wait_until(func(): return peeker().is_hidden(), 5.0)
	var star := await fire()
	if star == null:
		return false
	await wait_until(func(): return not is_instance_valid(star) or star.is_hovering(), 2.0)
	if not is_instance_valid(star) or not star.is_hovering():
		info("attempt %d: the star didn't hang" % attempt)
		return false
	info("attempt %d: star hangs at (%.2f, %.2f)" % [attempt, star.global_position.x, star.global_position.z])
	var front := carriers()[1]
	Input.action_press(front.action_shoot)
	await wait_until(func(): return not is_instance_valid(star) or blade_error(star) < AIM_TOLERANCE, ShurikenLauncherSpecifics.MAX_HOLD_SEC - 0.1)
	if attempt == 1:
		await shot("03_slowed_aim.png")
	Input.action_release(front.action_shoot)
	return await wait_until(func(): return ninja_hp() <= 0, 1.0)
