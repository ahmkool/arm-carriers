extends Node
## Test driver for vent-only enemy shields. Run through godot.sh on two scenes,
## see docs/level-creation-for-agents.md:
## - world_local_space_station.tscn: the level's shielded robots, against the pulse rifle.
## - any level with another weapon, such as world_local_siege_bow.tscn: a shield removes itself.
## Uses the carriers' real buttons. Save tracking is disabled, so save.json stays untouched.

const ROBOT_SCENE := "res://src/enemy/enemy_robot.tscn"
const SHIELD_SCRIPT := "res://src/enemy/shield/enemy_shield.gd"

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var rifle: PulseRifleSpecifics
var back: PlayerLocal
var front: PlayerLocal


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
	get_tree().root.get_texture().get_image().save_png(out_dir + "/" + file_name)


func tap(action: String) -> void:
	Input.action_press(action)
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release(action)
	await get_tree().physics_frame


func hp(enemy: EnemyLocal) -> int:
	return Health.from_target(enemy).current_hp if is_instance_valid(enemy) else 0


func group_robots(group: String) -> Array:
	return world.get_node("Enemies/%s/InstancedEnemies" % group).get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func shielded_robots(group: String) -> Array:
	return group_robots(group).filter(func(e): return EnemyShield.is_shielded(e))


func bubble_count(enemy: EnemyLocal) -> int:
	var shield := EnemyShield.find_on(enemy)
	if shield == null:
		return 0
	return shield.get_children(true).filter(func(c): return c is MeshInstance3D).size()


func forward() -> Vector3:
	var f := rifle.muzzle.global_basis.z
	f.y = 0.0
	return f.normalized()


## Holds a robot in front of the muzzle so it can't wander out of the line of fire.
func pin(enemy: EnemyLocal, at: Vector3) -> void:
	enemy.speed = 0.0
	enemy.velocity = Vector3.ZERO
	enemy.global_position = Vector3(at.x, enemy.global_position.y, at.z)


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	for p in world.players.get_children():
		if p is PlayerLocal:
			p.get_node("Health").grant_invulnerability(9999.0)
	if world.get_active_weapon_id() != "pulse_rifle":
		await check_removed_with_other_weapon()
	else:
		await check_pulse_rifle_run()
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_removed_with_other_weapon() -> void:
	var robot := (load(ROBOT_SCENE) as PackedScene).instantiate() as EnemyLocal
	var shield := Node3D.new()
	shield.set_script(load(SHIELD_SCRIPT))
	robot.add_child(shield)
	world.get_node("Enemies").add_child(robot)
	await get_tree().process_frame
	await get_tree().process_frame
	print("INFO weapon: ", world.get_active_weapon_id())
	check("with another weapon a shield removes itself", EnemyShield.find_on(robot) == null)
	Health.apply_damage(robot, 1, robot.global_position + Vector3.FORWARD)
	check("so that weapon can hurt the robot", hp(robot) == 2, "hp %d" % hp(robot))


func check_pulse_rifle_run() -> void:
	var weapon := world.get_active_weapon()
	rifle = weapon.get_node("WeaponSpecifics") as PulseRifleSpecifics
	var info: CarryInfo = weapon.get_node("PickAndDropHandler").get_carry_info()
	back = info.main_carrier
	front = info.secondary_carrier
	check("both carriers hold the rifle", is_instance_valid(back) and is_instance_valid(front))
	var yard := shielded_robots("EnemyGroup2")
	var causeway := shielded_robots("EnemyGroup3")
	check("the yard has two shielded robots and the causeway one", yard.size() == 2 and causeway.size() == 1, "%d, %d" % [yard.size(), causeway.size()])
	check("the other robots have no shield", shielded_robots("EnemyGroup").is_empty())
	var robot: EnemyLocal = yard[0]
	pin(robot, rifle.muzzle.global_position + forward() * 4.0)
	await wait(0.3)
	await shot("shield_up.png")
	await check_bolts_bounce(robot)
	await check_vent_breaks(robot)
	await check_bolts_hurt_after(robot)
	check_fall_still_kills(yard[1])
	await check_reset_restores(robot)


func check_bolts_bounce(robot: EnemyLocal) -> void:
	var hits := [0]
	var on_fired := func(bolt: PulseBolt): bolt.spent.connect(func(hit: bool): hits[0] += int(hit))
	rifle.fired.connect(on_fired)
	Input.action_press(back.action_shoot)
	await wait(1.0)
	await shot("shield_absorbing.png")
	Input.action_release(back.action_shoot)
	await wait(0.3)
	rifle.fired.disconnect(on_fired)
	check("bolts reach the shielded robot", hits[0] >= 5, "%d hits" % hits[0])
	check("bolts don't hurt a shielded robot", hp(robot) == 3, "hp %d" % hp(robot))
	check("firing at a shield still heats the barrel", rifle.heat > 0.15, "heat %.2f" % rifle.heat)


func check_vent_breaks(robot: EnemyLocal) -> void:
	var heat := 0.35
	check("the test vent doesn't kill a full-health robot", PulseVent.get_damage(heat) < 3)
	pin(robot, rifle.muzzle.global_position + forward() * 3.0)
	await get_tree().physics_frame
	var distance_before := (robot.global_position - rifle.muzzle.global_position).length()
	rifle.heat = heat
	await tap(front.action_shoot)
	await wait(0.05)
	await shot("shield_shattered.png")
	check("the vent breaks the shield", not EnemyShield.is_shielded(robot))
	check("the vent hits the robot through it", hp(robot) == 3 - PulseVent.get_damage(heat), "hp %d" % hp(robot))
	await wait(0.4)
	var pushed := (robot.global_position - rifle.muzzle.global_position).length() - distance_before
	check("the vent shoves the robot", pushed > 1.0, "%.2f m" % pushed)
	check("the shield is gone after its shatter", EnemyShield.find_on(robot) == null)


func check_bolts_hurt_after(robot: EnemyLocal) -> void:
	pin(robot, rifle.muzzle.global_position + forward() * 4.0)
	await wait(0.2)
	await wait(PulseRifleSpecifics.HEAT_COOL_DELAY_SEC)
	Input.action_press(back.action_shoot)
	await wait_until(func(): return not robot.is_alive(), 2.0)
	Input.action_release(back.action_shoot)
	check("bolts kill the robot once its shield is down", not robot.is_alive(), "hp %d" % hp(robot))


func check_fall_still_kills(robot: EnemyLocal) -> void:
	Health.apply_damage(robot, 99, robot.global_position + Vector3.FORWARD)
	check("other damage can't get through a shield", robot.is_alive() and hp(robot) == 3)
	Health.from_target(robot).kill()
	check("falling out of the level still kills a shielded robot", not robot.is_alive())


## A respawn rebuilds the yard from its snapshot: shields come back, with one bubble each.
func check_reset_restores(_robot: EnemyLocal) -> void:
	var group := world.get_node("Enemies/EnemyGroup2") as NormalEnemyGroup
	group.reset()
	await wait(0.3)
	var shielded := shielded_robots("EnemyGroup2")
	check("a checkpoint reset brings the yard's shields back", shielded.size() == 2, str(shielded.size()))
	var bubbles: Array = shielded.map(func(e): return bubble_count(e))
	check("each restored shield has one bubble", bubbles.all(func(n): return n == 1), str(bubbles))
