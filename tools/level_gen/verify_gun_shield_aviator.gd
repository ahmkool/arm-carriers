extends Node
## Test driver for the gun-shielded aviator on world_playground.tscn. Run through godot.sh,
## see docs/level-creation-for-agents.md:
##   tools/level_gen/godot.sh test tools/level_gen/verify_gun_shield_aviator.gd res://src/world/levels/world_playground.tscn <out_dir>
## Checks that he wakes, keeps his shield on the carriers at a capped turn speed and shoots, that a
## rocket blowing up on his shield does nothing, and that one detonated beside or behind him kills him.
## Uses the carriers' real buttons. Save tracking is disabled, so save.json stays untouched.

const ENEMY_SCENE := "res://src/enemy/enemy_aviator_gun_shield.tscn"

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var bazooka: BazookaSpecifics
var back: PlayerLocal
var front: PlayerLocal
var fired: Array = []


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


func instanced() -> Node:
	return world.get_node("Enemies/Prototype/InstancedEnemies")


func aviators() -> Array:
	return instanced().get_children().filter(func(c): return c is EnemyLocal)


func forward() -> Vector3:
	var f := bazooka.muzzle.global_basis.z
	f.y = 0.0
	return f.normalized()


func on_ground(enemy: EnemyLocal, point: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(enemy.navigation_agent.get_navigation_map(), point)


## Holds an aviator still at `at`, shield turned toward `look_at_point`, and stops him acting so
## his own bolts can't set the rocket off early.
func pin(enemy: EnemyLocal, at: Vector3, look_at_point: Vector3) -> void:
	enemy.is_offensive = false
	enemy.speed = 0.0
	enemy.velocity = Vector3.ZERO
	var ground := on_ground(enemy, at)
	enemy.global_position = Vector3(ground.x, enemy.global_position.y, ground.z)
	var to := look_at_point - enemy.global_position
	enemy.global_basis = Basis.looking_at(Vector3(to.x, 0.0, to.z).normalized(), Vector3.UP)


func facing_error_degrees(enemy: EnemyLocal, point: Vector3) -> float:
	var guard := FrontalGuard.find_on(enemy)
	var to := point - enemy.global_position
	return rad_to_deg(guard.get_facing().angle_to(Vector3(to.x, 0.0, to.z).normalized()))


## Removes bolts still in flight: a rocket that meets one goes off early.
func clear_bolts() -> void:
	for c in world.get_children():
		if c is FireballSpawn or c is Fireball:
			c.queue_free()
	await get_tree().physics_frame


## A close-up of `enemy`, since the playground camera follows the carriers.
func close_up(enemy: EnemyLocal, file_name: String, from_side := false) -> void:
	var cam := Camera3D.new()
	world.add_child(cam)
	var facing := FrontalGuard.find_on(enemy).get_facing()
	var offset := facing * 4.5 + Vector3.UP * 2.2
	if from_side:
		offset = facing.cross(Vector3.UP) * 4.0 + facing * 2.5 + Vector3.UP * 2.0
	cam.global_position = enemy.global_position + offset
	cam.look_at(enemy.global_position + Vector3.UP * 1.1)
	cam.make_current()
	await wait(0.1)
	await shot(file_name)
	cam.queue_free()
	world.get_node("CameraFollowRig/ShakePivot/Camera3D").make_current()


func count_bolts() -> int:
	return world.get_children().filter(func(c): return c is FireballSpawn or c is Fireball).size()


func _run() -> void:
	var ok: bool = await wait_until(func(): return state() == "playing", 45.0)
	check("reaches Playing", ok, state())
	await wait(1.0)
	for p in world.players.get_children():
		if p is PlayerLocal:
			p.get_node("Health").grant_invulnerability(9999.0)
	var weapon := world.get_node("Weapon/Bazooka")
	bazooka = weapon.get_node("WeaponSpecifics") as BazookaSpecifics
	bazooka.fired.connect(func(r): fired.append(r))
	var carry: CarryInfo = weapon.get_node("PickAndDropHandler").get_carry_info()
	back = carry.main_carrier
	front = carry.secondary_carrier
	check("both carriers hold the bazooka", is_instance_valid(back) and is_instance_valid(front))
	# Other prototypes in the playground would shoot the rockets down, so they leave.
	for other in aviators().filter(func(e): return FrontalGuard.find_on(e) == null):
		other.free()
	check("the playground holds the gun-shielded aviator", aviators().size() == 1, str(aviators().size()))
	var aviator: EnemyLocal = aviators()[0]
	var guard := FrontalGuard.find_on(aviator)
	check("the aviator has a frontal guard wired to his health", guard != null and Health.from_target(aviator).guard == guard)
	await check_wakes_and_shoots(aviator)
	await check_turn_cap(aviator)
	await check_front_blast_blocked(aviator)
	await check_back_blast_kills(aviator)
	await check_side_blast_kills(aviator)
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_wakes_and_shoots(aviator: EnemyLocal) -> void:
	await wait(0.5)
	await shot("aviator_asleep.png")
	check("the aviator waits until woken", not aviator.is_offensive)
	(world.get_node("Enemies/Prototype") as EnemyGroup).trigger(true)
	await wait(0.3)
	check("the wake event makes him offensive", aviator.is_offensive)
	var saw_bolt := await wait_until(func(): return count_bolts() > 0, 8.0)
	await shot("aviator_shooting.png")
	await close_up(aviator, "closeup_front.png")
	await close_up(aviator, "closeup_side.png", true)
	check("he shoots from behind his shield", saw_bolt)
	var nearest := aviator.target_player.global_position if is_instance_valid(aviator.target_player) else front.global_position
	var err := facing_error_degrees(aviator, nearest)
	check("his shield faces the carriers", err < 25.0, "%.1f°" % err)


func check_turn_cap(aviator: EnemyLocal) -> void:
	var target := aviator.target_player.global_position
	var away := aviator.global_position * 2.0 - target
	aviator.global_basis = Basis.looking_at(Vector3(away.x - aviator.global_position.x, 0.0, away.z - aviator.global_position.z).normalized(), Vector3.UP)
	await get_tree().physics_frame
	var start := facing_error_degrees(aviator, target)
	await wait(0.5)
	var turned := start - facing_error_degrees(aviator, target)
	check("he turns round at no more than his capped speed", turned > 10.0 and turned <= aviator.max_turn_speed_degrees * 0.5 + 8.0, "%.1f° in 0.5 s" % turned)


func check_front_blast_blocked(aviator: EnemyLocal) -> void:
	var origin := bazooka.muzzle.global_position
	pin(aviator, origin + forward() * 7.0, origin)
	await wait(0.2)
	var blocks := [0]
	FrontalGuard.find_on(aviator).blocked.connect(func(_p): blocks[0] += 1)
	await clear_bolts()
	fired.clear()
	await tap(back.action_shoot)
	check("the back carrier fires a rocket", fired.size() == 1)
	if fired.is_empty():
		return
	var rocket: BazookaBulletLocal = fired[0]
	await wait_until(func(): return rocket.is_spent(), 4.0)
	await wait(0.05)
	await shot("front_blast_blocked.png")
	await wait(0.3)
	check("a rocket flown into his shield goes off on it", rocket.is_spent())
	check("the shield blocks the blast", blocks[0] >= 1, "%d blocks" % blocks[0])
	check("a blast in front of him does no damage", aviator.is_alive() and Health.from_target(aviator).current_hp == Health.from_target(aviator).max_hp)


func check_back_blast_kills(first: EnemyLocal) -> void:
	var muzzle := bazooka.muzzle.global_position
	pin(first, muzzle - forward() * 10.0, muzzle)
	var aviator := (load(ENEMY_SCENE) as PackedScene).instantiate() as EnemyLocal
	aviator.is_offensive = false
	instanced().add_child(aviator)
	await wait(2.3)
	var origin := bazooka.muzzle.global_position
	var side := forward().cross(Vector3.UP)
	pin(aviator, origin + forward() * 6.0 + side * 2.0, origin)
	await wait(0.2)
	await clear_bolts()
	fired.clear()
	await tap(back.action_shoot)
	if fired.is_empty():
		check("a second rocket fires", false)
		return
	var rocket: BazookaBulletLocal = fired[0]
	# Flies past his flank, then goes off behind him.
	await wait_until(func(): return (rocket.global_position - origin).dot(forward()) >= 8.0 or rocket.is_spent(), 4.0)
	check("the rocket flies past without touching him", not rocket.is_spent())
	await tap(front.action_shoot)
	await wait(0.05)
	await shot("back_blast.png")
	await wait(0.3)
	check("a blast behind him kills him", not aviator.is_alive())


func check_side_blast_kills(aviator: EnemyLocal) -> void:
	await wait(1.0)
	var origin := bazooka.muzzle.global_position
	var side := forward().cross(Vector3.UP)
	pin(aviator, origin + forward() * 6.0 - side * 2.2, origin)
	await wait(0.2)
	await clear_bolts()
	fired.clear()
	await tap(back.action_shoot)
	if fired.is_empty():
		check("a third rocket fires", false)
		return
	var rocket: BazookaBulletLocal = fired[0]
	await wait_until(func(): return (rocket.global_position - origin).dot(forward()) >= 6.0 or rocket.is_spent(), 4.0)
	check("the rocket draws level with him", not rocket.is_spent())
	var guard := FrontalGuard.find_on(aviator)
	print("INFO blast angle from his facing: %.1f°" % rad_to_deg(guard.get_facing().angle_to(Vector3(rocket.global_position.x - aviator.global_position.x, 0.0, rocket.global_position.z - aviator.global_position.z).normalized())))
	await tap(front.action_shoot)
	await wait(0.05)
	await shot("side_blast.png")
	await wait(0.3)
	check("a blast beside him kills him", not aviator.is_alive())
