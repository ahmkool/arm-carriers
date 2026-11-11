extends Node
## Test driver for the aviator gunner on world_playground.tscn. Run through godot.sh,
## see docs/level-creation-for-agents.md:
##   tools/level_gen/godot.sh test tools/level_gen/verify_aviator_gunner.gd res://src/world/levels/world_playground.tscn <out_dir>
## Checks that he waits to be woken, then aims his rifle at the carriers, plays the shoot animation and
## fires bolts, and that a rocket kills him outright: he has no shield.
## Uses the carriers' real buttons. Save tracking is disabled, so save.json stays untouched.

const SHOOT_ACTIVE := &"parameters/OneShot 2/internal_active"

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


func forward() -> Vector3:
	var f := bazooka.muzzle.global_basis.z
	f.y = 0.0
	return f.normalized()


func count_bolts() -> int:
	return world.get_children().filter(func(c): return c is FireballSpawn or c is Fireball).size()


func clear_bolts() -> void:
	for c in world.get_children():
		if c is FireballSpawn or c is Fireball:
			c.queue_free()
	await get_tree().physics_frame


func facing_error_degrees(enemy: EnemyLocal, point: Vector3) -> float:
	var facing := -enemy.global_basis.z
	var to := point - enemy.global_position
	return rad_to_deg(Vector3(facing.x, 0.0, facing.z).normalized().angle_to(Vector3(to.x, 0.0, to.z).normalized()))


## A close-up of `enemy`, since the playground camera follows the carriers.
func close_up(enemy: EnemyLocal, file_name: String) -> void:
	var cam := Camera3D.new()
	world.add_child(cam)
	var facing := -enemy.global_basis.z
	facing = Vector3(facing.x, 0.0, facing.z).normalized()
	cam.global_position = enemy.global_position + facing * 3.5 + facing.cross(Vector3.UP) * 2.5 + Vector3.UP * 1.8
	cam.look_at(enemy.global_position + Vector3.UP * 1.1)
	cam.make_current()
	await wait(0.05)
	await shot(file_name)
	cam.queue_free()
	world.get_node("CameraFollowRig/ShakePivot/Camera3D").make_current()


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
	var gunner: EnemyLocal = null
	# A checkpoint reset respawns enemies under generated names, so match the scene instead.
	for child in instanced().get_children():
		if child.scene_file_path.ends_with("enemy_aviator_gunner.tscn"):
			gunner = child
	check("the playground has the aviator gunner", gunner != null)
	if gunner == null:
		_finish()
		return
	# Leaves the gunner on his own.
	for other in instanced().get_children():
		if other != gunner:
			other.free()
	await check_shoots(gunner)
	await check_rocket_kills(gunner)
	_finish()


func _finish() -> void:
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_shoots(gunner: EnemyLocal) -> void:
	check("he waits until woken", not gunner.is_offensive)
	(world.get_node("Enemies/Prototype") as EnemyGroup).trigger(true)
	var cast := await wait_until(func(): return gunner.enemy_state_machine.is_in_state("casting"), 8.0)
	check("he starts a shot", cast)
	var anim := await wait_until(func(): return gunner.animation_tree.get(SHOOT_ACTIVE) == true, 2.0)
	check("the shoot animation plays", anim)
	await wait(0.25)
	await close_up(gunner, "gunner_shooting.png")
	var bolt := await wait_until(func(): return count_bolts() > 0, 3.0)
	check("he fires a bolt", bolt)
	var err := facing_error_degrees(gunner, gunner.target_player.global_position)
	check("he aims at the carriers", err < 20.0, "%.1f°" % err)
	await wait(1.0)
	await shot("gunner_overview.png")
	var flat := gunner.target_player.global_position - gunner.global_position
	print("INFO distance to target: %.1f m" % Vector2(flat.x, flat.z).length())


func check_rocket_kills(gunner: EnemyLocal) -> void:
	gunner.is_offensive = false
	gunner.speed = 0.0
	var origin := bazooka.muzzle.global_position
	var spot := NavigationServer3D.map_get_closest_point(gunner.navigation_agent.get_navigation_map(), origin + forward() * 7.0)
	gunner.global_position = Vector3(spot.x, gunner.global_position.y, spot.z)
	await wait(0.2)
	await clear_bolts()
	fired.clear()
	await tap(back.action_shoot)
	check("the back carrier fires a rocket", fired.size() == 1)
	await wait_until(func(): return not gunner.is_alive(), 4.0)
	check("a rocket kills him: he has no shield", not gunner.is_alive())
