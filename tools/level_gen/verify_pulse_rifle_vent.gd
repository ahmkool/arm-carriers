extends Node
## Test driver for the pulse rifle's heat and vent, on world_local_space_station.tscn.
## Run through godot.sh, see docs/level-creation-for-agents.md.
## Uses the carriers' real shoot buttons. Save tracking is disabled, so save.json stays untouched.

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


func living_enemies() -> Array:
	return world.get_node("Enemies/EnemyGroup/InstancedEnemies").get_children().filter(func(c): return c is EnemyLocal and c.is_alive())


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	for p in world.players.get_children():
		if p is PlayerLocal:
			p.get_node("Health").grant_invulnerability(9999.0)
	var weapon := world.get_active_weapon()
	rifle = weapon.get_node("WeaponSpecifics") as PulseRifleSpecifics
	var info: CarryInfo = weapon.get_node("PickAndDropHandler").get_carry_info()
	back = info.main_carrier
	front = info.secondary_carrier
	check("both carriers hold the rifle", is_instance_valid(back) and is_instance_valid(front))
	await check_heat_and_overheat()
	await check_dry_vent()
	await check_vent_blast()
	await check_overdrive()
	await check_weak_vent_shoves()
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_heat_and_overheat() -> void:
	var shots := [0]
	var overheats := [0]
	var on_fired := func(_bolt): shots[0] += 1
	var on_overheat := func(): overheats[0] += 1
	rifle.fired.connect(on_fired)
	rifle.overheated.connect(on_overheat)
	Input.action_press(back.action_shoot)
	await wait(2.0)
	check("2 s of fire heats the barrel without overheating", rifle.heat > 0.4 and overheats[0] == 0, "heat %.2f" % rifle.heat)
	await shot("rifle_hot.png")
	var hot: bool = await wait_until(func(): return overheats[0] > 0, 3.0)
	check("a held trigger overheats after about 3.6 s", hot, "%d shots" % shots[0])
	var at_lock: int = shots[0]
	await wait(1.2)
	check("an overheated rifle stops firing", shots[0] == at_lock, "%d extra" % (shots[0] - at_lock))
	await tap(front.action_shoot)
	check("an overheated rifle can't vent", rifle.is_overheated())
	var recovered: bool = await wait_until(func(): return not rifle.is_overheated(), 1.5)
	await wait(0.3)
	check("the lock ends and the held trigger fires again", recovered and shots[0] > at_lock)
	Input.action_release(back.action_shoot)
	rifle.fired.disconnect(on_fired)
	rifle.overheated.disconnect(on_overheat)
	await wait_until(func(): return rifle.heat <= 0.0, 4.0)
	check("the barrel cools on its own", rifle.heat <= 0.0, "heat %.2f" % rifle.heat)


func check_dry_vent() -> void:
	var vents := [0]
	var on_vent := func(_h, _c, _p): vents[0] += 1
	rifle.vented.connect(on_vent)
	await tap(front.action_shoot)
	rifle.vented.disconnect(on_vent)
	check("venting a cold barrel does nothing", vents[0] == 0)


## Lines robots up in front of the muzzle and has the front carrier vent a near-full barrel.
func check_vent_blast() -> void:
	var enemies := living_enemies().slice(0, 3)
	var forward := rifle.muzzle.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var side := forward.cross(Vector3.UP)
	var origin := rifle.muzzle.global_position
	var spots := [origin + forward * 2.5, origin + forward * 4.0 + side * 1.5, origin + forward * 5.5 - side * 1.5]
	var behind: EnemyLocal = living_enemies()[3]
	for i in enemies.size():
		_place(enemies[i], spots[i])
	_place(behind, origin - forward * 5.0)
	await wait(0.15)
	var hp_before: Array = enemies.map(func(e): return Health.from_target(e).current_hp)
	var behind_hp: int = Health.from_target(behind).current_hp
	var dist_before: Array = enemies.map(func(e): return _flat_distance(e, origin))
	var result := []
	var on_vent := func(h, c, p): result.append_array([h, c, p])
	rifle.vented.connect(on_vent)
	rifle.heat = 0.9
	await tap(front.action_shoot)
	await shot("rifle_vent.png")
	rifle.vented.disconnect(on_vent)
	check("the front carrier's shoot button vents", result.size() == 3)
	if result.size() < 3:
		return
	check("a vent at 90% heat is perfect", result[2] == true)
	check("the blast hits all three robots in the cone", result[1] == 3, str(result[1]))
	check("venting empties the barrel", rifle.heat == 0.0)
	check("the robot behind the rifle is untouched", Health.from_target(behind).current_hp == behind_hp)
	var expected := PulseVent.get_damage(0.9)
	for i in enemies.size():
		var e: EnemyLocal = enemies[i]
		var lost: int = hp_before[i] - Health.from_target(e).current_hp
		check("robot %d takes %d damage" % [i, expected], lost == mini(expected, hp_before[i]), "lost %d of %d" % [lost, hp_before[i]])
	await wait(0.3)
	for i in enemies.size():
		var e: EnemyLocal = enemies[i]
		if not e.is_alive():
			print("INFO robot %d died to the vent" % i)
			continue
		var pushed := _flat_distance(e, origin) - float(dist_before[i])
		check("robot %d is shoved away from the muzzle" % i, pushed > 1.0, "%.2f m" % pushed)


func check_overdrive() -> void:
	check("a perfect vent starts overdrive", rifle.is_in_overdrive())
	var shots := [0]
	var on_fired := func(_bolt): shots[0] += 1
	rifle.fired.connect(on_fired)
	Input.action_press(back.action_shoot)
	await wait(1.0)
	Input.action_release(back.action_shoot)
	rifle.fired.disconnect(on_fired)
	check("overdrive fires faster than 10 a second", shots[0] >= 13, str(shots[0]))
	check("overdrive bolts don't heat the barrel", rifle.heat < 0.05, "heat %.2f" % rifle.heat)


## A low-heat vent doesn't kill a full-health robot, so it shows the shove on its own.
func check_weak_vent_shoves() -> void:
	await wait(OVERDRIVE_WAIT)
	var enemy: EnemyLocal = living_enemies()[0]
	var forward := rifle.muzzle.global_basis.z
	forward.y = 0.0
	var origin := rifle.muzzle.global_position
	_place(enemy, origin + forward.normalized() * 2.0)
	await wait(0.15)
	var hp_before: int = Health.from_target(enemy).current_hp
	var dist_before := _flat_distance(enemy, origin)
	rifle.heat = 0.3
	await tap(front.action_shoot)
	await wait(0.3)
	var lost: int = hp_before - Health.from_target(enemy).current_hp
	print("INFO weak vent: robot had %d hp, lost %d" % [hp_before, lost])
	check("a 30%% vent deals %d damage" % PulseVent.get_damage(0.3), lost == PulseVent.get_damage(0.3), str(lost))
	check("a weak vent isn't perfect", not rifle.is_in_overdrive())
	if not enemy.is_alive():
		check("the weakly vented robot survives to be shoved", false)
		return
	var pushed := _flat_distance(enemy, origin) - dist_before
	check("the vent shoves the robot away from the muzzle", pushed > 1.0, "%.2f m" % pushed)


const OVERDRIVE_WAIT := 2.0


func _place(enemy: EnemyLocal, at: Vector3) -> void:
	enemy.velocity = Vector3.ZERO
	enemy.global_position = Vector3(at.x, enemy.global_position.y, at.z)


func _flat_distance(enemy: EnemyLocal, origin: Vector3) -> float:
	var d := enemy.global_position - origin
	return Vector2(d.x, d.z).length()
