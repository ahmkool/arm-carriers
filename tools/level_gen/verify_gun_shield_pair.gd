extends Node
## Test driver for two gun-shielded aviators standing side by side, on world_playground.tscn. Run through godot.sh:
##   tools/level_gen/godot.sh test tools/level_gen/verify_gun_shield_pair.gd res://src/world/levels/world_playground.tscn <out_dir>
## A real rocket is flown into one aviator's shield, at several spacings between the two, and every hit each of
## them takes is logged: where the blast was, its angle from his facing, and whether his shield blocked it.
## A rocket that blows up on a shield must hurt neither of them. Save tracking is disabled.

const ENEMY_SCENE := "res://src/enemy/enemy_aviator_gun_shield.tscn"
const SPACINGS := [1.6, 2.5, 3.5]
## How far each pair is turned off the rocket's line, as when the aviators face the other carrier.
const YAWS := [0.0, 25.0, -25.0, 40.0, -40.0]

var out_dir: String
var world: WorldLocal
var gsm: GameStateMachine
var fails := 0
var bazooka: BazookaSpecifics
var back: PlayerLocal
var fired: Array = []


func _ready() -> void:
	out_dir = OS.get_environment("VERIFY_OUT")
	world = get_tree().current_scene as WorldLocal
	world.skip_save = true
	GameSave.untrack_manager(world.checkpoint_manager)
	gsm = world.get_node("GameStateMachine") as GameStateMachine
	get_tree().create_timer(240.0).timeout.connect(func(): print("WATCHDOG quit"); get_tree().quit(2))
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


func forward() -> Vector3:
	var f := bazooka.muzzle.global_basis.z
	f.y = 0.0
	return f.normalized()


func instanced() -> Node:
	return world.get_node("Enemies/Prototype/InstancedEnemies")


func spawn_aviator(at: Vector3, look_at_point: Vector3, yaw_degrees := 0.0) -> EnemyLocal:
	var aviator := (load(ENEMY_SCENE) as PackedScene).instantiate() as EnemyLocal
	aviator.is_offensive = false
	instanced().add_child(aviator)
	var ground := NavigationServer3D.map_get_closest_point(aviator.navigation_agent.get_navigation_map(), at)
	aviator.global_position = Vector3(ground.x, aviator.global_position.y, ground.z)
	aviator.speed = 0.0
	var to := look_at_point - aviator.global_position
	var facing := Vector3(to.x, 0.0, to.z).normalized().rotated(Vector3.UP, deg_to_rad(yaw_degrees))
	aviator.global_basis = Basis.looking_at(facing, Vector3.UP)
	return aviator


## Logs every hit that reaches an aviator's health, blocked or not.
func watch(label: String, aviator: EnemyLocal, log: Array) -> void:
	var guard := FrontalGuard.find_on(aviator)
	var describe := func(source: Vector3) -> String:
		var to := source - aviator.global_position
		var flat := Vector3(to.x, 0.0, to.z)
		var angle := rad_to_deg(guard.get_facing().angle_to(flat.normalized()))
		return "%s: source %.1f m away, %.0f° from his facing" % [label, flat.length(), angle]
	guard.blocked.connect(func(source: Vector3): log.append("blocked " + describe.call(source)))
	Health.from_target(aviator).damaged.connect(func(amount: int, _remaining: int, source: Vector3): log.append("DAMAGED %d " % amount + describe.call(source)))


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
	back = (weapon.get_node("PickAndDropHandler").get_carry_info() as CarryInfo).main_carrier
	for child in instanced().get_children():
		child.free()
	for spacing in SPACINGS:
		for yaw in YAWS:
			await check_pair(spacing, yaw)
	print("RESULT fails=", fails)
	get_tree().quit(1 if fails > 0 else 0)


func check_pair(spacing: float, yaw: float) -> void:
	var origin := bazooka.muzzle.global_position
	var side := forward().cross(Vector3.UP)
	var target := spawn_aviator(origin + forward() * 7.0, origin, yaw)
	var neighbour := spawn_aviator(origin + forward() * 7.0 + side * spacing, origin, yaw)
	await wait(2.5)  # past their Spawning state
	var log: Array = []
	watch("target", target, log)
	watch("neighbour", neighbour, log)
	fired.clear()
	await tap(back.action_shoot)
	if fired.is_empty():
		check("a rocket fires", false)
		return
	var rocket: BazookaBulletLocal = fired[0]
	await wait_until(func(): return rocket.is_spent(), 4.0)
	await wait(0.05)
	await shot("pair_%.1fm_%+.0f.png" % [spacing, yaw])
	await wait(0.4)
	for line in log:
		print("INFO %.1f m apart, turned %+.0f°, %s" % [spacing, yaw, line])
	var label := "%.1f m apart, turned %+.0f°" % [spacing, yaw]
	check(label + ": the rocket spares the target", target.is_alive())
	check(label + ": and spares the neighbour", neighbour.is_alive())
	target.queue_free()
	neighbour.queue_free()
	await wait(0.5)
